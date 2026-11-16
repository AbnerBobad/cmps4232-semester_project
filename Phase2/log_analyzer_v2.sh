
#!/bin/bash
# =========================================================
# log_analyzer.sh - System Log Analysis and Audit Report
# CMPS4232 Systems Administration - Phase 2
#
# What this script does:
#   1. Analyzes SSH logs for failed login attempts
#   2. Identifies SSH connection timeouts
#   3. Identifies unauthorized sudo authentication attempts
#   4. Reports successful root privilege escalations by user
#   5. Displays the top memory-consuming processes
#   6. Saves the timestamp and audit report to a file
#
# Log source: /var/log/auth.log
# Report file: /var/log/audit_report.txt
# Command to run script: "$HOME/bin/log_analyzer.sh"
# =========================================================

log="/var/log/auth.log"
report="/var/log/audit_report.txt"

# Check whether the authentication log exists
if [ ! -f "$log" ]; then
    echo "Error: Authentication log not found."
    exit 1
fi

# ---------------------------------------------------------
# Step 1: Analyze failed SSH login attempts
#
# grep -i ignores case; -a treats the log as text
# -E enables extended regular expressions
# sshd.* matches SSH daemon log entries
# grep -v excludes entries containing "COMMAND"
# grep -c counts matching lines
# ---------------------------------------------------------

# Identify failed SSH authentication attempts
failed_ssh=$(sudo grep -iaE 'sshd.*(Failed password|Invalid user|maximum authentication attempts exceeded|PAM.*authentication failure)' "$log" | grep -v 'COMMAND')

# Count the matching entries
total_ssh=$(printf '%s\n' "$failed_ssh" | grep -c .)

echo "$total_ssh Failed SSH login attempts:"

# Display matching log entries with indentation
printf '%s\n' "$failed_ssh" | sed 's/^/    /'

# ---------------------------------------------------------
# Identify SSH connection timeouts separately
#
# Timeout events are connection problems and are not
# necessarily failed authentication attempts
# ---------------------------------------------------------

# Identify SSH timeout entries
timeout=$(sudo grep -iaE 'sshd.*(Timeout|timed out)' "$log" | grep -v 'COMMAND')

# Count matching timeout entries
total_timeout=$(printf '%s\n' "$timeout" | grep -c .)

echo "$total_timeout SSH connection timeouts:"

# Display matching timeout entries
printf '%s\n' "$timeout" | sed 's/^/    /'

# ---------------------------------------------------------
# Step 2: Identify unauthorized sudo authentication attempts
#
# Search for authentication and authorization failures
# These include incorrect passwords, authentication failures,
# users not in sudoers, and unauthorized commands
#
# grep -i ignores case
# -a treats the log as text
# -E enables extended regular expressions
# grep -v excludes entries containing "COMMAND"
# ---------------------------------------------------------

# Identify sudo authentication and authorization failures
sudo_failures=$(sudo grep -iaE 'sudo.*(authentication failure|incorrect password|not in sudoers|not allowed to execute|conversation failed)' "$log" | grep -v 'COMMAND')

# Count matching entries
af=$(printf '%s\n' "$sudo_failures" | grep -c .)

echo "$af Unauthorized sudo attempts:"

# Display matching entries with indentation
printf '%s\n' "$sudo_failures" | sed 's/^/    /'

# ---------------------------------------------------------
# Step 3: Report successful root privilege escalations
#
# Search for successful root sessions opened through sudo
# grep -v excludes entries containing "COMMAND"
# AWK extracts the username following the word "by"
# substr() extracts the username
# sub() removes UID information
# An associative array counts sessions for each user
# ---------------------------------------------------------

echo "Successful root escalations:"

sudo grep -iaE 'sudo.*session opened for user root' "$log" | grep -v 'COMMAND' | awk '
{
    # Find the username responsible for opening the session
    if (match($0, /by [^ ]+/)) {

        # Extract the username
        user = substr($0, RSTART + 3, RLENGTH - 3)

        # Remove UID information if present
        sub(/\(uid=.*/, "", user)

        # Count successful root sessions for each user
        count[user]++
    }
}
END {
    # Display the total root escalations for each user
    for (user in count)
        print "Root escalations by " user ": " count[user]
}' | sed 's/^/    /'

# ---------------------------------------------------------
# Step 4: Identify the top memory-consuming processes
#
# ps displays currently running processes
# -e selects all processes
# -o specifies the columns to display
# --sort=-%mem sorts processes by descending memory usage
# head limits the output to the first 11 lines
# (1 header + 10 processes)
# AWK formats the selected process information
# ---------------------------------------------------------

echo "Top memory consuming processes:"

processes=$(ps -eo %mem,pid,user,comm --sort=-%mem | head -n 11 | awk '
NR == 1 {
    # Display column headings
    printf "%-8s %-8s %-15s %-20s\n", $1, $2, $3, $4
    next
}
{
    # Display memory usage, PID, username, and process name
    printf "%-8s %-8s %-15s %-20s\n", $1, $2, $3, $4
}' | sed 's/^/    /')

# Display the formatted process report
echo "$processes"

# ---------------------------------------------------------
# Step 5: Save the audit report
#
# date records when the report was generated
# -f checks whether the report file already exists
# touch creates the file if it does not exist
# tee -a appends the report without overwriting old entries
# /dev/null prevents tee from displaying the saved output
# ---------------------------------------------------------

# Capture the current date and time
daytime=$(date +"%Y-%m-%d %H:%M:%S")

# Create the report file if it does not already exist
if [ ! -f "$report" ]; then
    sudo touch "$report"
fi

# Append the timestamp and audit findings to the report
{
    echo "=================================================="
    echo "System Audit Report"
    echo "Generated: $daytime"
    echo "=================================================="

    echo
    echo "$total_ssh Failed SSH login attempts:"
    printf '%s\n' "$failed_ssh"

    echo
    echo "$total_timeout SSH connection timeouts:"
    printf '%s\n' "$timeout"

    echo
    echo "$af Unauthorized sudo attempts:"
    printf '%s\n' "$sudo_failures"

    echo
    echo "Successful root escalations:"
    sudo grep -iaE 'sudo.*session opened for user root' "$log" | grep -v 'COMMAND' | awk '
    {
        if (match($0, /by [^ ]+/)) {
            user = substr($0, RSTART + 3, RLENGTH - 3)
            sub(/\(uid=.*/, "", user)
            count[user]++
        }
    }
    END {
        for (user in count)
            print "Root escalations by " user ": " count[user]
    }'

    echo
    echo "Top memory consuming processes:"
    echo "$processes"

    echo
} | sudo tee -a "$report" > /dev/null

echo "Output saved to $report"
