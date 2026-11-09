#!/bin/bash
# =====================================================================
# net_check.sh - Beginner-friendly network diagnostic script
#
# Concepts practiced:
#   * ip -s link : packets/bytes/errors per network interface
#   * ss         : which ports are LISTENING (open for connections)
#   * docker port: how container ports map to host ports
#   * ping/curl  : can we reach the outside world?
#
# Usage:  sudo ./net_check.sh
# =====================================================================

# ---------- 1. SETTINGS ----------------------------------------------
# This host folder is the SAME one mounted into the container with
# -v /opt/dashboard/data:/usr/share/nginx/html/data
# Anything written here instantly appears inside the container.
DASH_DATA="/opt/dashboard/data"
OUTPUT_FILE="$DASH_DATA/net_metrics.txt"
CONTAINER="health-dashboard"

mkdir -p "$DASH_DATA"

# ---------- 2. A HELPER TO PRINT SECTION TITLES ----------------------
title() {
    echo ""
    echo "----- $1 -----"
}

# ---------- 3. THE DIAGNOSTICS ---------------------------------------
# Everything inside { ... } is sent through "tee -a" at the end:
#   tee = show on screen AND save to a file
#   -a  = APPEND (add to the file instead of overwriting it)
{
    echo "=============================================="
    echo "Network check: $(date)   Host: $(hostname)"
    echo "=============================================="

    title "1. Network interfaces and IP addresses"
    ip -br addr          # -br = brief, one line per interface

    title "2. Interface statistics (bytes, packets, errors)"
    ip -s link           # look at RX (received) and TX (sent) numbers

    title "3. Listening ports"
    # t=TCP u=UDP l=listening n=show numbers p=show program name
    ss -tulnp

    title "4. Docker containers and port bindings"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    echo "Port mapping for '$CONTAINER':"
    docker port "$CONTAINER"

    title "5. External connectivity"
    # ping -c 2 sends 2 packets. "if" checks if the command succeeded.
    for HOST in 8.8.8.8 1.1.1.1 example.com; do
        if ping -c 2 -W 2 "$HOST" > /dev/null 2>&1; then
            echo "[ UP ]   $HOST is reachable"
        else
            echo "[DOWN]   $HOST is NOT reachable"
        fi
    done

    title "6. Web dashboard check"
    # curl -w prints just the HTTP status code (200 = success)
    CODE=$(curl -s -o /dev/null -m 3 -w "%{http_code}" http://localhost:8080/)
    echo "http://localhost:8080 returned HTTP $CODE"
    echo ""
} 2>&1 | tee -a "$OUTPUT_FILE"

echo "Results appended to: $OUTPUT_FILE"
echo "View them at: http://localhost:8080"
