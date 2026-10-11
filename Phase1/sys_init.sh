#!/bin/bash
# =========================================================
# sys_init.sh - Interactive User Provisioning Script
# CMPS4232 Systems Administration - Phase 1
#
# What this script does:
#   1. Asks for a username, primary group, and password
#   2. Checks that the input is valid
#   3. Creates the user account (home dir, bash shell)
#   4. Forces a password change at first login (chage -d 0)
#   5. Adds aliases and a custom prompt to the user's .bashrc
#   6. Writes everything to /var/log/sys_init.log
#
# Usage: sudo ./sys_init.sh
# =========================================================

LOG="/var/log/sys_init.log"

# ---------------------------------------------------------
# Function: log
# Writes a line with date/time and a level (INFO or ERROR)
# to the log file. ">>" appends, so old entries are kept.
# ---------------------------------------------------------
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] $2" >> "$LOG"
}

# ---------------------------------------------------------
# Function: error_exit
# Shows an error on the screen (standard error),
# saves it in the log, and stops the script.
# ---------------------------------------------------------
error_exit() {
    echo "ERROR: $1" >&2
    log "ERROR" "$1"
    exit 1
}

# ---------------------------------------------------------
# Step 1: Check that the script is run as root
# ---------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run this script with sudo." >&2
    exit 1
fi

# Create the log file if it does not exist and restrict access
touch "$LOG"
chmod 640 "$LOG"
log "INFO" "Script started by ${SUDO_USER:-root}"

# ---------------------------------------------------------
# Step 2: Ask the administrator for the information
# ---------------------------------------------------------
echo "-----------------------------------------"
read -p "Enter a new username: " user_n
read -p "Enter the primary group: " group_n
read -s -p "Enter the initial password: " pass_n
echo

# ---------------------------------------------------------
# Step 3: Validate the input
# ---------------------------------------------------------
echo "-----------------------------------------"
echo "Checking input..."

# Username must not be empty
if [ -z "$user_n" ]; then
    error_exit "Username cannot be empty."
fi

# Username must use only lowercase letters, numbers, _ and -
if [[ ! "$user_n" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    error_exit "Invalid username '$user_n'. Use lowercase letters, numbers, _ or -."
fi

# Username must not already exist
if id "$user_n" &> /dev/null; then
    error_exit "User '$user_n' already exists."
fi

# Primary group must not be empty
if [ -z "$group_n" ]; then
    error_exit "Primary group cannot be empty."
fi

# Primary group must already exist
if ! getent group "$group_n" > /dev/null; then
    error_exit "Group '$group_n' does not exist."
fi

# Password must not be empty
if [ -z "$pass_n" ]; then
    error_exit "Password cannot be empty."
fi

echo "Input is valid."
log "INFO" "Input validated for user '$user_n' with primary group '$group_n'"

# ---------------------------------------------------------
# Step 4: Create the user (home dir + bash shell)
# >> appends standard output, 2>> appends errors
# ---------------------------------------------------------
echo "-----------------------------------------"
useradd -m -s /bin/bash -g "$group_n" "$user_n" 2>> "$LOG"

if [ $? -ne 0 ]; then
    error_exit "useradd failed for '$user_n'."
fi

echo "User $user_n created."
log "INFO" "User '$user_n' created (primary group: $group_n)"

# ---------------------------------------------------------
# Step 5: Set the initial password
# ---------------------------------------------------------
echo "$user_n:$pass_n" | chpasswd 2>> "$LOG"

if [ $? -ne 0 ]; then
    userdel -r "$user_n" 2>> "$LOG"
    error_exit "Could not set the password. User '$user_n' was removed."
fi

echo "Password set for $user_n."
log "INFO" "Initial password set for '$user_n'"

# ---------------------------------------------------------
# Step 6: Force a password change at first login
# -d 0 means the password has expired (must change)
# ---------------------------------------------------------
chage -d 0 "$user_n" 2>> "$LOG"

if [ $? -ne 0 ]; then
    userdel -r "$user_n" 2>> "$LOG"
    error_exit "chage failed. User '$user_n' was removed."
fi

echo "Password must be changed at first login."
log "INFO" "Password expiry forced for '$user_n' (chage -d 0)"

# ---------------------------------------------------------
# Step 7: Add aliases and prompt styling to .bashrc
# >> appends to keep the original .bashrc
# ---------------------------------------------------------
cat >> "/home/$user_n/.bashrc" << 'EOF'

# ---- sys_init custom configuration ----
# New files are readable/writable by the group
umask 002

# Aliases
alias ll='ls -alF'
alias la='ls -A'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias update='sudo apt update && sudo apt upgrade -y'

# Prompt: green user@host, blue current directory
export PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '

# History
export HISTSIZE=5000
export HISTFILESIZE=10000
export HISTCONTROL=ignoreboth
shopt -s histappend
# ---- end sys_init configuration ----
EOF

# Fix ownership
chown "$user_n:$(id -gn "$user_n")" "/home/$user_n/.bashrc" 2>> "$LOG"

echo "Custom .bashrc configured."
log "INFO" ".bashrc configured for '$user_n'"

# ---------------------------------------------------------
# Step 8: Show the result
# ---------------------------------------------------------
echo "-----------------------------------------"
echo "User $user_n was created successfully!"
id "$user_n"
echo "-----------------------------------------"
chage -l "$user_n"

log "INFO" "Script finished successfully for '$user_n'"
