# monitor-mac

A lightweight, open-source alternative to [iStat Menus](https://bjango.com/mac/istatmenus/) — with full historical data and dashboards. Built with [Vector](https://vector.dev), [InfluxDB 3 Core](https://www.influxdata.com), and [Grafana](https://grafana.com), it collects host metrics and visualizes them in real time, designed to run locally with minimal setup.

## What It Does

Collects system-level metrics from your Mac every 10 seconds and displays them on a pre-built Grafana dashboard:

- **CPU** — usage by mode (user, system, idle) with threshold alerts
- **Memory** — total, active, available, and free
- **Disk** — read/write throughput per device
- **Filesystem** — usage ratio per mountpoint
- **Network** — RX/TX bytes per interface
- **System Load** — 1, 5, and 15 minute averages
- **Per-Process CPU & Memory** — top 500 processes with historical trends

## Architecture

```
Vector (macOS host)  ──▶  InfluxDB (Docker)  ──▶  Grafana (Docker)
   collect metrics         store time-series        visualize
```

Vector runs natively on macOS (not in Docker) because it needs direct access to system metrics. InfluxDB 3 Core and Grafana run as Docker containers.

| Component  | Port  | URL                        |
|------------|-------|----------------------------|
| Grafana    | 3046  | http://localhost:3046       |
| InfluxDB   | 8334  | http://localhost:8334       |

## Prerequisites

- macOS (Apple Silicon or Intel)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (or any Docker-compatible runtime)
- [Homebrew](https://brew.sh)

## Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/kfirfer/monitor-mac.git
cd monitor-mac
```

### 2. Start InfluxDB and Grafana

```bash
docker compose up -d
```

This starts InfluxDB 3 Core and Grafana with auto-provisioned datasources and dashboards.

### 3. Install and start Vector

```bash
brew tap vectordotdev/brew && brew install vector
```

Run Vector manually to verify everything works:

```bash
vector --config vector.toml
```

You should see metrics flowing. Open [http://localhost:3046](http://localhost:3046) to view the dashboard — no login required.

### 4. (Optional) Auto-start Vector on boot

To have Vector start automatically when your Mac boots:

```bash
# Copy the LaunchAgent plist (update the path inside if your clone location differs)
ln -sf "$(pwd)/com.vector.metrics.plist" ~/Library/LaunchAgents/

# Load it
launchctl load ~/Library/LaunchAgents/com.vector.metrics.plist

# Verify it's running
launchctl list | grep vector
```

Vector logs are written to `/tmp/vector.log` and `/tmp/vector.err`.

> **Note:** The included plist references the config path `/Users/dev345/code/kfirfer/monitor-mac/vector.toml`. Update it to match your local clone path.

### 5. (Optional) Graceful shutdown hook

A LaunchAgent that traps `SIGTERM` on macOS shutdown and gracefully stops the Docker containers, preventing InfluxDB WAL corruption from unclean shutdowns:

```bash
ln -sf "$(pwd)/com.monitor.shutdown.plist" ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.monitor.shutdown.plist

# Verify it's running
launchctl list | grep com.monitor.shutdown

# View logs
cat /tmp/shutdown-hook.log
```

### 6. (Optional) Scheduled parquet pruning

A LaunchAgent that runs daily at 3 AM and removes parquet files older than 7 days, preventing InfluxDB query-file-limit issues as data accumulates:

```bash
ln -sf "$(pwd)/com.monitor.prune.plist" ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.monitor.prune.plist

# Manual run (retention in days)
./scripts/prune-parquet.sh 7

# View logs
cat /tmp/parquet-prune.log
```

## Stopping

```bash
# Stop the Docker containers
docker compose down

# If Vector is running via LaunchAgent
launchctl unload ~/Library/LaunchAgents/com.vector.metrics.plist

# If the shutdown hook / prune agents are installed
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.monitor.shutdown.plist
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.monitor.prune.plist
```

## Configuration

All configuration lives in the repository root:

| File | Purpose |
|------|---------|
| `vector.toml` | Vector metrics collection and delivery config |
| `docker-compose.yml` | InfluxDB and Grafana container definitions |
| `grafana/provisioning/datasources/datasource.yml` | Auto-provisioned InfluxDB datasource |
| `grafana/provisioning/dashboards/dashboard.yml` | Dashboard provisioning config |
| `grafana/dashboards/macos-metrics.json` | Pre-built Grafana dashboard |
| `com.vector.metrics.plist` | macOS LaunchAgent for auto-starting Vector |
| `com.monitor.health.plist` | LaunchAgent: every-5-minute health check & auto-recovery |
| `com.monitor.shutdown.plist` | LaunchAgent: graceful Docker stop on macOS shutdown (SIGTERM) |
| `com.monitor.prune.plist` | LaunchAgent: daily 3 AM parquet pruning (>7 days old) |

### Defaults

| Setting | Value |
|---------|-------|
| InfluxDB database | `mybucket` |
| Scrape interval | 10 seconds |

These are local development defaults. Change them in `docker-compose.yml`, `vector.toml`, and `grafana/provisioning/datasources/datasource.yml` if needed.

> **Note:** InfluxDB 3 Core does not support automatic data retention. Data grows indefinitely, which is suitable for local monitoring. To manage data size, periodically delete old data via SQL `DELETE` queries.

## Troubleshooting

**Vector can't connect to InfluxDB**
Make sure the Docker containers are running: `docker compose ps`

**No data appearing in Grafana**
1. Check Vector logs: `tail -f /tmp/vector.err`
2. Verify InfluxDB is reachable: `curl http://localhost:8334/health`
3. Confirm Vector is sending data: run `vector --config vector.toml` in the foreground and watch for errors

**InfluxDB crash loop (container keeps restarting)**

This typically happens due to corrupt WAL or snapshot files from an unclean shutdown.

```bash
# Quick recovery — removes corrupt files and restarts everything
./scripts/fix-wal.sh

# Dry-run mode — shows what would be deleted
./scripts/fix-wal.sh --dry-run
```

If the automated script doesn't fix it (nuclear option):
```bash
docker compose stop influxdb
docker run --rm -v monitor-mac_influxdb3-data:/data busybox rm -rf /data/node0/wal /data/node0/snapshots
docker compose up -d influxdb
```

**Health check monitoring**

A health check script runs every 5 minutes to auto-detect and recover from InfluxDB crash loops and Vector outages:

```bash
# Install the health check LaunchAgent
ln -sf "$(pwd)/com.monitor.health.plist" ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.monitor.health.plist

# View health check logs
cat /tmp/health-check.log
```

**LaunchAgent not starting**
```bash
# Check status
launchctl list | grep vector

# Check logs
tail -f /tmp/vector.err
```

## License

See [LICENSE](LICENSE) for details.
