# Phase 1 - Required Commands

Environment Foundation & User Security Management.

This guide follows the order for the current files in this folder:

- `setup_srv.sh` creates the project groups and shared `/srv` directories.
- `sys_init.sh` creates each user with its primary group, sets the initial
  password, forces a password change at first login, and configures `.bashrc`.
- The `usermod` commands below add each user's required secondary group.

Run these commands on the Ubuntu server from the `Phase1` folder.

## 1. Make the scripts executable

```bash
chmod +x setup_srv.sh sys_init.sh
```

## 2. Create the groups and shared directories

Run the setup script once:

```bash
sudo ./setup_srv.sh
```

It creates `sysadmins`, `developers`, and `auditors` if they do not already
exist. It creates `/srv/sysadmins`, `/srv/developers`, and `/srv/auditors`, sets
each directory's owner to `root` and its group to the matching project group,
then applies mode `2770`.

Mode `2770` gives the owner and group read, write, and directory access. Other
users receive no access. The leading `2` is the SGID bit, which makes new items
inherit the shared directory's group.

Verify the setup:

```bash
getent group sysadmins developers auditors
ls -ld /srv/sysadmins /srv/developers /srv/auditors
stat -c '%a %U %G %n' /srv/sysadmins /srv/developers /srv/auditors
```

Expected `stat` results are mode `2770`, owner `root`, and the corresponding
group name for each directory. In `ls -ld`, the permissions should look like
`drwxrws---`.

## 3. Create each team member with a primary group

Run the interactive script once for each user:

```bash
sudo ./sys_init.sh
```

Enter the username, primary group, and initial password when prompted. The
script checks the username and group, asks you to confirm the password, creates
the account, configures the profile, and requires a password change at first
login. Repeat the command for the other team members.

User assignment Example:

| Username | Primary group | Secondary group |
|---|---|---|
| `abnerbobadilla` | `sysadmins` | `developers` |
| `chahiimpop` | `developers` | `auditors` |
| `josephkoop` | `auditors` | `sysadmins` |

## 4. Add the secondary group memberships

After creating the users, run these commands. `-aG` adds a secondary group and
keeps the user's primary group unchanged. Use this if in initial Setup no secondary user was added.

```bash
sudo usermod -aG developers abnerbobadilla
sudo usermod -aG auditors chahiimpop
sudo usermod -aG sysadmins josephkoop
```

Verify each account's primary and secondary groups:

```bash
id abnerbobadilla
id chahiimpop
id josephkoop
```

## 5. Verify password expiry and the provisioning log

For each newly created user, verify the forced password change. For example:

```bash
sudo chage -l abnerbobadilla
```

The output should say the password must be changed. Then display the log:

```bash
sudo tail -n 40 /var/log/sys_init.log
```

The log has timestamps and separate `[INFO stdout]` and `[ERROR stderr]` entries.
The script also displays the latest log lines when it finishes.
