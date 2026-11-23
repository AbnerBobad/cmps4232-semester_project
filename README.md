# CMPS4232 Semester Project

## Automated Ubuntu Infrastructure, Containerization, and Operations Management

**Course:** CMPS4232 - Systems Administration  
**Group:** 2

This repository contains Bash tools and configuration notes for the semester
project. The scripts are intended for an Ubuntu Server virtual machine.

## Project members

- Abner Bobadilla
- Chahiim Pop
- Joseph Koop

## Repository structure

### Phase 1 - Environment Foundation and User Security

- `Phase1/setup_srv.sh` creates the project groups and shared `/srv` directories.
- `Phase1/sys_init.sh` provisions user accounts and configures their Bash profiles.
- `Phase1/bashrc.template` contains the profile settings used by the provisioning script.
- `Phase1/commands.md` documents setup, group membership, and verification.

### Phase 2 - Log Analytics, Regex, and Job Automation

- `Phase2/log_analyzer.sh` displays authentication findings and appends a timestamp and process list to the audit report.
- `Phase2/process_watchdog.sh` monitors a named process and lowers its priority when configured limits are exceeded.
- `Phase2/commands.md` documents execution, cron scheduling, watchdog demonstration, and evidence collection.
- `Phase2/cron_entry.example` shows the midnight cron entry format.

### Phase 3 - Containerization, Networking, and Disaster Recovery

- `Phase3/Docker/` builds and runs the NGINX **SysAdmin Health Dashboard** with
  host port mapping, environment variables, a memory limit, and a persistent
  volume mount.
  - `Phase3/Docker/Dockerfile` builds the image.
  - `Phase3/Docker/nginx/default.conf.template` provides the NGINX configuration
    (variables are filled in at container start).
  - `Phase3/Docker/html/index.html` is the dashboard landing page.
  - `Phase3/Docker/deploy_dashboard.sh` rebuilds the image and recreates the
    container reproducibly.
  - `Phase3/Docker/README.md` is the full build, run, verification, and
    persistence guide.
- `Phase3/backup script/sys_backup.sh` creates timestamped compressed archives
  of host configuration, system logs, and Docker volumes, with priority
  throttling.
- `Phase3/net script/net_check.sh` collects interface, port, and connectivity
  metrics and appends them to the dashboard's mounted metrics folder.
- `Phase3/net script/README.md` documents the network diagnostics and how they
  reach the web dashboard.

## Phase 1 quick start

Run these commands from `Phase1/`:

```bash
chmod +x setup_srv.sh sys_init.sh
sudo ./setup_srv.sh
sudo ./sys_init.sh
```

Additional setup, membership, and evidence instructions are in `Phase1/commands.md`.

## Phase 2 quick start

Run these commands from `Phase2/`:

```bash
chmod +x log_analyzer.sh process_watchdog.sh
sudo ./log_analyzer.sh
```

Cron installation, watchdog usage, and evidence instructions are in
`Phase2/commands.md`.

## Phase 3 quick start (matches the Phase 4 live demo)

### 1. One-time setup (Docker, curl, and the persistent data folder)

```bash
sudo apt update && sudo apt install -y docker.io curl
sudo systemctl enable --now docker

sudo mkdir -p /srv/dashboard/metrics
sudo chown -R root:sysadmins /srv/dashboard      # requires the sysadmins group from Phase 1
sudo find /srv/dashboard -type d -exec chmod 2775 {} +
```

### 2. Docker service - build, run, verify

Phase 4: *"Run docker ps showing active container bindings."*

```bash
cd Phase3/Docker
chmod +x deploy_dashboard.sh
sudo ./deploy_dashboard.sh

# Key Phase 4 screenshot: running container, ports, mounts
sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Mounts}}'
curl -s http://localhost:8080/health
curl -sI http://localhost:8080/ | grep -i x-dashboard-env
```

Open `http://localhost:8080/` for the dashboard and
`http://localhost:8080/metrics/` for the network reports.

### 3. Verify persistence across a container restart

Phase 4: *"verify persistence by demonstrating volume data survival across container restarts."*

```bash
sudo docker exec dashboard sh -c 'echo "persisted at $(date)" > /usr/share/nginx/html/metrics/persist_test.txt'
sudo docker restart dashboard
curl http://localhost:8080/metrics/persist_test.txt

sudo docker rm -f dashboard
sudo ./deploy_dashboard.sh
curl http://localhost:8080/metrics/persist_test.txt   # still there
ls -l /srv/dashboard/metrics/
```

### 4. Backup utility - run and verify

Phase 4: *"Execute ./sys_backup.sh and verify archive creation."*

```bash
cd "Phase3/backup script"
chmod +x sys_backup.sh
sudo ./sys_backup.sh                    # prints "Backup complete."

ls -lah ~/backups
tar -tvf ~/backups/system_backup_*.tar.gz | head -20
gzip -t ~/backups/system_backup_*.tar.gz && echo "archive OK"
```

To prove the `renice` during the run, in a second terminal:

```bash
watch -n1 'ps -eo pid,ni,cmd | grep "[t]ar -czf"'
```

### 5. Network diagnostics - run and query the dashboard endpoint

Phase 4: *"Execute ./net_check.sh and query the container endpoint using curl http://localhost:8080/metrics/net_status.html."*

Align the script with the Docker mount and the Phase 4 endpoint once:

```bash
cd "Phase3/net script"
sed -i 's|^DASH_DATA=.*|DASH_DATA="/srv/dashboard/metrics"|' net_check.sh
sed -i 's|^OUTPUT_FILE=.*|OUTPUT_FILE="$DASH_DATA/net_status.html"|' net_check.sh
sed -i 's|^CONTAINER=.*|CONTAINER="dashboard"|' net_check.sh
```

Then run it and verify the endpoint:

```bash
chmod +x net_check.sh
sudo ./net_check.sh
curl -s http://localhost:8080/metrics/net_status.html | head -40
```

Build, port, memory, persistence, and evidence steps are in
`Phase3/Docker/README.md`. Backup details are in `Phase3/backup script/README.md`
and network diagnostic details are in `Phase3/net script/README.md`.

