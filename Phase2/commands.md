# Phase 2 - Log Analysis, Cron, and Process Watchdog

## Scripts

- `log_analyzer.sh` searches `/var/log/auth.log` for failed SSH attempts,
  sudo authentication failures, and sessions opened as root. It displays those
  findings in the terminal and displays the top memory-consuming processes.
  It appends a timestamp and the process list to `/var/log/audit_report.txt`.
- `process_watchdog.sh` checks a named process for a fixed number of checks.
  When CPU or memory use exceeds its limit, it lowers the process priority to
  nice value `10` with `renice`. It records monitoring status and priority changes in
  `/var/log/process_watchdog.log`; it does not terminate processes.

Run the commands from `Phase2/` on the Ubuntu Server VM.

## 1. Make the scripts executable

```bash
chmod +x log_analyzer.sh process_watchdog.sh
```

## 2. Run the log analyzer

```bash
sudo ./log_analyzer.sh
```

The terminal displays counts and matching entries for:

1. SSH failed-password attempts, invalid users, and timeout events.
2. Sudo authentication failures.
3. Successful root sessions, counted by user.
4. The top memory-consuming processes.

The script appends the report timestamp and process list to the following file:

```bash
sudo tail -n 40 /var/log/audit_report.txt
```

**Report scope:** In the current script, authentication findings are displayed
in the terminal. They are not appended to `audit_report.txt`; that file contains
the timestamp and process list.

## 3. Schedule the analyzer at midnight

From this folder, obtain the script's absolute path and print the cron entry:

```bash
SCRIPT_PATH=$(realpath ./log_analyzer.sh)
printf '0 0 * * * /bin/bash %s >> /var/log/log_analyzer_cron.log 2>&1\n' "$SCRIPT_PATH"
```

Add the printed five-field entry to root's crontab:

```bash
sudo crontab -e
```

Save the entry, then verify it:

```bash
sudo crontab -l
systemctl is-active cron
```

The entry runs `log_analyzer.sh` every day at midnight. It appends the script's
standard output and errors to `/var/log/log_analyzer_cron.log`. The audit file
continues to receive the timestamp and process list.

The current analyzer invokes `sudo` internally. Cron cannot answer an
interactive password prompt, so test the exact scheduled command and inspect
its output before relying on the schedule:

```bash
SCRIPT_PATH=$(realpath ./log_analyzer.sh)
sudo bash -c '/bin/bash "$1" >> /var/log/log_analyzer_cron.log 2>&1' _ "$SCRIPT_PATH"
sudo tail -n 20 /var/log/log_analyzer_cron.log
```

## 4. Run the process watchdog

Usage:

```text
sudo ./process_watchdog.sh PROCESS_NAME CPU_LIMIT MEM_LIMIT INTERVAL CHECKS
```

- `PROCESS_NAME`: process name accepted by `ps -C`; use a short name such as
  `firefox` or `yes`.
- `CPU_LIMIT`: whole-number percentage from `0` to `100`.
- `MEM_LIMIT`: whole-number percentage from `0` to `100`.
- `INTERVAL`: whole number of seconds, at least `1`.
- `CHECKS`: number of checks, at least `1`.

The script defines no upper limit for the interval or check count. Approximate
runtime is `INTERVAL × (CHECKS - 1)` seconds because the first check is immediate.

For example, the following command checks `firefox` every five seconds for 12
checks:

```bash
sudo ./process_watchdog.sh firefox 80 70 5 12
```

The watchdog can also run in the background. `sudo -v` authenticates first so
`nohup` does not need to prompt after launch:

```bash
sudo -v
sudo nohup ./process_watchdog.sh firefox 80 70 5 12 \
  > /tmp/watchdog-output.txt 2>&1 < /dev/null &
WATCHDOG_PID=$!
echo "$WATCHDOG_PID"
```

Monitor its action log with:

```bash
sudo tail -f /var/log/process_watchdog.log
```

Press `Ctrl+C` to stop `tail`; this does not stop the watchdog. The watchdog
finishes automatically after the specified number of checks. A process raised
to nice value `10` remains at that priority after the watchdog exits. Restore a
process to nice value `0` with `sudo renice -n 0 -p PID`, using its process ID.

## 5. Watchdog demonstration

A temporary `yes` process provides a simple CPU workload. The watchdog checks
it five times, two seconds apart, using a `1%` CPU limit and a `100%` memory
limit. The process is stopped manually after the demonstration.

```bash
yes > /dev/null &
TEST_PID=$!
sudo -v
sudo nohup ./process_watchdog.sh yes 1 100 2 5 \
  > /tmp/watchdog-output.txt 2>&1 < /dev/null &
WATCHDOG_PID=$!
wait "$WATCHDOG_PID"
ps -p "$TEST_PID" -o pid,ni,comm
cat /tmp/watchdog-output.txt
kill "$TEST_PID"
sudo tail -n 20 /var/log/process_watchdog.log
```

In the completed test, the `yes` process used approximately `99.8%` CPU and
`0.1%` memory. The watchdog raised its nice value to `10`; `ps` confirmed the
change. Later checks reported that the process already had nice value `10`.
The final `kill` command stops only the temporary test workload, not a process
managed by the watchdog.


