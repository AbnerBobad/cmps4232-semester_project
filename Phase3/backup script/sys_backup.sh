#!/bin/bash
# =========================================================
# sys_backup.sh - Creates a backup for key system folders
# CMPS4232 Systems Administration - Phase 3
#
# What this script does:
#   1. Gathers the date and time
#   2. Creates an compressed archived timestamped backup that includes all three folders
#      a. /etc (host configuration directories)
#      b. /var/log (system logs)
#      c. /srv/dashboard/metrics (Docker container persistent volumes)
#   3. Runs it in the background
#   4. Pauses execution and changes the renice value to lesser priority
#   5. Waits until process is completed
#
# Backup is outputted to $HOME/backups/
# Command to run script: "$HOME/phase3/sys_backup.sh"
# =========================================================

# User-friendly status mesage
echo "Creating a compressed backup of /etc, /var/log, and /srv/dashboard/metrics..."

# Gets the date and time for the timestamp
timestamp=$(date +'%Y-%m-%d_%H-%M-%S')

# Creates a backup folder if necessary
mkdir -p "$HOME/backups"

# Creates compressed archived timestamped backup as a background process
sudo tar -czf "$HOME/backups/system_backup_${timestamp}.tar.gz" /etc /var/log /srv/dashboard/metrics &

# Gets the PID for the most recent process
tar_pid=$!

# The sudo kill and sleep commands are not needed for script execution but are included
# so the change can be visualled in top or htop by pausing the system 
sudo kill -STOP $tar_pid
sleep 7

# Changes the job priority to lesser priority to maintain system performance
sudo renice -n 10 -p $tar_pid

# Wait 7 more seconds, then resume the backup process
sleep 7
sudo kill -CONT $tar_pid

# Ensure process completes before exiting the script
wait "$tar_pid"

# Ensure backup was created successfully
if [ $? -eq 0 ] && gzip -t "$HOME/backups/system_backup_${timestamp}.tar.gz"; then
    echo "Backup complete."
else
    echo "Backup failed or archive is corrupted."
    exit 1
fi