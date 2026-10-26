#!/bin/bash
# process_watchdog.sh - Lower the priority of an overused process.
# Usage: sudo ./process_watchdog.sh NAME CPU_LIMIT MEM_LIMIT SECONDS CHECKS
# Example: sudo ./process_watchdog.sh yes 80 50 5 12
# This script uses renice; it does not kill processes.

LOG="/var/log/process_watchdog.log"

if [ "$EUID" -ne 0 ]; then
    echo "Please run this script with sudo." >&2
    exit 1
fi
if [ "$#" -ne 5 ]; then
    echo "Usage: sudo $0 PROCESS_NAME CPU_LIMIT MEM_LIMIT INTERVAL CHECKS" >&2
    exit 1
fi

PROCESS_NAME=$1
CPU_LIMIT=$2
MEM_LIMIT=$3
INTERVAL=$4
CHECKS=$5

if [[ ! "$PROCESS_NAME" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "Use a simple process name, such as firefox or yes." >&2
    exit 1
fi
for value in "$CPU_LIMIT" "$MEM_LIMIT" "$INTERVAL" "$CHECKS"; do
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        echo "CPU, memory, interval, and check values must be whole numbers." >&2
        exit 1
    fi
done
if (( CPU_LIMIT > 100 || MEM_LIMIT > 100 || INTERVAL < 1 || CHECKS < 1 )); then
    echo "Limits must be 0-100; interval and checks must be at least 1." >&2
    exit 1
fi

command -v ps >/dev/null 2>&1 || { echo "The ps command is required." >&2; exit 1; }
command -v renice >/dev/null 2>&1 || { echo "The renice command is required." >&2; exit 1; }
touch "$LOG" || { echo "Cannot write to $LOG." >&2; exit 1; }
chmod 640 "$LOG" || { echo "Cannot set permissions on $LOG." >&2; exit 1; }

log() {
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" | tee -a "$LOG"
}

log INFO "Watching '$PROCESS_NAME': CPU limit ${CPU_LIMIT}%, memory limit ${MEM_LIMIT}%, $CHECKS checks every $INTERVAL seconds."

check=1
while [ "$check" -le "$CHECKS" ]; do
    matches=$(ps -C "$PROCESS_NAME" -o pid=,%cpu=,%mem=,ni=,comm=)

    if [ -z "$matches" ]; then
        log INFO "Check $check/$CHECKS: no '$PROCESS_NAME' process is running."
    else
        while read -r pid cpu memory nice process; do
            [ -n "$pid" ] || continue
            over_limit=$(awk -v cpu="$cpu" -v memory="$memory" \
                -v cpu_limit="$CPU_LIMIT" -v mem_limit="$MEM_LIMIT" \
                'BEGIN { if (cpu > cpu_limit || memory > mem_limit) print "yes"; else print "no" }')

            if [ "$over_limit" = "yes" ]; then
                if (( nice < 10 )); then
                    if renice -n 10 -p "$pid" >/dev/null 2>&1; then
                        log WARN "PID $pid ($process): CPU ${cpu}%, memory ${memory}%; priority lowered to nice 10."
                    else
                        log ERROR "Could not change priority for PID $pid ($process)."
                    fi
                else
                    log INFO "PID $pid ($process) exceeded a limit but already has nice $nice."
                fi
            fi
        done <<< "$matches"
    fi

    if [ "$check" -lt "$CHECKS" ]; then sleep "$INTERVAL"; fi
    check=$((check + 1))
done

log INFO "Watchdog finished after $CHECKS checks."

