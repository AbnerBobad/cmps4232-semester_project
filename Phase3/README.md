# Phase 3 - Docker Service Deployment

This folder builds a small NGINX-based **SysAdmin Health Dashboard** and runs it
in a container with host port mapping, environment variables, a memory limit,
and a persistent volume mount.

The dashboard is also the endpoint that Phase 3's `net_check.sh` writes network
metrics to (`/metrics/net_status.html`).

## What's in this folder

| Path | Purpose |
|------|---------|
| `Dockerfile` | Recipe that builds the image |
| `nginx/default.conf.template` | NGINX config; `${VARIABLES}` filled in at container start |
| `html/index.html` | Landing page served by NGINX |
| `README.md` | This guide |

> Copy this whole folder to the Ubuntu server before starting (e.g. to `~/phase3`).

---

## Step 0 - Prerequisites

Install Docker and `curl`, and make sure the daemon is running:

```bash
sudo apt update && sudo apt install -y docker.io curl
sudo systemctl enable --now docker
docker --version          # screenshot-worthy proof Docker is installed
```

We use `sudo` with Docker below, so you do **not** have to deal with group
membership.

---

## Step 1 - Create the host directories (Data Persistence criterion)

```bash
sudo mkdir -p /srv/dashboard/metrics
getent group sysadmins >/dev/null || sudo groupadd sysadmins    # created in Phase 1
sudo chown -R root:sysadmins /srv/dashboard
sudo find /srv/dashboard -type d -exec chmod 2775 {} +
sudo find /srv/dashboard -type f -exec chmod 664 {} +
ls -ld /srv/dashboard /srv/dashboard/metrics
```

**Why these permissions?**

- `root:sysadmins` means only `root` and members of `sysadmins` can write.
- `2775` is `rwxrwsr-x`. The leading `2` (**setgid**) makes new files inherit
  the `sysadmins` group.
- "Others" can read because the NGINX process inside the container runs as a
  non-root user (uid 101) and needs read access to serve files. Nobody outside
  `sysadmins` can write.

Place the project files in the same layout as this folder:

```bash
mkdir -p ~/phase3/{html,nginx}
cd ~/phase3
# copy Dockerfile, html/index.html and nginx/default.conf.template here
```

---

## Step 2 - Understand the three files

A **Dockerfile** is a recipe for an **image** (a read-only template).
`docker run` turns an image into a **container** (a running instance).
Containers are disposable: anything written inside is lost when the container is
deleted unless it lives on a mount from the host. That is why we mount a host
folder.

### `Dockerfile`

Starts from the official NGINX Alpine image (small, about 50 MB), adds a custom
config and a landing page, and defines a health check.

### `nginx/default.conf.template`

The official NGINX image substitutes `${VARIABLES}` in files under
`/etc/nginx/templates/` at startup. This makes the environment variables
actually do something.

### `html/index.html`

The static landing page.

---

## Step 3 - Build the image

```bash
cd ~/phase3
sudo docker build -t sysadmin-dashboard:1.0 .
sudo docker images sysadmin-dashboard
```

**Screenshot this** - it proves the image built.

---

## Step 4 - Run the container

```bash
sudo docker run -d \
  --name dashboard \
  --restart unless-stopped \
  -p 8080:80 \
  -e DASHBOARD_ENV=production \
  -e SERVER_NAME=localhost \
  --memory 128m --memory-swap 128m \
  -v /srv/dashboard/metrics:/usr/share/nginx/html/metrics \
  sysadmin-dashboard:1.0
```

| Flag | Meaning |
|------|---------|
| `-d` | Run in the background |
| `--name dashboard` | Fixed name, so scripts can find it |
| `--restart unless-stopped` | Auto-restart after crash or reboot, unless you stopped it manually |
| `-p 8080:80` | Host port 8080 -> container port 80 |
| `-e` | Environment variables |
| `--memory 128m` | Hard RAM cap |
| `--memory-swap 128m` | Equal to memory, so no swap is allowed (a true hard cap) |
| `-v host:container` | Bind mount |

**Screenshot this** - it proves the container is running.

---

## Optional - Reproducible deployment script

Save this as `~/phase3/deploy_dashboard.sh`. It rebuilds the image and
(re)creates the container with identical settings every time.

```bash
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
```

```bash
chmod +x ~/phase3/deploy_dashboard.sh && sudo ~/phase3/deploy_dashboard.sh
```

---

## Verification (screenshot these)

```bash
# 1. Running, ports, mounts, health (the key screenshot)
sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Mounts}}'

# 2. Service responds, and the env var shows in the header
curl -s http://localhost:8080/health
curl -sI http://localhost:8080/ | grep -i x-dashboard-env

# 3. Environment variable inside the container
sudo docker exec dashboard env | grep -E 'DASHBOARD_ENV|SERVER_NAME'

# 4. Memory limit (bytes) and live usage
sudo docker inspect -f 'Memory limit: {{.HostConfig.Memory}} bytes' dashboard   # 134217728
sudo docker stats --no-stream dashboard                                         # LIMIT shows 128MiB

# 5. Restart policy and health status
sudo docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' dashboard
sudo docker inspect -f '{{.State.Health.Status}}' dashboard
```

If Docker prints a "swap limit support" warning, your kernel is not applying
the swap cap. It is harmless for the demo, and `--memory` still works.

---

## Persistence test (screenshot this)

```bash
# Write a file from INSIDE the container into the mounted folder
sudo docker exec dashboard sh -c 'echo "persisted at $(date)" > /usr/share/nginx/html/metrics/persist_test.txt'

# Restart the container
sudo docker restart dashboard
curl http://localhost:8080/metrics/persist_test.txt

# DESTROY the container entirely, then recreate it
sudo docker rm -f dashboard
sudo ~/phase3/deploy_dashboard.sh
curl http://localhost:8080/metrics/persist_test.txt     # still there!
ls -l /srv/dashboard/metrics/                           # also visible on the host
```

---

## Restart-policy test

```bash
sudo systemctl restart docker
sleep 5
sudo docker ps --format 'table {{.Names}}\t{{.Status}}'   # "Up a few seconds": it came back automatically
```

---

## Quick reference - common commands

```bash
sudo docker ps                      # running containers
sudo docker logs dashboard          # container logs
sudo docker inspect dashboard       # full config / limits / mounts
sudo docker exec -it dashboard sh   # shell inside the container
sudo docker stop dashboard          # stop it
sudo docker rm -f dashboard         # remove it (host data survives)
```
