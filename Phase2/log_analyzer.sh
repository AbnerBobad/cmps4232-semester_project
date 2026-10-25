#!/bin/bash

log="/var/log/auth.log"

# SSH Failed Logins

fp=$(sudo grep -iaP 'ssh.+Failed password' "$log" | grep -v 'COMMAND' | wc -l)
iu=$(sudo grep -iaP 'ssh.+Invalid user' "$log" | grep -v 'COMMAND' | wc -l)
ta=$(sudo grep -iaP 'ssh.+Timeout' "$log" | grep -v 'COMMAND' | wc -l)
total_ssh=$((fp+iu+ta))

echo "$total_ssh Failed SSH login attempts:"

echo "    $fp Failed password attempts:"
sudo grep -ianP 'ssh.+Failed password' "$log" | grep -v 'COMMAND' | sed 's/^/        /'

echo "    $iu Invalid user attempts:"
sudo grep -ianP 'ssh.+Invalid user' "$log" | grep -v 'COMMAND' | sed 's/^/        /'

echo "    $ta Timeout failures:"
sudo grep -ianP 'ssh.+Timeout' "$log" | grep -v 'COMMAND' | sed 's/^/        /'

# Unauthorized Sudo Executions

af=$(sudo grep -iaP 'sudo.+authentication failure' "$log" | grep -v 'COMMAND' | wc -l)
echo "$af Unauthorized sudo executions:"
sudo grep -ianP 'sudo.+authentication failure' "$log" | grep -v 'COMMAND' | sed 's/^/    /'

# Successful Root Escalations

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
	for (user in count)
		print "Root escalations by " user, ": " count[user]
}' | sed 's/^/    /'

# Top Memory Consuming Processes

echo "Top memory consuming processes:"
processes=$(top -b -n 1 -o %MEM | head -n 17 | awk 'NR > 6 {
	printf "%-6s %-8s %-10s %-10s %-4s %-4s %-10s\n", $10, $1, $2, $12, $3, $4, $11
}' | sed 's/^/    /')

echo "$processes"
daytime=$(date +"%Y-%m-%d %H:%M:%S")
if [ ! -f "/var/log/audit_report.txt" ]; then
	sudo touch /var/log/audit_report.txt
fi
echo -e "$daytime\n $processes\n" | sudo tee -a /var/log/audit_report.txt > /dev/null
echo "Output saved to /var/log/audit_report.txt"
