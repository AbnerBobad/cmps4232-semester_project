# sys_backup.sh - System Backup Script

CMPS4232 Systems Administration - Phase 3

---

## 1. What it does

1. Creates timestamped compressed archives of /etc, /var/log, and /srv/dashboard/metrics, all in one .tar.gz file.
2. These folders represent host configuration directories, system logs, and Docker container persistent volumes, respectively.
3. It renices the backup process with a value of 10 during execution to ensure it doesn't freeze up unnecessary resources.

## 2. Requirements

| Requirement | Why |
|---|---|
| Folder `/srv/dashboard/metrics` exists | It is the mounted folder the docker volumes are stored in |

## 3. How to run it

```bash
cd ~/phase2
nano sys_backup.sh (paste the script)
chmod +x sys_backup.sh      # only needed the first time
bash ./sys_backup.sh
```

The script will print "Backup complete." at the end if successful.

## 4. Verify

```bash
cd ~/backups
ls -la          # to show timestamped backup files
tar -tf name.tar.gz     # to view backup contents | replace 'name' with actual name of backup

