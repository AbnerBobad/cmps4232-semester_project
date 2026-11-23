#!/bin/bash
# =====================================================================
# net_check.sh - Network diagnostic script
# CMPS4232 Systems Administration - Phase 3
#
# Concepts practiced:
#   * ip -s link : packets/bytes/errors per network interface
#   * ss         : which ports are LISTENING (open for connections)
#   * docker port: how container ports map to host ports
#   * ping/curl  : can we reach the outside world?
#
# Output: appends a timestamped section to
#   /srv/dashboard/metrics/net_status.html
#   -> http://localhost:8080/metrics/net_status.html
#
# Usage:  sudo ./net_check.sh
# =====================================================================
set -u

# ---------- 1. SETTINGS ----------------------------------------------
# This host folder is the SAME one mounted into the container with
#   -v /srv/dashboard/metrics:/usr/share/nginx/html/metrics
# Anything written here instantly appears inside the container.
DASH_DATA="${DASH_DATA:-/srv/dashboard/metrics}"
OUTPUT_FILE="$DASH_DATA/net_status.html"
CONTAINER="${CONTAINER:-dashboard}"
HOST_PORT=8080

# ---------- 2. SAFETY CHECKS (error handling) ------------------------
# Must be root: docker commands and 'ss -p' need it
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: run with sudo: sudo ./net_check.sh" >&2
    exit 1
fi

# Make sure every tool used is installed
for cmd in ip ss ping curl docker; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: required command not found: $cmd" >&2
        exit 1
    fi
done

# Do NOT create the folder silently: a missing folder means the
# container mount is not set up, and writing elsewhere would hide that.
if [[ ! -d "$DASH_DATA" ]]; then
    echo "ERROR: $DASH_DATA does not exist." >&2
    echo "       Create it and start the container first (deploy_dashboard.sh)." >&2
    exit 1
fi

# Temporary files, removed automatically when the script exits
RAW="$(mktemp)"
trap 'rm -f "$RAW"' EXIT

# ---------- 3. A HELPER TO PRINT SECTION TITLES ----------------------
title() {
    echo ""
    echo "----- $1 -----"
}

# ---------- 4. THE DIAGNOSTICS ---------------------------------------
# Everything inside { ... } goes through "tee":
#   tee = show on screen AND save to a temporary file
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
    if ss -tln | awk 'NR>1 {print $4}' | grep -Eq "[:.]${HOST_PORT}\$"; then
        echo "[ UP ]   Host is listening on port $HOST_PORT"
    else
        echo "[FAIL]   Nothing is listening on port $HOST_PORT"
    fi

    title "4. Docker containers and port bindings"
    if docker inspect "$CONTAINER" >/dev/null 2>&1; then
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo ""
        echo "Port mapping for '$CONTAINER':"
        if docker port "CONTAINER"2>/dev/null|grep-q":{HOST_PORT}\$"; then
            docker port "$CONTAINER"
            echo "[ UP ]   Container port is bound to host port $HOST_PORT"
        else
            echo "[FAIL]   Container '$CONTAINER' has no binding on host port $HOST_PORT"
        fi
    else
        echo "[FAIL]   Container '$CONTAINER' not found"
    fi

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
    CODE=(curl-s-o/dev/null-m3-w"%httpcode""http://localhost:{HOST_PORT}/health")
    if [[ "$CODE" == "200" ]]; then
        echo "[ UP ]   http://localhost:${HOST_PORT}/health returned HTTP $CODE"
    else
        echo "[FAIL]   http://localhost:${HOST_PORT}/health returned HTTP $CODE"
    fi
    echo ""
} 2>&1 | tee "$RAW"

# ---------- 5. SUMMARY -----------------------------------------------
# Count the failed checks (lines starting with [DOWN] or [FAIL])
FAILS=$(grep -cE '^\[(DOWN|FAIL)\]' "$RAW" || true)

# ---------- 6. APPEND TO THE DASHBOARD FILE --------------------------
# First run: write the HTML page header once
if [[ ! -s "$OUTPUT_FILE" ]]; then
    cat > "$OUTPUT_FILE" <<'EOF'
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Network Status</title>
<style>
 body{font-family:sans-serif;max-width:960px;margin:1.5rem auto;padding:0 1rem}
 pre{background:#f4f4f4;padding:8px;overflow-x:auto}
</style></head><body>
<h1>Network Status History</h1>
<p>Each run appends a new section below.</p>
EOF
fi

# Every run: append one section. sed escapes & < > so the output is safe in HTML.
{
    echo "<section>"
    echo "<h2>Report - $(date '+%Y-%m-%d %H:%M:%S') - failed checks: $FAILS</h2>"
    echo "<pre>"
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$RAW"
    echo "</pre>"
    echo "<hr></section>"
} >> "$OUTPUT_FILE"

chmod 644 "$OUTPUT_FILE"    # the container's NGINX user must be able to read it

echo "Results appended to: $OUTPUT_FILE   (failed checks: $FAILS)"
echo "View them at: http://localhost:${HOST_PORT}/metrics/net_status.html"
