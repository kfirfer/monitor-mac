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

## Architecture

**Data flow:** Vector (host) → InfluxDB (container:8334) → Grafana (container:3046)

- **Vector** runs on the host machine (not containerized) because it needs direct access to macOS system metrics
- **InfluxDB 3 Core** stores time-series data, exposed on port 8334 (maps to internal 8181). Uses SQL as primary query language.
- **Grafana** visualizes metrics, exposed on port 3046 (maps to internal 3000), configured for anonymous admin access

## Configuration

- Vector config: `vector.toml`
- InfluxDB database: `mybucket` (auth disabled for local use)
- Grafana datasource is auto-provisioned via `grafana/provisioning/datasources/datasource.yml`
- Dashboard is auto-provisioned from `grafana/dashboards/macos-metrics.json`

## Collected Metrics

Vector collects via `host_metrics` source: CPU, memory, disk, filesystem, network, load, and per-process CPU/memory stats.

## Access URLs

- Grafana: http://localhost:3046 (no login required)
- InfluxDB: http://localhost:8334

## Critical Rules

Never run git commands.
