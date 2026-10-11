#!/usr/bin/env bash
#
# sys_init.sh - CMPS4232 Phase 1
# Interactive user provisioning for the /srv group hierarchy.
#
# Prompts the administrator for a username, primary group, optional secondary
# groups, and an initial password. It then:
#   1. creates the primary/secondary groups if they do not already exist
#   2. creates the user account with the correct shell and home directory
#   3. sets the initial password
#   4. forces a password change on first login (chage)
#   5. appends custom aliases + prompt styling to the user's ~/.bashrc
#
# All normal output and error output is timestamped and appended to
# /var/log/sys_init.log (stdout via '>'/'>>', stderr via '2>'/'2>>').
#
# Usage: sudo ./sys_init.sh
#
set -uo pipefail

readonly LOG_FILE="/var/log/sys_init.log"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BASHRC_TEMPLATE="${SCRIPT_DIR}/bashrc.template"
readonly USER_SHELL="/bin/bash"
readonly USER_RE='^[a-z_][a-z0-9_-]{0,31}$'
readonly GROUP_RE='^[a-z_][a-z0-9_-]{0,31}$'
readonly MIN_PW_LEN=8

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
# Timestamp every line of stdout/stderr, keep a copy in the terminal (tee), and
# append everything to the log file. Process substitution gives us cleanly
# separated OUT/ERR streams inside a single log.
ts_stream() {
  local tag="$1" line
  while IFS= read -r line; do
    printf '%s [%s] %s\n' "$(date '+%F %T')" "$tag" "$line"
  done
}

die() { echo "ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Interactive helpers - prompts go to the terminal (/dev/tty), not the log
# ---------------------------------------------------------------------------
ask() {                 # ask "<prompt>" <varname>
  local __val
  printf '%s' "$1" > /dev/tty
  IFS= read -r __val < /dev/tty
  printf -v "$2" '%s' "$__val"
}

ask_secret() {          # ask_secret "<prompt>" <varname>
  local __val
  printf '%s' "$1" > /dev/tty
  IFS= read -rs __val < /dev/tty
  printf '\n' > /dev/tty
  printf -v "$2" '%s' "$__val"
}

# ---------------------------------------------------------------------------
# Install custom shell profile for a user
# ---------------------------------------------------------------------------
install_bashrc() {
  local user="$1" home group
  home="$(getent passwd "$user" | cut -d: -f6)"
  group="$(id -gn "$user")"

  [[ -n "$home" ]] || die "could not resolve home directory for '$user'"
  [[ -f "$BASHRC_TEMPLATE" ]] || die "bashrc template not found: $BASHRC_TEMPLATE"

  {
    printf '\n# --- CMPS4232 custom profile (added %s) ---\n' "$(date '+%F %T')"
    cat "$BASHRC_TEMPLATE"
  } >>"${home}/.bashrc" 2>>"$LOG_FILE" || die "could not update ${home}/.bashrc"

  chown "${user}:${group}" "${home}/.bashrc" >>"$LOG_FILE" 2>>"$LOG_FILE" \
    || die "could not set ownership on ${home}/.bashrc"

  echo "Installed custom .bashrc for '$user'."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  [[ $EUID -eq 0 ]] || { echo "Must be run as root: sudo $0" >&2; exit 1; }

  # Set up timestamped, separated logging to both the terminal and the log file.
  touch "$LOG_FILE" || { echo "Cannot write $LOG_FILE" >&2; exit 1; }
  exec >  >(ts_stream OUT | tee -a "$LOG_FILE")
  exec 2>  >(ts_stream ERR | tee -a "$LOG_FILE" >&2)

  echo "=== sys_init.sh start $(date '+%F %T') ==="
  echo "Requested by: ${SUDO_USER:-root}"

  local username pgroup sgroups password pw2 grp
  local -a _sec uargs

  # ---- username with validation ----
  while :; do
    ask "Enter new username: " username
    if [[ -z "$username" ]]; then
      echo "Validation: username cannot be empty."
    elif [[ ! "$username" =~ $USER_RE ]]; then
      echo "Validation: invalid username '$username' (lowercase letters, digits, _ and -)."
    elif id "$username" &>/dev/null; then
      echo "Validation: user '$username' already exists."
    else
      break
    fi
  done
  echo "Username accepted: $username"

  # ---- primary group with validation ----
  while :; do
    ask "Enter primary group: " pgroup
    if [[ -z "$pgroup" ]]; then
      echo "Validation: primary group cannot be empty."
    elif [[ ! "$pgroup" =~ $GROUP_RE ]]; then
      echo "Validation: invalid group name '$pgroup'."
    else
      break
    fi
  done

  # ---- optional secondary groups (comma-separated) ----
  ask "Enter secondary groups (comma-separated, blank for none): " sgroups

  # ---- password with validation ----
  while :; do
    ask_secret "Enter initial password: " password
    ask_secret "Confirm password: " pw2
    if [[ ${#password} -lt $MIN_PW_LEN ]]; then
      echo "Validation: password must be at least $MIN_PW_LEN characters."
    elif [[ "$password" != "$pw2" ]]; then
      echo "Validation: passwords do not match."
    else
      break
    fi
  done

  # ---- create the primary group if needed ----
  if getent group "$pgroup" >/dev/null 2>&1; then
    echo "Primary group '$pgroup' already exists."
  else
    groupadd "$pgroup" >>"$LOG_FILE" 2>>"$LOG_FILE" || die "failed to create group '$pgroup'"
    echo "Created primary group: $pgroup"
  fi

  # ---- create any secondary groups that are missing ----
  if [[ -n "$sgroups" ]]; then
    IFS=',' read -ra _sec <<< "$sgroups"
    for grp in "${_sec[@]}"; do
      grp="${grp// /}"
      [[ -z "$grp" ]] && continue
      if getent group "$grp" >/dev/null 2>&1; then
        echo "Secondary group '$grp' already exists."
      else
        groupadd "$grp" >>"$LOG_FILE" 2>>"$LOG_FILE" || die "failed to create group '$grp'"
        echo "Created secondary group: $grp"
      fi
    done
  fi

  # ---- create the user account ----
  uargs=( -m -s "$USER_SHELL" -g "$pgroup" )
  [[ -n "$sgroups" ]] && uargs+=( -G "$sgroups" )
  useradd "${uargs[@]}" "$username" >>"$LOG_FILE" 2>>"$LOG_FILE" \
    || die "useradd failed for '$username'"
  echo "Created user '$username' (primary group: $pgroup${sgroups:+, secondary: $sgroups})."

  # ---- set the initial password ----
  echo "$username:$password" | chpasswd >>"$LOG_FILE" 2>>"$LOG_FILE" \
    || die "failed to set password for '$username'"
  echo "Initial password set for '$username'."

  # ---- force change on first login + basic aging policy ----
  chage -d 0 -m 1 -M 90 -W 7 "$username" >>"$LOG_FILE" 2>>"$LOG_FILE" \
    || die "chage failed for '$username'"
  echo "Password aging enforced: '$username' must change password on first login."

  # ---- install the custom shell profile ----
  install_bashrc "$username"

  echo "=== sys_init.sh finished OK $(date '+%F %T') ==="

  # Give the background tee writers a moment to flush the log before exit.
  sleep 0.3
}

main "$@"
