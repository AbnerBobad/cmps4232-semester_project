#!/bin/bash
#==============================================================================
# sys_init.sh - Interactive, validated, logged user provisioning (Phase 1)
#------------------------------------------------------------------------------
# WHAT IT DOES
#   Prompts for username, primary group, optional secondary groups and an
#   initial password, then:
#     1. creates the account (home dir, /bin/bash, primary + secondary groups)
#     2. sets the password (via stdin, never on a command line)
#     3. applies password aging and FORCES a change at first login (chage -d 0)
#     4. appends aliases + a custom prompt to the user's ~/.bashrc
#     5. VERIFIES every step and prints the evidence on screen
#     6. rolls the account back automatically if any step fails
#
# FEEDBACK FIXES IMPLEMENTED
#   - Logging: every line is timestamped; stdout and stderr of each command are
#     captured SEPARATELY and tagged [INFO] [stdout] / [ERROR] [stderr].
#     The final log entries are DISPLAYED at the end of every run and can be
#     shown any time with  --show-log.
#   - Validation: every check prints a visible PASS/FAIL line. Run
#     --selftest to watch the validators reject bad input LIVE.
#   - Safe exit: any failure after the account exists triggers a rollback
#     (userdel -r) so no half-created accounts are left behind.
#
# USAGE
#   sudo ./sys_init.sh                 interactive provisioning
#   sudo ./sys_init.sh --selftest      demonstrate the input validation live
#        ./sys_init.sh --show-log [N]  print last N (default 30) log lines
#        ./sys_init.sh --help
#
# EXIT CODES
#   0 ok | 1 usage | 2 not root | 3 missing dependency/lock | 4 invalid input
#   5 provisioning failed (rolled back) | 130 interrupted
#==============================================================================

set -o pipefail      # a pipeline fails if ANY stage fails, not just the last
umask 022

#------------------------------- constants ------------------------------------
readonly SCRIPT_NAME="${0##*/}"
readonly LOG_FILE="/var/log/sys_init.log"
readonly LOCK_FILE="/var/lock/sys_init.lock"
readonly -a ALLOWED_GROUPS=(sysadmins developers auditors)
readonly -a RESERVED_NAMES=(root admin administrator daemon bin sys nobody sysadmins developers auditors)
readonly MAX_ATTEMPTS=3          # retries per prompt before giving up
readonly MIN_PASS_LEN=8
readonly PASS_MAX_DAYS=90        # force periodic change
readonly PASS_WARN_DAYS=7
readonly MARK_BEGIN="# >>> sys_init.sh managed block >>>"
readonly MARK_END="# <<< sys_init.sh managed block <<<"

readonly E_USAGE=1 E_NOTROOT=2 E_DEPS=3 E_INPUT=4 E_PROVISION=5

#------------------------------- globals --------------------------------------
NEW_USER="" PRIMARY_GROUP="" SECONDARY_GROUPS="" NEW_PASS=""
USER_CREATED=0       # set once useradd succeeds (used by rollback)
PROVISION_OK=0       # set only when EVERYTHING succeeded
VALIDATION_MSG=""    # validators put their human-readable reason here
TMP_DIR=""           # holds per-command stdout/stderr capture files

# Colours only when talking to a real terminal
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
    C_G=$'\e[32m' C_R=$'\e[31m' C_Y=$'\e[33m' C_B=$'\e[36m' C_0=$'\e[0m'
else
    C_G="" C_R="" C_Y="" C_B="" C_0=""
fi

#==============================================================================
# LOGGING LAYER
#==============================================================================
ts() { date '+%Y-%m-%d %H:%M:%S'; }

# _log LEVEL MESSAGE  ->  append one timestamped line to the log file.
#   '>>' APPENDS (never truncates) so history is preserved across runs.
_log() {
    local level=$1; shift
    printf '%s [%-5s] [pid:%d] [%s] %s\n' \
        "$(ts)" "$level" "$$" "${SUDO_USER:-${USER:-root}}" "$*" >> "$LOG_FILE" 2>/dev/null
}

# Console helpers. Normal messages -> STDOUT, problems -> STDERR (2>).
info() { _log INFO  "$*"; printf '%s[ OK ]%s %s\n'   "$C_G" "$C_0" "$*"; }
note() { _log INFO  "$*"; printf '%s[INFO]%s %s\n'   "$C_B" "$C_0" "$*"; }
warn() { _log WARN  "$*"; printf '%s[WARN]%s %s\n'   "$C_Y" "$C_0" "$*" >&2; }
err()  { _log ERROR "$*"; printf '%s[FAIL]%s %s\n'   "$C_R" "$C_0" "$*" >&2; }

# run_cmd "description" command args...
#   Runs a command with its STDOUT and STDERR sent to two DIFFERENT temp files
#   (>  and  2>), then copies each into the log with its own tag. This is how
#   the two streams stay separated and still end up in /var/log/sys_init.log.
#   Anything on stdin (e.g. a here-string) is passed through to the command.
run_cmd() {
    local desc=$1; shift
    local out_f="$TMP_DIR/stdout" err_f="$TMP_DIR/stderr" line rc

    "$@" > "$out_f" 2> "$err_f"          # <-- the two redirections
    rc=$?

    while IFS= read -r line; do [[ -n $line ]] && _log INFO  "[stdout] $line"; done < "$out_f"
    while IFS= read -r line; do [[ -n $line ]] && _log ERROR "[stderr] $line"; done < "$err_f"

    if (( rc == 0 )); then
        info "$desc"
        return 0
    fi
    err "FAILED: $desc (exit code $rc)"
    return "$rc"
}

#==============================================================================
# VALIDATION LAYER  (each validator returns 0/1 and sets VALIDATION_MSG)
#==============================================================================
in_array() { local needle=$1 e; shift; for e in "$@"; do [[ $e == "$needle" ]] && return 0; done; return 1; }

validate_username() {
    local u=$1
    VALIDATION_MSG=""
    [[ -n $u ]] || { VALIDATION_MSG="username must not be empty"; return 1; }
    # POSIX-style name: starts with letter/_, 3-32 chars, only [a-z0-9_-]
    [[ $u =~ ^[a-z_][a-z0-9_-]{2,31}$ ]] || { VALIDATION_MSG="'$u' is not a valid name (3-32 chars, a-z 0-9 _ -, must start with a letter or _)"; return 1; }
    in_array "$u" "${RESERVED_NAMES[@]}"  && { VALIDATION_MSG="'$u' is a reserved name"; return 1; }
    getent passwd "$u" >/dev/null         && { VALIDATION_MSG="user '$u' already exists (conflict)"; return 1; }
    getent group  "$u" >/dev/null         && { VALIDATION_MSG="a group named '$u' already exists (conflict)"; return 1; }
    return 0
}

validate_primary_group() {
    local g=$1
    VALIDATION_MSG=""
    [[ -n $g ]] || { VALIDATION_MSG="group must not be empty"; return 1; }
    in_array "$g" "${ALLOWED_GROUPS[@]}" || { VALIDATION_MSG="'$g' is not a project group (allowed: ${ALLOWED_GROUPS[*]})"; return 1; }
    getent group "$g" >/dev/null         || { VALIDATION_MSG="group '$g' does not exist - run setup_srv.sh first"; return 1; }
    return 0
}

# validate_secondary_groups "a, b" -> on success SECONDARY_GROUPS="a,b" (cleaned, de-duplicated)
validate_secondary_groups() {
    local raw=$1 g cleaned="" seen=","
    VALIDATION_MSG=""
    SECONDARY_GROUPS=""
    [[ -z ${raw// /} ]] && return 0                       # optional: empty is fine
    IFS=',' read -r -a parts <<< "$raw"
    for g in "${parts[@]}"; do
        g=${g// /}                                        # strip spaces
        [[ -z $g ]] && continue
        in_array "$g" "${ALLOWED_GROUPS[@]}" || { VALIDATION_MSG="'$g' is not a project group (allowed: ${ALLOWED_GROUPS[*]})"; return 1; }
        getent group "$g" >/dev/null         || { VALIDATION_MSG="group '$g' does not exist"; return 1; }
        [[ $g == "$PRIMARY_GROUP" ]]         && { VALIDATION_MSG="'$g' is already the primary group"; return 1; }
        [[ $seen == *",$g,"* ]]              && continue  # silently drop duplicates
        seen+="$g,"; cleaned+="${cleaned:+,}$g"
    done
    SECONDARY_GROUPS=$cleaned
    return 0
}

# validate_password PASSWORD USERNAME : length + complexity + not containing the username
validate_password() {
    local p=$1 u=$2
    VALIDATION_MSG=""
    (( ${#p} >= MIN_PASS_LEN ))  || { VALIDATION_MSG="password shorter than $MIN_PASS_LEN characters"; return 1; }
    [[ $p =~ [A-Z] ]]            || { VALIDATION_MSG="password needs an uppercase letter"; return 1; }
    [[ $p =~ [a-z] ]]            || { VALIDATION_MSG="password needs a lowercase letter"; return 1; }
    [[ $p =~ [0-9] ]]            || { VALIDATION_MSG="password needs a digit"; return 1; }
    [[ -n $u && ${p,,} == *"${u,,}"* ]] && { VALIDATION_MSG="password must not contain the username"; return 1; }
    return 0
}

#==============================================================================
# INTERACTIVE PROMPTS (each retries up to MAX_ATTEMPTS, then aborts safely)
#==============================================================================
prompt_username() {
    local n=0 input
    while (( n < MAX_ATTEMPTS )); do
        read -r -p "Enter new username: " input || { err "no input available (EOF)"; return 1; }
        if validate_username "$input"; then NEW_USER=$input; info "username '$NEW_USER' is valid and available"; return 0; fi
        err "$VALIDATION_MSG  (attempt $((++n))/$MAX_ATTEMPTS)"
    done
    return 1
}

prompt_primary_group() {
    local n=0 input g status=""
    for g in "${ALLOWED_GROUPS[@]}"; do
        getent group "$g" >/dev/null && status+="$g " || status+="$g(MISSING) "
    done
    note "Available project groups: $status"
    while (( n < MAX_ATTEMPTS )); do
        read -r -p "Enter primary group: " input || { err "no input available (EOF)"; return 1; }
        if validate_primary_group "$input"; then PRIMARY_GROUP=$input; info "primary group '$PRIMARY_GROUP' is valid"; return 0; fi
        err "$VALIDATION_MSG  (attempt $((++n))/$MAX_ATTEMPTS)"
    done
    return 1
}

prompt_secondary_groups() {
    local n=0 input
    while (( n < MAX_ATTEMPTS )); do
        read -r -p "Enter secondary groups, comma-separated (blank for none): " input || input=""
        if validate_secondary_groups "$input"; then
            info "secondary groups: ${SECONDARY_GROUPS:-none}"; return 0
        fi
        err "$VALIDATION_MSG  (attempt $((++n))/$MAX_ATTEMPTS)"
    done
    return 1
}

prompt_password() {
    local n=0 p1 p2
    while (( n < MAX_ATTEMPTS )); do
        read -r -s -p "Enter initial password (hidden): " p1 || { echo; err "no input available (EOF)"; return 1; }; echo
        read -r -s -p "Confirm initial password: "        p2 || { echo; err "no input available (EOF)"; return 1; }; echo
        if [[ $p1 != "$p2" ]]; then
            err "passwords do not match  (attempt $((++n))/$MAX_ATTEMPTS)"; continue
        fi
        if validate_password "$p1" "$NEW_USER"; then NEW_PASS=$p1; info "password meets complexity policy"; return 0; fi
        err "$VALIDATION_MSG  (attempt $((++n))/$MAX_ATTEMPTS)"
    done
    return 1
}

#==============================================================================
# PROVISIONING STEPS  (every step returns non-zero on failure -> rollback)
#==============================================================================
create_account() {
    local -a args=(-m -s /bin/bash -g "$PRIMARY_GROUP" -c "Provisioned by sys_init.sh")
    [[ -n $SECONDARY_GROUPS ]] && args+=(-G "$SECONDARY_GROUPS")
    run_cmd "account '$NEW_USER' created (primary: $PRIMARY_GROUP, secondary: ${SECONDARY_GROUPS:-none})" \
        useradd "${args[@]}" "$NEW_USER" || return 1
    USER_CREATED=1
}

set_password_and_aging() {
    # chpasswd reads "user:password" from STDIN, so the secret never appears in
    # 'ps' output or in the log (run_cmd only logs the description).
    run_cmd "initial password set" chpasswd <<< "${NEW_USER}:${NEW_PASS}" || return 1
    NEW_PASS=""                                            # wipe from memory ASAP

    run_cmd "password aging policy set (max ${PASS_MAX_DAYS}d, warn ${PASS_WARN_DAYS}d)" \
        chage -M "$PASS_MAX_DAYS" -W "$PASS_WARN_DAYS" "$NEW_USER" || return 1

    # chage -d 0 sets "last password change" to the epoch => password is
    # considered expired => the user MUST choose a new one at first login.
    run_cmd "password change FORCED at first login (chage -d 0)" chage -d 0 "$NEW_USER" || return 1
}

# Emits the aliases/prompt block that gets appended to ~/.bashrc.
# Quoted heredoc ('EOF') = nothing is expanded NOW; the user's shell expands it at login.
profile_block() {
    printf '\n%s\n# Provisioned: %s by sys_init.sh\n' "$MARK_BEGIN" "$(ts)"
    cat <<'EOF'
# ---- group collaboration: new files are group read/write (pairs with setgid /srv dirs) ----
umask 002
# ---- aliases ----
alias ll='ls -alF --color=auto'
alias la='ls -A'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias update='sudo apt update && sudo apt upgrade -y'
alias df='df -hT'
alias free='free -h'
alias ports='ss -tulpn'
alias myid='id; echo; groups'
# ---- history hardening ----
export HISTSIZE=5000
export HISTFILESIZE=10000
export HISTCONTROL=ignoreboth
export HISTTIMEFORMAT='%F %T '
shopt -s histappend
# ---- prompt: green user@host, yellow [primary group], blue working dir ----
PS1='\[\e[1;32m\]\u@\h\[\e[0m\] [\[\e[1;33m\]$(id -gn)\[\e[0m\]] \[\e[1;34m\]\w\[\e[0m\]\$ '
EOF
    printf '%s\n' "$MARK_END"
}

configure_shell_profile() {
    local home bashrc
    home=$(getent passwd "$NEW_USER" | cut -d: -f6)
    [[ -d $home ]] || { err "home directory for '$NEW_USER' not found"; return 1; }
    bashrc="$home/.bashrc"
    [[ -f $bashrc ]] || : > "$bashrc"                      # useradd -m normally copies /etc/skel/.bashrc

    if grep -qF "$MARK_BEGIN" "$bashrc"; then              # idempotent: never add the block twice
        warn ".bashrc already contains the managed block - skipped"
    else
        profile_block >> "$bashrc" 2> "$TMP_DIR/stderr" \
            || { err ".bashrc append failed: $(cat "$TMP_DIR/stderr")"; return 1; }
        info "aliases and custom prompt appended to $bashrc"
    fi
    run_cmd ".bashrc ownership set to $NEW_USER:$PRIMARY_GROUP" chown "$NEW_USER:$PRIMARY_GROUP" "$bashrc" || return 1
    run_cmd "home directory restricted to mode 750"             chmod 750 "$home"                          || return 1
}

# Visible verification: proves each requirement on screen (feedback item).
verify_account() {
    local failures=0 home groups_now lastchg

    id "$NEW_USER" >/dev/null 2>&1 \
        && info "VERIFY account exists: $(id "$NEW_USER")" || { err "VERIFY account missing"; ((failures++)); }

    [[ $(id -gn "$NEW_USER") == "$PRIMARY_GROUP" ]] \
        && info "VERIFY primary group = $PRIMARY_GROUP" || { err "VERIFY primary group mismatch"; ((failures++)); }

    if [[ -n $SECONDARY_GROUPS ]]; then
        groups_now=" $(id -nG "$NEW_USER") "
        local g
        for g in ${SECONDARY_GROUPS//,/ }; do
            [[ $groups_now == *" $g "* ]] && info "VERIFY member of secondary group $g" \
                                          || { err "VERIFY not in secondary group $g"; ((failures++)); }
        done
    fi

    # field 3 of /etc/shadow = days since epoch of last change; 0 => must change at next login
    lastchg=$(getent shadow "$NEW_USER" | cut -d: -f3)
    [[ $lastchg == 0 ]] && info "VERIFY password expiry enforced (shadow lastchg = 0)" \
                        || { err "VERIFY password expiry NOT enforced (lastchg=$lastchg)"; ((failures++)); }

    home=$(getent passwd "$NEW_USER" | cut -d: -f6)
    grep -qF "$MARK_BEGIN" "$home/.bashrc" 2>/dev/null \
        && info "VERIFY .bashrc customisation present" || { err "VERIFY .bashrc customisation missing"; ((failures++)); }

    (( failures == 0 ))
}

# Roll back a half-built account (called from the EXIT trap).
rollback() {
    if (( USER_CREATED == 1 && PROVISION_OK == 0 )) && [[ -n $NEW_USER ]]; then
        warn "Rolling back: removing incomplete account '$NEW_USER'"
        if userdel -r "$NEW_USER" >> "$LOG_FILE" 2>&1; then
            _log WARN "rollback complete for '$NEW_USER'"; echo "[WARN] rollback complete" >&2
        else
            _log ERROR "rollback FAILED for '$NEW_USER' - remove manually: userdel -r $NEW_USER"
            echo "[FAIL] rollback failed - run: sudo userdel -r $NEW_USER" >&2
        fi
    fi
}

cleanup() {                       # EXIT trap: runs on success, failure and signals
    rollback
    [[ -n $TMP_DIR && -d $TMP_DIR ]] && rm -rf "$TMP_DIR"
}

#==============================================================================
# SUPPORT COMMANDS
#==============================================================================
show_log() {
    local n=${1:-30}
    [[ $n =~ ^[0-9]+$ ]] || n=30
    echo "${C_B}===== last $n lines of $LOG_FILE =====${C_0}"
    if [[ -r $LOG_FILE ]]; then tail -n "$n" "$LOG_FILE"; else echo "(cannot read $LOG_FILE - try sudo)"; return 1; fi
    echo "${C_B}=======================================${C_0}"
}

# --selftest: feed deliberately BAD input to the validators and show the result live.
run_selftest() {
    local pass=0 fail=0 label expect rc
    t() {   # t "label" expected_rc command args...
        label=$1 expect=$2; shift 2
        "$@"; rc=$?
        if [[ $rc == "$expect" ]]; then
            printf '  %s[PASS]%s %-34s -> %s\n' "$C_G" "$C_0" "$label" "${VALIDATION_MSG:-accepted}"; ((pass++))
        else
            printf '  %s[FAIL]%s %-34s -> unexpected result (rc=%s)\n' "$C_R" "$C_0" "$label" "$rc"; ((fail++))
        fi
        _log INFO "SELFTEST $label rc=$rc msg='${VALIDATION_MSG:-accepted}'"
    }
    local grp_ok=1; getent group sysadmins >/dev/null && grp_ok=0

    note "Username validation"
    t "empty username"             1 validate_username ""
    t "too short (ab)"             1 validate_username "ab"
    t "uppercase (Alice)"          1 validate_username "Alice"
    t "starts with digit (9lives)" 1 validate_username "9lives"
    t "contains space"             1 validate_username "john doe"
    t "shell injection attempt"    1 validate_username 'a;rm -rf /'
    t "reserved name (root)"       1 validate_username "root"
    t "valid name (selftest_user)" 0 validate_username "selftest_user"

    note "Group validation"
    t "group not allowed (wheel)"  1 validate_primary_group "wheel"
    t "group missing (ghostgrp)"   1 validate_primary_group "ghostgrp"
    t "project group (sysadmins)"  "$grp_ok" validate_primary_group "sysadmins"

    note "Password validation"
    t "too short"                  1 validate_password "Ab1" "bob"
    t "no uppercase"               1 validate_password "alllowercase1" "bob"
    t "no digit"                   1 validate_password "NoDigitsHere" "bob"
    t "contains username"          1 validate_password "Alice2026Pass" "alice"
    t "strong password"            0 validate_password "Str0ngPassw0rd" "bob"

    echo; printf 'Self-test: %d passed, %d failed\n' "$pass" "$fail"
    _log INFO "SELFTEST finished: $pass passed, $fail failed"
    (( fail == 0 ))
}

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }

check_dependencies() {
    local c missing=()
    for c in useradd userdel chpasswd chage getent flock id mktemp; do command -v "$c" >/dev/null || missing+=("$c"); done
    (( ${#missing[@]} == 0 )) || { echo "Missing required commands: ${missing[*]}" >&2; exit $E_DEPS; }
}

init_logging() {
    if ! { touch "$LOG_FILE" && chmod 640 "$LOG_FILE"; } 2>/dev/null; then
        echo "Cannot write to $LOG_FILE" >&2; exit $E_DEPS
    fi
    _log INFO "===== $SCRIPT_NAME started (invoked by ${SUDO_USER:-root}) ====="
}

#==============================================================================
# MAIN
#==============================================================================
main() {
    local mode=provision
    case "${1:-}" in
        -h|--help)  usage; exit 0 ;;
        --show-log) show_log "${2:-30}"; exit $? ;;
        --selftest) mode=selftest ;;
        "")         ;;
        *)          echo "Unknown option: $1 (try --help)" >&2; exit $E_USAGE ;;
    esac

    (( EUID == 0 )) || { echo "This script must be run as root: sudo $0" >&2; exit $E_NOTROOT; }
    check_dependencies

    # Only one provisioning run at a time (file descriptor 9 holds the lock).
    exec 9> "$LOCK_FILE" || { echo "cannot open lock file" >&2; exit $E_DEPS; }
    flock -n 9 || { echo "Another sys_init.sh instance is running" >&2; exit $E_DEPS; }

    init_logging
    TMP_DIR=$(mktemp -d /tmp/sys_init.XXXXXX) || { err "cannot create temp dir"; exit $E_DEPS; }
    trap cleanup EXIT
    trap 'err "Interrupted by signal - aborting safely"; exit 130' INT TERM HUP

    if [[ $mode == selftest ]]; then run_selftest; exit $?; fi

    echo "${C_B}=== User provisioning (log: $LOG_FILE) ===${C_0}"

    # ---- collect + validate input (nothing is changed on the system yet) ----
    prompt_username        || { err "aborting: no valid username";        exit $E_INPUT; }
    prompt_primary_group   || { err "aborting: no valid primary group";   exit $E_INPUT; }
    prompt_secondary_groups|| { err "aborting: invalid secondary groups"; exit $E_INPUT; }
    prompt_password        || { err "aborting: no valid password";        exit $E_INPUT; }

    echo
    note "About to create: user=$NEW_USER primary=$PRIMARY_GROUP secondary=${SECONDARY_GROUPS:-none}"
    local answer; read -r -p "Proceed? [y/N]: " answer
    [[ ${answer,,} == y* ]] || { warn "cancelled by administrator - nothing changed"; exit 0; }

    # ---- provision (any failure -> non-zero -> EXIT trap rolls back) ----
    if create_account && set_password_and_aging && configure_shell_profile && verify_account; then
        PROVISION_OK=1
        _log INFO "SUCCESS: user '$NEW_USER' fully provisioned"
        echo; echo "${C_B}=== chage -l $NEW_USER ===${C_0}"; chage -l "$NEW_USER"
        echo; show_log 25
        echo; info "Provisioning of '$NEW_USER' finished successfully"
        exit 0
    fi

    err "Provisioning of '$NEW_USER' FAILED - see $LOG_FILE"
    echo; show_log 15
    exit $E_PROVISION
}

main "$@"