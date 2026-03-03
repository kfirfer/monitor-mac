# monitor-mac

A lightweight macOS system monitoring stack that collects host metrics and visualizes them in real time. Built with [Vector](https://vector.dev), [InfluxDB](https://www.influxdata.com), and [Grafana](https://grafana.com) — designed to run locally with minimal setup.

## What It Does

Collects system-level metrics from your Mac every 5 seconds and displays them on a pre-built Grafana dashboard:

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

Vector runs natively on macOS (not in Docker) because it needs direct access to system metrics. InfluxDB and Grafana run as Docker containers.

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

This starts InfluxDB and Grafana with auto-provisioned datasources and dashboards. Data is retained for 7 days.

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

## Stopping

```bash
# Stop the Docker containers
docker compose down

# If Vector is running via LaunchAgent
launchctl unload ~/Library/LaunchAgents/com.vector.metrics.plist
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

### Defaults

| Setting | Value |
|---------|-------|
| InfluxDB org | `myorg` |
| InfluxDB bucket | `mybucket` |
| InfluxDB token | `mytoken123` |
| Scrape interval | 5 seconds |
| Data retention | 7 days |

These are local development defaults. Change them in `docker-compose.yml`, `vector.toml`, and `grafana/provisioning/datasources/datasource.yml` if needed.

## Troubleshooting

**Vector can't connect to InfluxDB**
Make sure the Docker containers are running: `docker compose ps`

**No data appearing in Grafana**
1. Check Vector logs: `tail -f /tmp/vector.err`
2. Verify InfluxDB is reachable: `curl http://localhost:8334/health`
3. Confirm Vector is sending data: run `vector --config vector.toml` in the foreground and watch for errors

**LaunchAgent not starting**
```bash
# Check status
launchctl list | grep vector

# Check logs
tail -f /tmp/vector.err
```

## License

See [LICENSE](LICENSE) for details.
