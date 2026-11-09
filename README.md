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

Phase 3 implementation is not included in this repository version.

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


