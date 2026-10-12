# cmps4232-semester_project - Group2

Automated Ubuntu Infrastructure, Containerization &
Operations Management Project **CMPS4232 - Systems Administration**.
Bash tooling for user/security provisioning, log analytics, process monitoring,
Docker services, and backups. Scripts are designed to run on an Ubuntu Server VM.

## Group 2 Members:
1. Abner Bobadilla
2. Chahiim Pop 
3. Joseph Koop

## Structure

- `Phase1/` - Environment foundation & user security management
  - `commands.md` - reference CLI commands used to build and verify the hierarchy
  - `sys_init.sh` - interactive user-provisioning script (deliverable)
  - `bashrc.template` - custom shell profile appended by `sys_init.sh`
- `Phase2/` - Log analytics, regex & job automation
- `Phase3/` - Containerization, networking & disaster recovery

Each phase folder pairs a `commands.md` (the manual commands, for the report and
live demonstration) with the actual deliverable script(s).

## Running in Ubuntu VM

```bash
sudo ./sys_init.sh
```

Provisioning output and errors are timestamped into `/var/log/sys_init.log`.
