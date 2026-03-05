# InfluxDB 2 to InfluxDB 3 Core Upgrade Plan

This document provides a comprehensive plan for upgrading the monitoring stack from **InfluxDB 2.x** to **InfluxDB 3 Core** (stable). InfluxDB 3 Core is free and open source (MIT + Apache 2), built on Apache DataFusion with columnar Parquet-based storage.

> **Note:** Data migration from InfluxDB 2 is **not required** for this project. The InfluxDB 2 data volume will be removed and the system will start fresh. This document focuses on a clean deployment of InfluxDB 3 Core with all dependent services reconfigured.

---

## Table of Contents

1. [Key Differences: InfluxDB 2 vs InfluxDB 3 Core](#key-differences-influxdb-2-vs-influxdb-3-core)
2. [Configuration to Preserve](#configuration-to-preserve)
3. [Task Hierarchy](#task-hierarchy)
4. [Phase 1: Preparation](#phase-1-preparation)
5. [Phase 2: InfluxDB 3 Core Docker Setup](#phase-2-influxdb-3-core-docker-setup)
6. [Phase 3: Vector Configuration Update](#phase-3-vector-configuration-update)
7. [Phase 4: Grafana Datasource Migration](#phase-4-grafana-datasource-migration)
8. [Phase 5: Dashboard Migration (Flux to SQL)](#phase-5-dashboard-migration-flux-to-sql)
9. [Phase 6: Testing and Validation](#phase-6-testing-and-validation)
10. [Phase 7: Cleanup and Documentation](#phase-7-cleanup-and-documentation)
11. [Reference: Flux to SQL Query Migration](#reference-flux-to-sql-query-migration)

---

## Key Differences: InfluxDB 2 vs InfluxDB 3 Core

| Aspect | InfluxDB 2.x | InfluxDB 3 Core |
|--------|-------------|-----------------|
| **Docker Image** | `influxdb:2-alpine` | `influxdb:3-core` |
| **Default Port** | 8086 | 8181 |
| **Data Organization** | Orgs + Buckets | Databases (no orgs) |
| **Query Language** | Flux (primary), InfluxQL | SQL (primary), InfluxQL. **No Flux support.** |
| **Write API** | `/api/v2/write` | `/api/v3/write_lp` (new), `/api/v2/write` (v2 compat), `/write` (v1 compat) |
| **Data Storage** | Custom TSM engine | Apache Parquet (columnar) |
| **Data Path** | `/var/lib/influxdb2` | `/var/lib/influxdb3/data` |
| **Configuration** | `DOCKER_INFLUXDB_INIT_*` env vars | CLI flags via `influxdb3 serve` command (preferred over env vars) |
| **Web UI** | Built-in | None (optional InfluxDB 3 Explorer) |
| **Retention Policies** | Built-in per bucket | Not available in Core (available in Enterprise) |
| **Authentication** | Token-based with org/bucket scoping | Token-based with database scoping (optional) |
| **License** | MIT | MIT + Apache 2 |

> **Important: CLI flags vs environment variables.** The official Docker Hub compose example for InfluxDB 3 Core uses CLI command flags (via `command:` in docker-compose) rather than `INFLUXDB3_*` environment variables. There is a [known issue](https://github.com/influxdata/influxdb/issues/26459) where some `INFLUXDB3_*` env vars are not properly honored (inconsistent naming between `INFLUXDB3_DATA_DIR`, `INFLUXDB_IOX_DB_DIR`, etc.). **Use CLI flags for reliability.**

---

## Configuration to Preserve

These values from the current InfluxDB 2 setup should be carried forward (adapted to v3 equivalents):

| Setting | Current Value (v2) | v3 Equivalent |
|---------|-------------------|---------------|
| Bucket name | `mybucket` | Database name: `mybucket` |
| Auth token | `mytoken123` | Admin token: `mytoken123` (or disable auth for local use) |
| Retention | `7d` | Not available in Core (see note below) |
| Host port | `8334` | `8334` (unchanged externally) |
| Internal port | `8086` | `8181` (changed) |

> **Retention Policy Note:** InfluxDB 3 Core does not support automatic data retention/expiration. Options:
> 1. Accept that data grows indefinitely (suitable for local dev with limited scrape history).
> 2. Use a cron job or script to periodically delete old data via SQL `DELETE` queries.
> 3. Upgrade to InfluxDB 3 Enterprise for built-in retention policies.
>
> For this local monitoring use case, option 1 or 2 is recommended.

---

## Task Hierarchy

### Phase 1: Preparation
- [x] 1.1 Review and document current running state
  - [x] 1.1.1 Verify current InfluxDB 2 container is running and healthy
  - [x] 1.1.2 Confirm Vector is writing metrics successfully
  - [x] 1.1.3 Confirm Grafana dashboards are rendering correctly
- [x] 1.2 Create a git branch for the upgrade
- [x] 1.3 Back up current configuration files (handled by git branch — originals preserved on main)
  - [x] 1.3.1 Back up `docker-compose.yml`
  - [x] 1.3.2 Back up `vector.toml`
  - [x] 1.3.3 Back up `grafana/provisioning/datasources/datasource.yml`
  - [x] 1.3.4 Back up `grafana/dashboards/macos-metrics.json`

### Phase 2: InfluxDB 3 Core Docker Setup
- [x] 2.1 Update `docker-compose.yml`
  - [x] 2.1.1 Change image from `influxdb:2-alpine` to `influxdb:3-core`
  - [x] 2.1.2 Update port mapping from `8334:8086` to `8334:8181`
  - [x] 2.1.3 Replace `environment:` block with `command:` block using CLI flags (`influxdb3 serve --node-id=node0 --object-store=file --data-dir=/var/lib/influxdb3/data --plugin-dir=/var/lib/influxdb3/plugins`)
  - [x] 2.1.4 Update volume from `influxdb-data:/var/lib/influxdb2` to `influxdb3-data:/var/lib/influxdb3/data`
  - [x] 2.1.5 Add plugins volume: `influxdb3-plugins:/var/lib/influxdb3/plugins`
  - [x] 2.1.6 Update volumes section at bottom of file (replace `influxdb-data:` with `influxdb3-data:` and add `influxdb3-plugins:`)
- [x] 2.2 Start and verify InfluxDB 3 Core container
  - [x] 2.2.1 Run `docker compose up -d influxdb`
  - [x] 2.2.2 Verify container is healthy via `curl http://localhost:8334/health`
  - [x] 2.2.3 Create the `mybucket` database via `docker exec influxdb influxdb3 create database mybucket`
  - [x] 2.2.4 Verify database via `docker exec influxdb influxdb3 show databases`

### Phase 3: Vector Configuration Update
- [x] 3.1 Update `vector.toml` sink configuration
  - [x] 3.1.1 Update comments to reference InfluxDB 3 (not v2)
  - [x] 3.1.2 Endpoint remains `http://localhost:8334` (no change needed)
  - [x] 3.1.3 Verify `bucket = "mybucket"` maps to v3 database name via v2 compat API
  - [x] 3.1.4 Keep `org = "myorg"` (v2 compat API requires it, v3 ignores the value)
  - [x] 3.1.5 Set `token = "unused"` (if auth is disabled) or keep `mytoken123` (if auth is enabled)
- [x] 3.2 Test Vector writes
  - [x] 3.2.1 Run Vector in foreground: `vector --config vector.toml`
  - [x] 3.2.2 Confirm no write errors in output
  - [x] 3.2.3 Verify data arrives in InfluxDB 3 via CLI query

### Phase 4: Grafana Datasource Migration
- [x] 4.1 Update `grafana/provisioning/datasources/datasource.yml`
  - [x] 4.1.1 Change `url` from `http://influxdb:8086` to `http://influxdb:8181`
  - [x] 4.1.2 Change `jsonData.version` from `Flux` to `SQL`
  - [x] 4.1.3 Remove `jsonData.organization` field
  - [x] 4.1.4 Remove `jsonData.defaultBucket` field
  - [x] 4.1.5 Add `jsonData.database` field set to `mybucket`
  - [x] 4.1.6 Keep `secureJsonData.token` for authentication
  - [x] 4.1.7 **Verify:** `SQL` works with `insecureGrpc: true` and `metadata` array containing `{database: mybucket}`
- [x] 4.2 Verify Grafana datasource connectivity
  - [x] 4.2.1 Restart Grafana: `docker compose restart grafana`
  - [x] 4.2.2 Open Grafana UI and verify datasource is connected (green)

### Phase 5: Dashboard Migration (Flux to SQL)
- [x] 5.1 Rewrite all Flux queries in `grafana/dashboards/macos-metrics.json` to SQL
  - [x] 5.1.1 Migrate CPU Usage panel (id: 1, title: "CPU Usage") — derivative of `host.cpu_seconds_total`
  - [x] 5.1.2 Migrate Memory Usage panel (id: 2, title: "Memory Usage") — join of total and active bytes
  - [x] 5.1.3 Migrate Disk Usage panel (id: 3, title: "Disk Usage") — `host.filesystem_used_ratio`
  - [x] 5.1.4 Migrate Network Traffic panel (id: 4, title: "Network Traffic") — derivative of RX+TX bytes, **must include both RX and TX via UNION ALL**
  - [x] 5.1.5 Migrate Process CPU Table panel (id: 5, title: "CPU Usage per Process (Top 500)")
  - [x] 5.1.6 Migrate Process Memory Table panel (id: 6, title: "Memory Usage per Process (Top 500)")
  - [x] 5.1.7 Migrate System Load Average panel (id: 9, title: "System Load Average")
  - [x] 5.1.8 Migrate Memory Details panel (id: 10, title: "Memory Details")
  - [x] 5.1.9 Migrate Process CPU Time Series panel (id: 11, title: "CPU Usage per Process Over Time") — **note: original uses `fill(value: 0.0)` and `createEmpty: true`, SQL equivalent needs `COALESCE(..., 0)` or accept nulls**
  - [x] 5.1.10 Migrate Process Memory Time Series panel (id: 12, title: "Memory Usage per Process Over Time")
- [x] 5.2 Update dashboard JSON metadata for SQL compatibility
  - [x] 5.2.1 Ensure all panels reference the correct datasource UID (`influxdb-macos`)
  - [x] 5.2.2 **Update table panel field overrides:** Panels id 5 and 6 have overrides matching column name `_value` — change to `value` (SQL column name)
  - [x] 5.2.3 **Update `displayName` templates:** Panels id 11 and 12 use `${__field.labels.name}` which may not work with SQL mode — test and update to use `${__field.name}` or remove the `displayName` template and rely on the `metric` column alias instead

### Phase 6: Testing and Validation
- [x] 6.1 End-to-end data flow test
  - [x] 6.1.1 Verify Vector writes are reaching InfluxDB 3
  - [x] 6.1.2 Query data via `influxdb3` CLI to confirm tables exist
  - [x] 6.1.3 Verify Grafana can query and display data
- [x] 6.2 Dashboard validation
  - [x] 6.2.1 Verify CPU Usage panel renders correctly
  - [x] 6.2.2 Verify Memory Usage panel renders correctly
  - [x] 6.2.3 Verify Disk Usage panel renders correctly
  - [x] 6.2.4 Verify Network Traffic panel renders correctly (both RX and TX lines)
  - [x] 6.2.5 Verify Process CPU/Memory tables render correctly (column names display properly)
  - [x] 6.2.6 Verify System Load Average panel renders correctly
  - [x] 6.2.7 Verify Memory Details panel renders correctly
  - [x] 6.2.8 Verify Process CPU/Memory time series panels render correctly
- [x] 6.3 Performance check
  - [x] 6.3.1 Monitor InfluxDB 3 container resource usage (CPU/memory)
  - [x] 6.3.2 Verify query response times are acceptable

### Phase 7: Cleanup and Documentation
- [x] 7.1 Remove old InfluxDB 2 Docker volume
  - [x] 7.1.1 Run `docker volume rm monitor-mac_influxdb-data` (volume already removed/nonexistent)
- [x] 7.2 Update documentation
  - [x] 7.2.1 Update `README.md` to reference InfluxDB 3 Core
  - [x] 7.2.2 Update `README-vector.md` to reference InfluxDB 3 compatibility
  - [x] 7.2.3 Update `CLAUDE.md` with new configuration details
- [x] 7.3 Remove legacy Telegraf config
  - [x] 7.3.1 Delete `telegraf.conf` (leftover from pre-Vector setup)
- [x] 7.4 Commit and merge
  - [x] 7.4.1 Review all changes
  - [x] 7.4.2 Commit with descriptive message
  - [x] 7.4.3 Merge upgrade branch to main

---

## Phase 1: Preparation

### 1.1 Verify Current State

Before making any changes, ensure the current stack is functioning:

```bash
# Check containers are running
docker compose ps

# Check InfluxDB 2 health
curl http://localhost:8334/health

# Check Vector is running
launchctl list | grep vector

# Open Grafana and verify dashboards
open http://localhost:3046
```

### 1.2 Create Upgrade Branch

```bash
git checkout -b upgrade/influxdb-v3
```

### 1.3 Stop Current Stack

```bash
# Stop Vector
launchctl unload ~/Library/LaunchAgents/com.vector.metrics.plist

# Stop containers
docker compose down
```

---

## Phase 2: InfluxDB 3 Core Docker Setup

### 2.1 Updated `docker-compose.yml`

Replace the current `influxdb` service with:

```yaml
services:
  influxdb:
    image: influxdb:3-core
    container_name: influxdb
    restart: unless-stopped
    ports:
      - "8334:8181"
    command:
      - influxdb3
      - serve
      - --node-id=node0
      - --object-store=file
      - --data-dir=/var/lib/influxdb3/data
      - --plugin-dir=/var/lib/influxdb3/plugins
    volumes:
      - influxdb3-data:/var/lib/influxdb3/data
      - influxdb3-plugins:/var/lib/influxdb3/plugins

  grafana:
    # ... (unchanged except depends_on still references influxdb)
    ...

volumes:
  influxdb3-data:
  influxdb3-plugins:
  grafana-data:
```

**Key changes explained:**
- **Image:** `influxdb:3-core` is the official Docker Hub image for InfluxDB 3 Core (tags: `3-core`, `3.8-core`, `3.8.3-core`, `core`).
- **Port mapping:** Internal port changes from `8086` to `8181` (InfluxDB 3 default).
- **Command:** Uses CLI flags via `command:` instead of environment variables. This follows the [official Docker Hub compose example](https://hub.docker.com/_/influxdb) and avoids [known env var issues](https://github.com/influxdata/influxdb/issues/26459).
  - `--node-id=node0` — Unique node identifier (required).
  - `--object-store=file` — Use local file storage (suitable for single-node).
  - `--data-dir=/var/lib/influxdb3/data` — Data directory inside the container.
  - `--plugin-dir=/var/lib/influxdb3/plugins` — Processing engine plugins directory.
- **Volumes:** Two named volumes — `influxdb3-data` for data persistence and `influxdb3-plugins` for plugins.

> **Why CLI flags instead of env vars?** The official Docker Hub compose example uses `command:` with CLI flags. There is a [known GitHub issue (#26459)](https://github.com/influxdata/influxdb/issues/26459) where `INFLUXDB3_DATA_DIR` and `INFLUXDB_IOX_DB_DIR` environment variables conflict and cause startup failures. CLI flags are the reliable approach.

### 2.2 Start InfluxDB 3 Core

```bash
docker compose up -d influxdb
```

### 2.3 Verify and Create Database

```bash
# Check health
curl http://localhost:8334/health

# Create the database using the InfluxDB 3 CLI inside the container
docker exec influxdb influxdb3 create database mybucket

# Verify database was created
docker exec influxdb influxdb3 show databases
```

> **Note:** InfluxDB 3 Core also auto-creates databases on first write via the v2 compatibility API, so this step is optional if Vector writes first.

### 2.4 Authentication (Optional)

For local development, authentication can be left disabled (default). If you want to enable it:

```bash
# Create an admin token
docker exec influxdb influxdb3 create token \
  --admin \
  --token-name "admin-token"
```

The returned token must then be used in Vector and Grafana configs. For simplicity, this plan assumes **authentication is disabled** for local use.

If you keep auth disabled, the `token` field in Vector and Grafana configs is ignored but harmless to leave in place.

---

## Phase 3: Vector Configuration Update

### 3.1 Updated `vector.toml` Sink Section

The Vector `influxdb_metrics` sink uses the InfluxDB v2 write API (`/api/v2/write`), which InfluxDB 3 Core supports as a **v2 compatibility endpoint**. This means minimal changes are needed:

```toml
# Send metrics to InfluxDB 3 Core (via v2 compatibility API)
[sinks.influxdb]
type = "influxdb_metrics"
inputs = ["add_tags"]

# InfluxDB 3 endpoint (running in Docker on port 8334)
endpoint = "http://localhost:8334"

# InfluxDB v2 compatibility - bucket maps to database name in v3
org = "myorg"
bucket = "mybucket"
token = "unused"

# Default namespace for metrics that don't have one
default_namespace = "host"

# Batching configuration
[sinks.influxdb.batch]
max_events = 5000
timeout_secs = 10

# Buffer configuration
[sinks.influxdb.buffer]
type = "memory"
max_events = 20000
when_full = "block"

# Request configuration
[sinks.influxdb.request]
concurrency = 2
timeout_secs = 60
retry_initial_backoff_secs = 1
retry_max_duration_secs = 10
```

**What changes:**
- Update comments to reference InfluxDB 3.
- `bucket = "mybucket"` — This maps to the database name `mybucket` in v3.
- `org = "myorg"` — Required by the v2 API format but ignored by v3.
- `token = "unused"` — Set to any value if auth is disabled, or the actual token if auth is enabled.
- `endpoint` — Remains `http://localhost:8334` (no change).

### 3.2 Test Vector Writes

```bash
# Run Vector in foreground to verify
vector --config vector.toml

# In another terminal, verify data is being written
docker exec influxdb influxdb3 query \
  --database mybucket \
  "SELECT * FROM \"host.cpu_seconds_total\" LIMIT 5"
```

---

## Phase 4: Grafana Datasource Migration

### 4.1 Updated `grafana/provisioning/datasources/datasource.yml`

```yaml
apiVersion: 1

datasources:
  - name: InfluxDB
    type: influxdb
    uid: influxdb-macos
    access: proxy
    orgId: 1
    url: http://influxdb:8181
    jsonData:
      version: SQL
      database: mybucket
      tlsSkipVerify: true
    secureJsonData:
      token: unused
    isDefault: true
    editable: false
```

**Key changes:**
- `url`: Changed from `http://influxdb:8086` to `http://influxdb:8181` (v3 default port).
- `jsonData.version`: Changed from `Flux` to `SQL`.
- `jsonData.database`: Added — specifies the database to query (replaces bucket concept).
- `jsonData.organization`: Removed (not applicable to v3 SQL mode).
- `jsonData.defaultBucket`: Removed (replaced by `database`).

> **Grafana version requirement:** The InfluxDB datasource with SQL support requires **Grafana 10.3.0+**. The current setup uses Grafana 12.3.1, which fully supports this.

> **Troubleshooting:** If `version: SQL` does not work, try `version: InfluxDBv3` — some Grafana versions use this alternate value for the provisioning field. The Grafana UI shows "SQL" as the language option, but the internal provisioning value may differ. Test and confirm during Phase 6.

### 4.2 Verify Datasource

```bash
# Restart Grafana to pick up new datasource config
docker compose restart grafana

# Open Grafana and check datasource connectivity
open http://localhost:3046/connections/datasources
```

---

## Phase 5: Dashboard Migration (Flux to SQL)

This is the most significant change. All Flux queries in `grafana/dashboards/macos-metrics.json` must be rewritten in SQL. InfluxDB 3 uses SQL (Apache DataFusion dialect) as its primary query language.

### Important Notes on SQL Query Syntax

- **Table names** in InfluxDB 3 correspond to **measurement names** from line protocol. With Vector's `host_metrics` source and `host` namespace, measurements are written as `host.cpu_seconds_total`, `host.memory_total_bytes`, etc.
- **Table names containing dots must be quoted** with double quotes: `"host.cpu_seconds_total"`.
- **Tags become columns** — all tags (host, mode, device, etc.) are regular columns.
- **The `_value` field** from InfluxDB 2 becomes the `value` column in v3 (the field name used in line protocol by Vector's `influxdb_metrics` sink).
- **Time column** is `time` (not `_time`).
- **Grafana macros** like `$__timeFilter` and `$__interval` work with the SQL datasource.
- **No `derivative()` function** in SQL — use window functions like `LAG()` to compute rate of change.
- **InfluxDB 3 Core supports** `date_bin()`, `LAG()`, `LEAD()`, and other window functions, `UNION ALL`, `CONCAT()`, `EXTRACT()`, and standard SQL aggregations (confirmed via official SQL reference docs).

### 5.1 Query Migration Reference

Below are the current Flux queries and their SQL equivalents for each dashboard panel.

#### 5.1.1 CPU Usage (%) — Panel id: 1, "CPU Usage"

Derivative of counter, grouped by mode, averaged across CPUs.

**Current Flux:**
```flux
from(bucket: "mybucket")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r._measurement == "host.cpu_seconds_total")
  |> filter(fn: (r) => r.mode == "user" or r.mode == "system" or r.mode == "idle")
  |> derivative(unit: 1s, nonNegative: true)
  |> map(fn: (r) => ({r with _value: r._value * 100.0}))
  |> group(columns: ["_time", "mode"])
  |> sum()
  |> group(columns: ["mode"])
  |> aggregateWindow(every: v.windowPeriod, fn: mean, createEmpty: false)
  |> yield(name: "mean")
```

**SQL equivalent:**
```sql
SELECT
  date_bin('$__interval', time) AS time,
  mode,
  AVG(
    (value - LAG(value) OVER (PARTITION BY cpu, mode ORDER BY time))
    / EXTRACT(EPOCH FROM (time - LAG(time) OVER (PARTITION BY cpu, mode ORDER BY time)))
    * 100.0
  ) AS value
FROM "host.cpu_seconds_total"
WHERE
  $__timeFilter(time)
  AND mode IN ('user', 'system', 'idle')
GROUP BY date_bin('$__interval', time), mode
ORDER BY time
```

> **Note:** This computes the per-second rate of change (derivative) of the counter, then averages across all CPUs. The `LAG()` window function provides the previous value for rate calculation.

#### 5.1.2 Memory Usage (%) — Panel id: 2, "Memory Usage"

**Current Flux:**
```flux
total = from(bucket: "mybucket")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r._measurement == "host.memory_total_bytes")
  |> aggregateWindow(every: v.windowPeriod, fn: mean, createEmpty: false)

used = from(bucket: "mybucket")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r._measurement == "host.memory_active_bytes")
  |> aggregateWindow(every: v.windowPeriod, fn: mean, createEmpty: false)

join(tables: {total: total, used: used}, on: ["_time"])
  |> map(fn: (r) => ({_time: r._time, _value: (r._value_used / r._value_total) * 100.0, _field: "used"}))
  |> group(columns: ["_field"])
  |> yield(name: "used")
```

**SQL equivalent:**
```sql
SELECT
  t.time,
  (a.value / t.value) * 100.0 AS value,
  'used' AS metric
FROM "host.memory_total_bytes" t
INNER JOIN "host.memory_active_bytes" a ON t.time = a.time
WHERE $__timeFilter(t.time)
ORDER BY t.time
```

#### 5.1.3 Disk Usage — Panel id: 3, "Disk Usage"

**Current Flux:**
```flux
from(bucket: "mybucket")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r._measurement == "host.filesystem_used_ratio")
  |> filter(fn: (r) => r.mountpoint != "/dev")
  |> map(fn: (r) => ({_time: r._time, _value: r._value * 100.0, _field: r.device + " - " + r.filesystem + " - " + r.mountpoint}))
  |> group(columns: ["_field"])
  |> aggregateWindow(every: v.windowPeriod, fn: mean, createEmpty: false)
  |> yield(name: "mean")
```

**SQL equivalent:**
```sql
SELECT
  date_bin('$__interval', time) AS time,
  CONCAT(device, ' - ', filesystem, ' - ', mountpoint) AS metric,
  AVG(value * 100.0) AS value
FROM "host.filesystem_used_ratio"
WHERE
  $__timeFilter(time)
  AND mountpoint != '/dev'
GROUP BY date_bin('$__interval', time), device, filesystem, mountpoint
ORDER BY time
```

#### 5.1.4 Network Traffic (bytes/sec) — Panel id: 4, "Network Traffic"

**Current Flux:**
```flux
from(bucket: "mybucket")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r._measurement == "host.network_receive_bytes_total" or r._measurement == "host.network_transmit_bytes_total")
  |> map(fn: (r) => ({r with direction: if r._measurement == "host.network_receive_bytes_total" then "rx" else "tx"}))
  |> group(columns: ["device", "direction"])
  |> derivative(unit: 1s, nonNegative: true)
  |> map(fn: (r) => ({_time: r._time, _value: r._value, _field: r.device + " " + r.direction}))
  |> group(columns: ["_field"])
  |> aggregateWindow(every: v.windowPeriod, fn: mean, createEmpty: false)
  |> yield(name: "mean")
```

**SQL equivalent (RX + TX combined via UNION ALL):**
```sql
SELECT
  date_bin('$__interval', time) AS time,
  CONCAT(device, ' rx') AS metric,
  AVG(
    (value - LAG(value) OVER (PARTITION BY device ORDER BY time))
    / EXTRACT(EPOCH FROM (time - LAG(time) OVER (PARTITION BY device ORDER BY time)))
  ) AS value
FROM "host.network_receive_bytes_total"
WHERE $__timeFilter(time)
GROUP BY date_bin('$__interval', time), device
UNION ALL
SELECT
  date_bin('$__interval', time) AS time,
  CONCAT(device, ' tx') AS metric,
  AVG(
    (value - LAG(value) OVER (PARTITION BY device ORDER BY time))
    / EXTRACT(EPOCH FROM (time - LAG(time) OVER (PARTITION BY device ORDER BY time)))
  ) AS value
FROM "host.network_transmit_bytes_total"
WHERE $__timeFilter(time)
GROUP BY date_bin('$__interval', time), device
ORDER BY time
```

#### 5.1.5 Process CPU Table (Top 500) — Panel id: 5, "CPU Usage per Process (Top 500)"

**Current Flux:**
```flux
from(bucket: "mybucket")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r._measurement == "host.process_cpu_usage")
  |> keep(columns: ["_time", "_value", "name"])
  |> group(columns: ["name"])
  |> last()
  |> group()
  |> sort(columns: ["_value"], desc: true)
  |> limit(n: 500)
  |> keep(columns: ["name", "_value"])
```

**SQL equivalent:**
```sql
SELECT name, value
FROM "host.process_cpu_usage"
WHERE $__timeFilter(time)
  AND time = (SELECT MAX(time) FROM "host.process_cpu_usage" WHERE $__timeFilter(time))
ORDER BY value DESC
LIMIT 500
```

> **Dashboard JSON update required:** Panel id 5 has field overrides matching column `_value` with displayName "CPU Usage %". Change the override matcher from `_value` to `value`.

#### 5.1.6 Process Memory Table (Top 500) — Panel id: 6, "Memory Usage per Process (Top 500)"

Same pattern as 5.1.5 but using `"host.process_memory_usage"`.

```sql
SELECT name, value
FROM "host.process_memory_usage"
WHERE $__timeFilter(time)
  AND time = (SELECT MAX(time) FROM "host.process_memory_usage" WHERE $__timeFilter(time))
ORDER BY value DESC
LIMIT 500
```

> **Dashboard JSON update required:** Panel id 6 has field overrides matching column `_value` with displayName "Memory Usage". Change the override matcher from `_value` to `value`.

#### 5.1.7 System Load Average — Panel id: 9, "System Load Average"

**Current Flux:**
```flux
from(bucket: "mybucket")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r._measurement == "host.load1" or r._measurement == "host.load5" or r._measurement == "host.load15")
  |> map(fn: (r) => ({_time: r._time, _value: r._value, _field: if r._measurement == "host.load1" then "load1" else if r._measurement == "host.load5" then "load5" else "load15"}))
  |> group(columns: ["_field"])
  |> aggregateWindow(every: v.windowPeriod, fn: mean, createEmpty: false)
  |> yield(name: "mean")
```

**SQL equivalent:**
```sql
SELECT
  date_bin('$__interval', time) AS time,
  'load1' AS metric,
  AVG(value) AS value
FROM "host.load1"
WHERE $__timeFilter(time)
GROUP BY date_bin('$__interval', time)
UNION ALL
SELECT
  date_bin('$__interval', time) AS time,
  'load5' AS metric,
  AVG(value) AS value
FROM "host.load5"
WHERE $__timeFilter(time)
GROUP BY date_bin('$__interval', time)
UNION ALL
SELECT
  date_bin('$__interval', time) AS time,
  'load15' AS metric,
  AVG(value) AS value
FROM "host.load15"
WHERE $__timeFilter(time)
GROUP BY date_bin('$__interval', time)
ORDER BY time
```

#### 5.1.8 Memory Details (Active, Available, Free) — Panel id: 10, "Memory Details"

**Current Flux:**
```flux
from(bucket: "mybucket")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r._measurement == "host.memory_active_bytes" or r._measurement == "host.memory_available_bytes" or r._measurement == "host.memory_free_bytes")
  |> map(fn: (r) => ({_time: r._time, _value: r._value, _field: if r._measurement == "host.memory_active_bytes" then "active" else if r._measurement == "host.memory_available_bytes" then "available" else "free"}))
  |> group(columns: ["_field"])
  |> aggregateWindow(every: v.windowPeriod, fn: mean, createEmpty: false)
  |> yield(name: "mean")
```

**SQL equivalent:**
```sql
SELECT
  date_bin('$__interval', time) AS time,
  'active' AS metric,
  AVG(value) AS value
FROM "host.memory_active_bytes"
WHERE $__timeFilter(time)
GROUP BY date_bin('$__interval', time)
UNION ALL
SELECT
  date_bin('$__interval', time) AS time,
  'available' AS metric,
  AVG(value) AS value
FROM "host.memory_available_bytes"
WHERE $__timeFilter(time)
GROUP BY date_bin('$__interval', time)
UNION ALL
SELECT
  date_bin('$__interval', time) AS time,
  'free' AS metric,
  AVG(value) AS value
FROM "host.memory_free_bytes"
WHERE $__timeFilter(time)
GROUP BY date_bin('$__interval', time)
ORDER BY time
```

#### 5.1.9 Process CPU Time Series — Panel id: 11, "CPU Usage per Process Over Time"

**Current Flux:**
```flux
from(bucket: "mybucket")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r._measurement == "host.process_cpu_usage")
  |> keep(columns: ["_time", "_value", "name"])
  |> group(columns: ["name"])
  |> aggregateWindow(every: v.windowPeriod, fn: mean, createEmpty: true)
  |> fill(value: 0.0)
```

**SQL equivalent:**
```sql
SELECT
  date_bin('$__interval', time) AS time,
  name AS metric,
  AVG(value) AS value
FROM "host.process_cpu_usage"
WHERE $__timeFilter(time)
GROUP BY date_bin('$__interval', time), name
ORDER BY time
```

> **Note:** The original Flux uses `createEmpty: true` and `fill(value: 0.0)` to fill gaps with zeros. SQL does not have a direct equivalent for gap-filling. The SQL query will return only time bins with actual data. For most monitoring use cases this is acceptable — Grafana's `spanNulls` option (already set to `false` in this panel) handles the visual gap display. If zero-filling is critical, consider using `COALESCE` with a gap-filling CTE, but this adds significant complexity.

> **Dashboard JSON update required:** Panel id 11 uses `displayName: "${__field.labels.name}"` which relies on Flux label format. With SQL mode, the series are identified differently. Test whether the `metric` column alias works as the series name, and if not, update `displayName` to `${__field.name}` or remove it to let Grafana auto-detect series names.

#### 5.1.10 Process Memory Time Series — Panel id: 12, "Memory Usage per Process Over Time"

**Current Flux:**
```flux
from(bucket: "mybucket")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r._measurement == "host.process_memory_usage")
  |> keep(columns: ["_time", "_value", "name"])
  |> group(columns: ["name"])
  |> aggregateWindow(every: v.windowPeriod, fn: mean, createEmpty: false)
```

**SQL equivalent:**
```sql
SELECT
  date_bin('$__interval', time) AS time,
  name AS metric,
  AVG(value) AS value
FROM "host.process_memory_usage"
WHERE $__timeFilter(time)
GROUP BY date_bin('$__interval', time), name
ORDER BY time
```

> **Dashboard JSON update required:** Same `displayName` concern as panel id 11 — see note in 5.1.9.

---

## Phase 6: Testing and Validation

### 6.1 End-to-End Smoke Test

```bash
# 1. Start the full stack
docker compose up -d

# 2. Wait for InfluxDB 3 to be ready
sleep 5
curl http://localhost:8334/health

# 3. Create database (if not auto-created)
docker exec influxdb influxdb3 create database mybucket

# 4. Start Vector
vector --config vector.toml &

# 5. Wait for data to accumulate
sleep 30

# 6. Query data to verify writes
docker exec influxdb influxdb3 query \
  --database mybucket \
  "SELECT count(*) FROM \"host.cpu_seconds_total\""

# 7. Open Grafana and verify dashboards
open http://localhost:3046
```

### 6.2 Panel-by-Panel Validation

Check each dashboard panel in Grafana:

| Panel | ID | Expected Behavior |
|-------|----|-------------------|
| CPU Usage | 1 | Line chart showing user, system, idle percentages |
| Memory Usage | 2 | Single line showing used memory percentage |
| Disk Usage | 3 | Lines per mount showing used ratio percentage |
| Network Traffic | 4 | Lines per device showing bytes/sec RX and TX |
| CPU Usage per Process (Top 500) | 5 | Table sorted by CPU usage descending, "CPU Usage %" column renders |
| Memory Usage per Process (Top 500) | 6 | Table sorted by memory usage descending, "Memory Usage" column renders |
| System Load Average | 9 | Three lines for load1, load5, load15 |
| Memory Details | 10 | Three lines for active, available, free bytes |
| CPU Usage per Process Over Time | 11 | Time series grouped by process name |
| Memory Usage per Process Over Time | 12 | Time series grouped by process name |

### 6.3 Performance Monitoring

```bash
# Monitor container resource usage
docker stats influxdb grafana

# Check InfluxDB 3 query performance
time docker exec influxdb influxdb3 query \
  --database mybucket \
  "SELECT count(*) FROM \"host.cpu_seconds_total\" WHERE time > now() - INTERVAL '1 hour'"
```

---

## Phase 7: Cleanup and Documentation

### 7.1 Remove Old Volume

```bash
# Ensure old containers are stopped
docker compose down

# Remove the old InfluxDB 2 volume
docker volume rm monitor-mac_influxdb-data
```

### 7.2 Remove Legacy Files

```bash
# Remove Telegraf config (leftover from pre-Vector setup)
rm telegraf.conf
```

### 7.3 Update Documentation

Update the following files to reference InfluxDB 3 Core:

- **`README.md`**: Update architecture description, port references, configuration table, and remove "Data is retained for 7 days" note.
- **`README-vector.md`**: Update references from "InfluxDB 2.x" to "InfluxDB 3 Core".
- **`CLAUDE.md`**: Update architecture overview (change "InfluxDB 2.x" to "InfluxDB 3 Core", port from 8086 to 8181), configuration details, and access URLs.

### 7.4 Commit

```bash
git add -A
git commit -m "upgrade InfluxDB from v2 to v3 Core

- Replace influxdb:2-alpine with influxdb:3-core Docker image
- Use CLI command flags instead of env vars (per official Docker Hub example)
- Update port mapping from 8086 to 8181 (internal)
- Migrate Grafana datasource from Flux to SQL query language
- Rewrite all dashboard queries from Flux to SQL
- Update table panel field overrides for SQL column names
- Update Vector sink comments for v3 compatibility
- Remove legacy telegraf.conf
- Update documentation"
```

---

## Reference: File Change Summary

| File | Change Type | Description |
|------|-------------|-------------|
| `docker-compose.yml` | Modify | New image, port, CLI command flags, volumes |
| `vector.toml` | Modify | Update comments, token value |
| `grafana/provisioning/datasources/datasource.yml` | Modify | Flux to SQL, new URL, add database, remove org/bucket |
| `grafana/dashboards/macos-metrics.json` | Modify | Rewrite all queries from Flux to SQL, update field overrides (`_value` → `value`), update/test `displayName` templates |
| `README.md` | Modify | Update InfluxDB version references, remove retention note |
| `README-vector.md` | Modify | Update InfluxDB version references |
| `CLAUDE.md` | Modify | Update configuration and architecture |
| `telegraf.conf` | Delete | Legacy file, no longer needed |

---

## Reference Links

- [InfluxDB 3 Core Documentation](https://docs.influxdata.com/influxdb3/core/)
- [InfluxDB 3 Core Docker Setup](https://docs.influxdata.com/influxdb3/core/get-started/setup/?t=Docker)
- [InfluxDB 3 Core Configuration Options](https://docs.influxdata.com/influxdb3/core/reference/config-options/)
- [InfluxDB 3 v1/v2 Compatibility Write APIs](https://docs.influxdata.com/influxdb3/core/write-data/http-api/compatibility-apis/)
- [InfluxDB 3 v3 Write API](https://docs.influxdata.com/influxdb3/core/write-data/http-api/v3-write-lp/)
- [InfluxDB 3 Core SQL Reference](https://docs.influxdata.com/influxdb3/core/reference/sql/)
- [InfluxDB 3 Core SQL Window Functions](https://docs.influxdata.com/influxdb3/core/reference/sql/functions/window/)
- [InfluxDB 3 Core SQL Time/Date Functions](https://docs.influxdata.com/influxdb3/core/reference/sql/functions/time-and-date/)
- [Grafana InfluxDB Datasource with SQL](https://grafana.com/docs/grafana/latest/datasources/influxdb/configure-influxdb-data-source/)
- [InfluxDB 3 Core Docker Hub](https://hub.docker.com/_/influxdb) (tags: `3-core`, `3.8-core`, `core`)
- [Vector InfluxDB Metrics Sink](https://vector.dev/docs/reference/configuration/sinks/influxdb_metrics/)
- [Known Issue: Env Var Naming (GitHub #26459)](https://github.com/influxdata/influxdb/issues/26459)
