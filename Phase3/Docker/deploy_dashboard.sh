#!/usr/bin/env bash
# Rebuilds the image and (re)creates the container with identical settings every time.
set -Eeuo pipefail

IMAGE="sysadmin-dashboard:1.0"
NAME="dashboard"
HOST_DIR="/srv/dashboard/metrics"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

[[ -d "$HOST_DIR" ]] || { echo "ERROR: $HOST_DIR missing. Create it first (Step 1)." >&2; exit 1; }
command -v docker >/dev/null || { echo "ERROR: docker not installed." >&2; exit 1; }

docker build -t "$IMAGE" "$SCRIPT_DIR"
docker rm -f "$NAME" >/dev/null 2>&1 || true     # safe: host data is NOT deleted

docker run -d --name "$NAME" --restart unless-stopped \
  -p 8080:80 \
  -e DASHBOARD_ENV=production -e SERVER_NAME=localhost \
  --memory 128m --memory-swap 128m \
  -v "$HOST_DIR":/usr/share/nginx/html/metrics \
  "$IMAGE"

docker ps --filter "name=$NAME"