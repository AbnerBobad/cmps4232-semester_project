#!/bin/bash
# =========================================================
# log_analyzer.sh - System Log Analysis and Audit Report
# CMPS4232 Systems Administration - Phase 2
#
# What this script does:
#   1. Analyzes SSH logs for failed login attempts
#   2. Identifies unauthorized sudo authentication attempts
#   3. Reports successful root privilege escalations by user
#   4. Displays the top memory-consuming processes
#   5. Saves the timestamp and process report to an audit file
#
# Log source: /var/log/auth.log
# Report file: /var/log/audit_report.txt
# Command to run script: "$HOME/bin/log_analyzer.sh"
# =========================================================

log="/var/log/auth.log"

# ---------------------------------------------------------
# Step 1: Analyze failed SSH login attempts
# grep -i ignores case; -a treats the log as text
# -P enables Perl-compatible regular expressions
# -n displays line numbers; -v excludes lines containing
# "COMMAND" to prevent matching the script's own commands
# wc -l counts the matching lines
# ---------------------------------------------------------

# Count failed password, invalid user, and timeout events
fp=$(sudo grep -iaP 'ssh.+Failed password' "$log" | grep -v 'COMMAND' | wc -l)
iu=$(sudo grep -iaP 'ssh.+Invalid user' "$log" | grep -v 'COMMAND' | wc -l)
ta=$(sudo grep -iaP 'ssh.+Timeout' "$log" | grep -v 'COMMAND' | wc -l)

# Add the individual counts to get the total
total_ssh=$((fp+iu+ta))

echo "$total_ssh Failed SSH login attempts:"

# Display matching log entries for each SSH event
# sed adds indentation to make the report easier to read

echo "    $fp Failed password attempts:"
sudo grep -ianP 'ssh.+Failed password' "$log" | grep -v 'COMMAND' | sed 's/^/        /'

echo "    $iu Invalid user attempts:"
sudo grep -ianP 'ssh.+Invalid user' "$log" | grep -v 'COMMAND' | sed 's/^/        /'

echo "    $ta Timeout failures:"
sudo grep -ianP 'ssh.+Timeout' "$log" | grep -v 'COMMAND' | sed 's/^/        /'

# ---------------------------------------------------------
# Step 2: Identify unauthorized sudo authentication attempts
# Search the authentication log for sudo authentication
# failures and exclude lines containing "COMMAND"
# ---------------------------------------------------------

# Count the matching authentication failure entries
af=$(sudo grep -iaP 'sudo.+authentication failure' "$log" | grep -v 'COMMAND' | wc -l)

echo "$af Unauthorized sudo executions:"

# Display the matching log entries with indentation
sudo grep -ianP 'sudo.+authentication failure' "$log" | grep -v 'COMMAND' | sed 's/^/    /'

# ---------------------------------------------------------
# Step 3: Report successful root privilege escalations
# Search for sessions opened for the root user
# awk scans each matching line and looks for the word "by"
# The following field identifies the user who opened the
# root session; sub() removes the UID information
# An associative array counts sessions for each user
# ---------------------------------------------------------

echo "Successful root escalations:"

sudo grep -iaP 'session opened for user root' "$log" | grep -v 'COMMAND' | awk '/session opened for user root/ {
    for (i=1; i<=NF; i++){
        if ($i=="by"){
            user=$(i+1)
            sub(/\(uid=.*/, "", user)
            count[user]++
        }
    }
}
END{
    # Display the total root escalations for each user
    for (user in count)
        print "Root escalations by " user, ": " count[user]
}' | sed 's/^/    /'

# ---------------------------------------------------------
# Step 4: Identify the top memory-consuming processes
# top -b runs in batch mode without interactive display
# -n 1 collects one process snapshot
# -o %MEM sorts processes by memory usage
# head limits the output to the first 17 lines
# awk skips the header and formats selected process fields
# ---------------------------------------------------------

echo "Top memory consuming processes:"

processes=$(top -b -n 1 -o %MEM | head -n 17 | awk 'NR > 6 {
    printf "%-6s %-8s %-10s %-10s %-4s %-4s %-10s\n", $10, $1, $2, $12, $3, $4, $11
}' | sed 's/^/    /')

# Display the formatted process report
echo "$processes"

# ---------------------------------------------------------
# Step 5: Save the audit report
# date records when the report was generated
# -f checks whether the report file already exists
# touch creates the file if it does not exist
# tee -a appends the report without overwriting old entries
# /dev/null prevents tee from displaying the saved output
# ---------------------------------------------------------

# Capture the current date and time
daytime=$(date +"%Y-%m-%d %H:%M:%S")

# Create the report file if it does not already exist
if [ ! -f "/var/log/audit_report.txt" ]; then
    sudo touch /var/log/audit_report.txt
fi

# Append the timestamp and process report to the audit file
echo -e "$daytime\n $processes\n" | sudo tee -a /var/log/audit_report.txt > /dev/null

echo "Output saved to /var/log/audit_report.txt"
