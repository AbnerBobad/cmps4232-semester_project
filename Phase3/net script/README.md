# net_check.sh - Network Diagnostic Script

CMPS4232 Systems Administration - Phase 3

`net_check.sh` checks the health of the server's network and writes the results to the web dashboard running in the Docker container. Every run adds a new timestamped report, so the page keeps a history.

---

## 1. What it does

1. Collects network facts from the host.
2. Shows them on the screen.
3. Appends them to `/srv/dashboard/metrics/net_status.html`.
4. The NGINX container serves that file, so you can read the report in a browser or with `curl`.

## 2. How it connects to the Docker setup

```
net_check.sh  --writes-->  /srv/dashboard/metrics/net_status.html   (host)
                                      |
                              bind mount (-v)
                                      |
                                      v
              /usr/share/nginx/html/metrics/net_status.html         (container)
                                      |
                              NGINX, container port 80
                                      |
                              host port 8080  (-p 8080:80)
                                      |
                                      v
         http://localhost:8080/metrics/net_status.html
```

The host folder and the container folder are the same files, so the report appears on the web page immediately. No copying or restart is needed.

## 3. Requirements

| Requirement | Why |
|---|---|
| Run with `sudo` | The `docker` commands and `ss -p` need root |
| Container named `dashboard` is running | The script checks its port binding |
| Folder `/srv/dashboard/metrics` exists | It is the mounted folder the report is written to |
| Tools: `ip`, `ss`, `ping`, `curl`, `docker` | Used for the checks (the script tells you if one is missing) |

## 4. Where the files are

```
~/phase3/
|-- net_check.sh                  the script
|-- deploy_dashboard.sh           builds the image and starts the container
|-- Dockerfile
|-- html/index.html
|-- nginx/default.conf.template
```

The report file lives on the host at `/srv/dashboard/metrics/net_status.html`.

## 5. How to run it

```bash
cd ~/phase3
nano net_check.sh (paste the script)
chmod +x net_check.sh      # only needed the first time
sudo ./net_check.sh
```

The script prints the full report on screen and ends with:

```
Results appended to: /srv/dashboard/metrics/net_status.html   (failed checks: 0)
View them at: http://localhost:8080/metrics/net_status.html
```

## 6. What it checks

| # | Section | Command used | What to look at |
|---|---|---|---|
| 1 | Interfaces and IP addresses | `ip -br addr` | One line per interface (`lo`, `ens33`, `docker0`, `veth...`) |
| 2 | Interface statistics | `ip -s link` | RX/TX bytes, packets, errors, dropped |
| 3 | Listening ports | `ss -tulnp` | Open ports, and a check that 8080 is listening |
| 4 | Docker container and port bindings | `docker ps`, `docker port dashboard` | `0.0.0.0:8080->80/tcp` |
| 5 | External connectivity | `ping` to `8.8.8.8`, `1.1.1.1`, `example.com` | Internet access and DNS |
| 6 | Dashboard web check | `curl` to `/health` | HTTP 200 means the container is serving |

### Reading the results

| Label | Meaning |
|---|---|
| `[ UP ]` | The check passed |
| `[DOWN]` | A host could not be reached |
| `[FAIL]` | A check failed (port, container binding, or web page) |

The heading of each report shows the number of failed checks, for example `failed checks: 0`.

## 7. How to view the report

Inside the VM:

```bash
curl http://localhost:8080/metrics/net_status.html
```

Only the passed/failed lines:

```bash
curl -s http://localhost:8080/metrics/net_status.html | grep -E '^\[ UP \]|^\[DOWN\]|^\[FAIL\]'
```

Count how many reports have been appended (keep this on one line):

```bash
curl -s http://localhost:8080/metrics/net_status.html | grep -c '<section>'
```

From another computer, use the VM's IP address (find it with `hostname -I`):

```
http://<VM-IP>:8080/metrics/net_status.html
```

## 8. Error handling

| Situation | What the script does |
|---|---|
| Not run as root | Prints `run with sudo` and exits with code 1 |
| A required tool is missing | Names the missing command and exits with code 1 |
| `/srv/dashboard/metrics` is missing | Prints an error and exits with code 1. It does not create the folder, because a missing folder means the container mount is not set up. |
| Container stopped or missing | Prints `[FAIL]` lines and still finishes the rest of the report |
| Command output contains `<`, `>`, or `&` | Escaped, so it displays as text and does not break the HTML page |

## 9. Test it (edge cases)

```bash
# Stopped container: expect [FAIL] lines, script still completes
sudo docker stop dashboard && sudo ./net_check.sh | grep FAIL
sudo docker start dashboard

# Missing folder: expect a clear error and exit code 1
sudo DASH_DATA=/nonexistent ./net_check.sh; echo "exit code: $?"

# Without sudo: expect a message asking for sudo
./net_check.sh
```

After the stopped-container test, run `sudo ./net_check.sh` once more so the newest report on the page is a clean one.

## 10. Settings you can change

These are at the top of the script:

| Setting | Default | Meaning |
|---|---|---|
| `DASH_DATA` | `/srv/dashboard/metrics` | Host folder mounted into the container |
| `CONTAINER` | `dashboard` | Container name (from `--name dashboard`) |
| `HOST_PORT` | `8080` | Host port (from `-p 8080:80`) |

`DASH_DATA` and `CONTAINER` can be overridden for a single run, for example:

```bash
sudo DASH_DATA=/some/other/folder ./net_check.sh
```

If you change the container name, port, or mount path in `deploy_dashboard.sh`, change them here too.

## 11. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `ERROR: run with sudo` | Missing `sudo` | `sudo ./net_check.sh` |
| `ERROR: ... does not exist` | Folder missing | Run `sudo ~/phase3/deploy_dashboard.sh`, or create `/srv/dashboard/metrics` |
| `[FAIL] Container 'dashboard' not found` | Container was removed | `sudo ~/phase3/deploy_dashboard.sh` |
| `[FAIL] ... returned HTTP 000` | Container stopped or port not published | `sudo docker start dashboard`, then check `sudo docker ps` |
| `[DOWN]` on all ping lines | VM has no internet access | Check the VM network adapter; the script is reporting correctly |
| `curl` shows 404 for the report | Report not written yet, or wrong mount | Run the script, then `ls -l /srv/dashboard/metrics/` |
| Section count looks too high (like 83) | The `grep` pattern was split across two lines | Put `grep -c '<section>'` on one line |

## 12. Demo (Phase 4)

```bash
sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Mounts}}'
sudo ./net_check.sh
ls -l /srv/dashboard/metrics/
curl http://localhost:8080/metrics/net_status.html
```