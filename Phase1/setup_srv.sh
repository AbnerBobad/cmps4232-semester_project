#!/bin/bash
# setup_srv.sh - Set up the Phase 1 groups and shared directories.
# Run once from this folder: sudo ./setup_srv.sh

LOG="/var/log/sys_init.log"
PROJECT_GROUPS=(sysadmins developers auditors)

log() {
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" >> "$LOG"
}

if [ "$EUID" -ne 0 ]; then
    echo "Please run this script with sudo." >&2
    exit 1
fi

touch "$LOG" || { echo "Cannot write to $LOG" >&2; exit 1; }
chmod 640 "$LOG" || { echo "Cannot set permissions on $LOG" >&2; exit 1; }

# Keep each command's standard output and errors in separate log entries.
run_command() {
    description=$1
    shift
    out_file=$(mktemp) || { echo "Could not create temporary file." >&2; return 1; }
    err_file=$(mktemp) || { rm -f "$out_file"; echo "Could not create temporary file." >&2; return 1; }

    "$@" > "$out_file" 2> "$err_file"
    result=$?

    while IFS= read -r line || [ -n "$line" ]; do log "INFO stdout" "$line"; done < "$out_file"
    while IFS= read -r line || [ -n "$line" ]; do log "ERROR stderr" "$line"; done < "$err_file"
    cat "$out_file"
    if [ -s "$err_file" ]; then cat "$err_file" >&2; fi
    rm -f "$out_file" "$err_file"

    if [ "$result" -ne 0 ]; then
        echo "[FAIL] $description" >&2
        log "ERROR" "$description failed (exit $result)"
        return 1
    fi
    echo "[ OK ] $description"
    log "INFO" "$description"
}

log "INFO" "Shared group and directory setup started"
for group in "${PROJECT_GROUPS[@]}"; do
    if getent group "$group" >/dev/null; then
        echo "[ OK ] Group $group already exists"
        log "INFO" "Group $group already exists"
    else
        run_command "Created group $group" groupadd "$group" || exit 1
    fi

    directory="/srv/$group"
    run_command "Ensured directory exists: $directory" mkdir -p "$directory" || exit 1
    run_command "Set owner and group root:$group on $directory" chown "root:$group" "$directory" || exit 1
    # 2770 means owner/group can use the directory and other users have no access.
    # The leading 2 makes new items inherit the shared directory's group.
    run_command "Set permissions 2770 on $directory" chmod 2770 "$directory" || exit 1

    actual=$(stat -c '%a %U %G' "$directory")
    if [ "$actual" != "2770 root $group" ]; then
        echo "[FAIL] $directory has unexpected settings: $actual" >&2
        log "ERROR" "Verification failed for $directory: $actual"
        exit 1
    fi
    echo "[ OK ] Verified $directory: $actual"
    log "INFO" "Verified $directory: $actual"
done

echo
echo "Shared directory verification:"
run_command "Displayed /srv directory settings" ls -ld /srv/sysadmins /srv/developers /srv/auditors || exit 1
echo
echo "Recent log entries:"
tail -n 15 "$LOG"
log "INFO" "Shared group and directory setup finished"
