# Vector Setup for macOS Metrics

This document describes the Vector.dev configuration for collecting macOS system metrics and sending them to InfluxDB.

## Overview

Vector replaces Telegraf as the metrics collection agent. It runs natively on macOS and sends metrics to InfluxDB 2.x running in Docker.

## Installation

### Install Vector via Homebrew

```bash
brew tap vectordotdev/brew && brew install vector
```

### Verify Installation

```bash
vector --version
```

## Configuration

The configuration file is located at `vector.toml` in this directory.

### Collected Metrics

Vector collects the following metrics via the `host_metrics` source:

| Collector | Metrics |
|-----------|---------|
| **cpu** | `host_cpu_seconds_total` (with mode: user, system, idle, etc.) |
| **memory** | `memory_total_bytes`, `memory_used_bytes`, `memory_available_bytes`, `memory_free_bytes`, etc. |
| **disk** | `disk_read_bytes_total`, `disk_written_bytes_total`, `disk_reads_completed_total`, `disk_writes_completed_total` |
| **filesystem** | `filesystem_total_bytes`, `filesystem_used_bytes`, `filesystem_free_bytes`, `filesystem_used_ratio` |
| **network** | `network_receive_bytes_total`, `network_transmit_bytes_total`, `network_receive_packets_total`, etc. |
| **process** | `process_cpu_usage`, `process_memory_usage`, `process_memory_virtual_usage`, `process_runtime` |
| **load** | `load1`, `load5`, `load15` |

### Metric Labels

All metrics include these common labels:
- `host`: Hostname of the originating system
- `collector`: Which collector the metric comes from

Process-specific metrics also include:
- `name`: Process executable name
- `pid`: Process ID

### Configuration Options

Key configuration in `vector.toml`:

```toml
[sources.host_metrics]
type = "host_metrics"
scrape_interval_secs = 5
namespace = "host"
collectors = ["cpu", "memory", "disk", "filesystem", "network", "process", "load"]

[sinks.influxdb]
type = "influxdb_metrics"
endpoint = "http://localhost:8334"
org = "myorg"
bucket = "mybucket"
token = "mytoken123"
```

## Auto-Start on macOS

### Setup LaunchAgent

```bash
# Create symlink to LaunchAgents
ln -sf $(pwd)/com.vector.metrics.plist ~/Library/LaunchAgents/

# Load the agent
launchctl load ~/Library/LaunchAgents/com.vector.metrics.plist
```

### Check Status

```bash
launchctl list | grep vector
```

### View Logs

```bash
# Standard output
tail -f /tmp/vector.log

# Error output
tail -f /tmp/vector.err
```

### Stop Vector

```bash
launchctl unload ~/Library/LaunchAgents/com.vector.metrics.plist
```

### Restart Vector

```bash
launchctl unload ~/Library/LaunchAgents/com.vector.metrics.plist
launchctl load ~/Library/LaunchAgents/com.vector.metrics.plist
```

## Validate Configuration

```bash
vector validate vector.toml
```

## Testing

### Run Vector in foreground (for debugging)

```bash
vector --config vector.toml
```

### Enable Vector API for monitoring

Add to `vector.toml`:

```toml
[api]
enabled = true
address = "127.0.0.1:8686"
```

Then use `vector top` to monitor in real-time.

## Comparison with Telegraf

| Feature | Telegraf | Vector |
|---------|----------|--------|
| **Metric Naming** | `measurement.field` (e.g., `cpu.usage_user`) | `namespace_metric` (e.g., `host_cpu_seconds_total`) |
| **CPU Metrics** | Percentage-based | Counter-based (seconds) |
| **Memory Metrics** | Percentage and bytes | Bytes only |
| **Process Metrics** | Via `procstat` plugin | Built-in `process` collector |
| **Configuration** | TOML | TOML/YAML/JSON |

## Troubleshooting

### Vector won't start

1. Check configuration syntax: `vector validate vector.toml`
2. Check InfluxDB is running: `docker ps | grep influxdb`
3. Check logs: `tail -f /tmp/vector.err`

### No metrics in Grafana

1. Verify Vector is running: `launchctl list | grep vector`
2. Check InfluxDB connectivity: `curl http://localhost:8334/health`
3. Query InfluxDB directly to verify data is being written

### High CPU usage

Reduce the number of processes monitored by adding exclusions:

```toml
[sources.host_metrics.process.processes]
includes = ["*"]
excludes = ["kernel_task", "mdworker*"]
```

Or increase the scrape interval:

```toml
scrape_interval_secs = 15
```
