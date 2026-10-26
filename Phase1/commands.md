# Phase 1 - Setup and Verification

## Environment Foundation and User Security Management

This guide documents the setup sequence for the Phase 1 files:

- `setup_srv.sh` creates the project groups and shared `/srv` directories.
- `sys_init.sh` creates a user with a primary group, sets the initial password,
  forces a password change at first login, and configures `.bashrc`.
- `bashrc.template` contains the aliases and prompt settings added by `sys_init.sh`.

Run the commands from `Phase1/` on the Ubuntu Server VM.

## 1. Make the scripts executable

```bash
chmod +x setup_srv.sh sys_init.sh
```

## 2. Create the groups and shared directories

Run the setup script once:

```bash
sudo ./setup_srv.sh
```

The script creates `sysadmins`, `developers`, and `auditors` if they do not
already exist. It creates `/srv/sysadmins`, `/srv/developers`, and `/srv/auditors`,
sets each directory's owner to `root` and its group to the corresponding project
group, applies mode `2770`, and verifies the resulting settings.

Mode `2770` gives the owner and group read, write, and directory access. Other
users receive no access. The leading `2` is the SGID bit, which makes new items
inherit the shared directory's group.

Verify the groups and directories:

```bash
getent group sysadmins developers auditors
ls -ld /srv/sysadmins /srv/developers /srv/auditors
stat -c '%a %U %G %n' /srv/sysadmins /srv/developers /srv/auditors
```

Expected `stat` values are mode `2770`, owner `root`, and the corresponding
group name. In `ls -ld`, the permissions appear as `drwxrws---`.

## 3. Create team accounts

Run the interactive script once for each account:

```bash
sudo ./sys_init.sh
```

Provide the username, primary group, and initial password when prompted. The
script validates the inputs, confirms the password, creates the account,
configures the shell profile, and requires a password change at first login.

| Username | Primary group | Secondary group |
|---|---|---|
| `abnerbobadilla` | `sysadmins` | `developers` |
| `chahiimpop` | `developers` | `auditors` |
| `josephkoop` | `auditors` | `sysadmins` |

## 4. Assign secondary group memberships

After creating the accounts, add each required secondary group. The `-aG`
option adds the secondary group while preserving the primary group.

```bash
sudo usermod -aG developers abnerbobadilla
sudo usermod -aG auditors chahiimpop
sudo usermod -aG sysadmins josephkoop
```

Verify the account memberships:

```bash
id abnerbobadilla
id chahiimpop
id josephkoop
```

## 5. Verify password expiry and logs

Check the first-login password requirement for each provisioned account. Example:

```bash
sudo chage -l abnerbobadilla
```

The output should indicate that the password must be changed. Inspect the
provisioning log with:

```bash
sudo tail -n 40 /var/log/sys_init.log
```

Log entries include timestamps. Command output and errors use separate labels,
such as `[INFO stdout]` and `[ERROR stderr]`. The provisioning script displays
recent log entries after a successful run.
