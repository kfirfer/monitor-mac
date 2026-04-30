# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a macOS system metrics monitoring stack using Vector + InfluxDB 3 Core + Grafana. Vector runs natively on macOS to collect metrics, while InfluxDB and Grafana run in Docker containers.

## Commands

### Start the monitoring stack
```bash
docker compose up -d
```

### Stop the stack
```bash
docker compose down
```

### View container logs
```bash
docker compose logs -f grafana
docker compose logs -f influxdb
```

### Vector Setup

See [README-vector.md](README-vector.md) for installation and auto-start configuration.

Quick commands:
```bash
# Install
brew tap vectordotdev/brew && brew install vector

# Setup auto-start on boot
ln -sf $(pwd)/com.vector.metrics.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.vector.metrics.plist

# Check status
launchctl list | grep vector

# View logs
tail -f /tmp/vector.err
```

### Graceful Shutdown Hook

A LaunchAgent daemon (`com.monitor.shutdown.plist`) traps SIGTERM on macOS shutdown to gracefully stop Docker containers, preventing InfluxDB WAL corruption.

```bash
# Install
ln -sf $(pwd)/com.monitor.shutdown.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.monitor.shutdown.plist

# Check status
launchctl list | grep com.monitor.shutdown

# View logs
cat /tmp/shutdown-hook.log
```

### Parquet Pruning (Scheduled)

A LaunchAgent (`com.monitor.prune.plist`) runs daily at 3 AM to remove parquet files older than 7 days, preventing InfluxDB query-file-limit issues.

```bash
# Install
ln -sf $(pwd)/com.monitor.prune.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.monitor.prune.plist

# Manual run
./scripts/prune-parquet.sh 7

# View logs
cat /tmp/parquet-prune.log
```

### WAL Recovery

If InfluxDB fails to start due to corrupt WAL/snapshot/catalog files, run:
```bash
./scripts/fix-wal.sh
```

Dry-run mode (shows what would be deleted without deleting):
```bash
./scripts/fix-wal.sh --dry-run
```

### Health Check

A LaunchAgent (`com.monitor.health.plist`) runs every 5 minutes to check pipeline health and auto-recover from InfluxDB crash loops.

```bash
# Install
ln -sf $(pwd)/com.monitor.health.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.monitor.health.plist

# Manual run
./scripts/health-check.sh

# View logs
cat /tmp/health-check.log
```

## Architecture

**Data flow:** Vector (host) → InfluxDB (container:8334) → Grafana (container:3046)

- **Vector** runs on the host machine (not containerized) because it needs direct access to macOS system metrics
- **InfluxDB 3 Core** stores time-series data, exposed on port 8334 (maps to internal 8181). Uses SQL as primary query language.
- **Grafana** visualizes metrics, exposed on port 3046 (maps to internal 3000), configured for anonymous admin access

## Configuration

- Vector config: `vector.toml`
- InfluxDB database: `mybucket` (auth disabled for local use, 2-week retention)
- Vector scrape interval: 10 seconds
- Grafana datasource is auto-provisioned via `grafana/provisioning/datasources/datasource.yml`
- Dashboard is auto-provisioned from `grafana/dashboards/macos-metrics.json`

## Collected Metrics

Vector collects via `host_metrics` source: CPU, memory, disk, filesystem, network, load, and per-process CPU/memory stats.

## Access URLs

- Grafana: http://localhost:3046 (no login required)
- InfluxDB: http://localhost:8334

## Playwright MCP

The Playwright MCP server is available for troubleshooting the Grafana dashboard at http://localhost:3046/d/macos-metrics/macos-metrics. Use it to navigate, inspect, and debug dashboard issues interactively.

## Common Issues

### InfluxDB Crash Loop (`serde_json error: EOF`)
1. Check: `docker compose ps` shows influxdb "Restarting"
2. Fix: `./scripts/fix-wal.sh` (auto-stops Vector, removes corrupt 0-byte WAL/JSON/parquet files, restarts everything)
3. Root cause: Corrupt WAL/snapshot files from unclean shutdown (macOS sleep, power loss, OOM)

### Vector "Connection refused" to InfluxDB
1. InfluxDB is likely down — check `docker compose ps`
2. If crash loop, run `./scripts/fix-wal.sh`
3. If InfluxDB is healthy but Vector still fails, restart Vector: `launchctl unload ~/Library/LaunchAgents/com.vector.metrics.plist && launchctl load ~/Library/LaunchAgents/com.vector.metrics.plist`

### Grafana "No data" on All Panels
1. Check InfluxDB health: `curl http://localhost:8334/health`
2. Check Vector is running: `launchctl list | grep vector`
3. Check data freshness: look at "Data Freshness" panel (bottom of dashboard)
4. If stale, follow InfluxDB crash loop recovery above

### Full Pipeline Restart
```bash
launchctl unload ~/Library/LaunchAgents/com.vector.metrics.plist
docker compose down
docker compose up -d
# Wait for InfluxDB to be healthy
launchctl load ~/Library/LaunchAgents/com.vector.metrics.plist
```

## Critical Rules

Never run git commands.

@.claude.local.md
