# Phase 1 - Required Commands

Environment Foundation & User Security Management.

These are the raw CLI commands used to build and verify the Phase 1 hierarchy.
`sys_init.sh` automates the user-provisioning portion; this file is the manual
reference for the report and the live demonstration.

## 1. Create the secondary groups

```bash
sudo groupadd sysadmins
sudo groupadd developers
sudo groupadd auditors

# verify
getent group sysadmins developers auditors
```

## 2. Provision users (primary + secondary membership)

### 2.1 Add new users (home dir (-m) + bash shell (-s), (-N) prevents personal group creation)

```bash
sudo useradd -m -s /bin/bash -N abnerbobadilla
sudo useradd -m -s /bin/bash -N chahiimpop
sudo useradd -m -s /bin/bash -N josephkoop
```

### 2.2 Assign primary group (-g) and secondary groups (-aG - appends secondary groups)

```bash
sudo usermod -g sysadmins -aG developers abnerbobadilla
sudo usermod -g developers -aG auditors chahiimpop
sudo usermod -g auditors -aG sysadmins josephkoop
```

### 2.3 Set initial passwords

```bash
sudo passwd abnerbobadilla
sudo passwd chahiimpop
sudo passwd josephkoop
```

### 2.4 Verify

```bash
id abnerbobadilla
id chahiimpop
id josephkoop
```

## 3. Shared `/srv` directories + least-privilege permissions

```bash
sudo mkdir -p /srv/sysadmins /srv/developers /srv/auditors

# Apply strict directory ownership (chown) - owner=root, group=matching group
sudo chown root:sysadmins  /srv/sysadmins
sudo chown root:developers /srv/developers
sudo chown root:auditors   /srv/auditors

# Apply file permission bits (chmod)
# 770 = owner/group rwx, others none
# 2770 = SGID set, so new files inherit the directory's group
# This allows all group members to edit files created by their teammates
sudo chmod 2770 /srv/sysadmins /srv/developers /srv/auditors

# verify (deliverable screenshot)
ls -ld /srv/sysadmins /srv/developers /srv/auditors
```

## 4. Run the interactive provisioning script

```bash
sudo ./sys_init.sh
```

## 5. Verify enforced password aging (deliverable)

```bash
sudo chage -l <username>
# expect: Last password change : password must be changed
```

## 6. Inspect the provisioning log (deliverable)

```bash
sudo tail -n 40 /var/log/sys_init.log
```
