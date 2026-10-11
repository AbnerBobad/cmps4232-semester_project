# cmps4232-semester_project

Automated Ubuntu Server infrastructure for **CMPS4232 - Systems Administration**.
Bash tooling for user/security provisioning, log analytics, process monitoring,
Docker services, and backups. Scripts are designed to run on an Ubuntu Server VM.

## Structure

- `Phase1/` - Environment foundation & user security management
  - `commands.md` - reference CLI commands used to build and verify the hierarchy
  - `sys_init.sh` - interactive user-provisioning script (deliverable)
  - `bashrc.template` - custom shell profile appended by `sys_init.sh`
- `Phase2/` - Log analytics, regex & job automation
- `Phase3/` - Containerization, networking & disaster recovery

Each phase folder pairs a `commands.md` (the manual commands, for the report and
live demonstration) with the actual deliverable script(s).

## Running

```bash
sudo ./Phase1/sys_init.sh
```

Provisioning output and errors are timestamped into `/var/log/sys_init.log`.
