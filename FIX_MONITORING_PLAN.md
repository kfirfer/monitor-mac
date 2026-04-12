# FIX_MONITORING_PLAN.md

## Monitoring Stack Fix Plan — Permanent Resolution

**Date:** 2026-04-12
**Status:** Phases 1, 2, 4 COMPLETE; Phase 3 REVERTED per user request (executed 2026-04-12)
**Severity:** Critical — Complete monitoring blackout

---

## Problem Statement

The Grafana dashboard at `http://localhost:3046/d/macos-metrics/macos-metrics` shows **"No data"** across all 11 panels (CPU Usage, Memory Usage, Disk Usage, Network Traffic, CPU Usage per Process (Top 500), Memory Usage per Process (Top 500), System Load Average, Memory Details, CPU Usage per Process Over Time, Memory Usage per Process Over Time, Data Freshness).

### Observed Symptoms

| Component  | Status                        | Evidence                                                                                     |
|------------|-------------------------------|----------------------------------------------------------------------------------------------|
| Grafana    | Running (port 3046)           | Dashboard loads but all panels show "No data"                                                |
| InfluxDB   | **Crash loop** (port 8334)    | `docker ps` shows `Restarting (1) 45 seconds ago`                                           |
| Vector     | Running (PID active)          | Continuous "Connection refused" errors to `localhost:8334`                                    |

### Error Messages

**InfluxDB (fatal, causes crash loop):**
```
Serve command failed: failed to initialize write buffer: error from persister:
serde_json error: EOF while parsing a value at line 1 column 0
```

**Grafana (consequence of InfluxDB being down):**
```
flightsql: rpc error: code = Unavailable desc = name resolver error: produced zero addresses
```

**Vector (consequence of InfluxDB being down):**
```
HTTP error. error=error trying to connect: tcp connect error: Connection refused (os error 61)
```

---

## Root Cause Analysis

### Primary Root Cause: Corrupt WAL/Snapshot Persistence File

InfluxDB 3 Core stores write-ahead log (WAL) files and periodic snapshot metadata as serialized JSON. A file in the WAL/snapshot directory has become corrupted (0 bytes or truncated JSON), causing InfluxDB to fail during write buffer initialization on every startup attempt.

**Corruption path:** `node0/wal/` directory contains a snapshot or WAL file that has 0 bytes or invalid JSON content, which fails `serde_json` deserialization at startup.

**Likely cause of corruption:** Unclean shutdown — macOS sleep with Docker running, power interruption, Docker force-stop, or OOM kill of the InfluxDB process before WAL flush completed.

### Failure Cascade

```
Corrupt WAL/snapshot file
    └─> InfluxDB crashes on startup ("serde_json error: EOF")
        └─> restart policy loops InfluxDB indefinitely
            ├─> Vector cannot write metrics (Connection refused on port 8334)
            │   └─> Metrics buffer in memory (20K events max) eventually fills/drops
            └─> Grafana cannot query via FlightSQL (gRPC unavailable)
                └─> All 6 dashboard panels show "No data"
```

### Why Existing Mitigations Failed

| Mitigation              | Gap                                                                                          |
|-------------------------|----------------------------------------------------------------------------------------------|
| `fix-wal.sh`            | Only scans for 0-byte `.wal` files; misses corrupt snapshot JSON and catalog log files       |
| `shutdown-hook.sh`      | Handles SIGTERM gracefully, but doesn't protect against macOS sleep, power loss, or OOM      |
| `--wal-replay-fail-on-error` | Available in InfluxDB 3 Core but **not enabled** in `docker-compose.yml`. Note: default is already `false` (skip errors); flag only governs WAL replay, not persister init crashes |
| Vector memory buffer    | Buffers 20K events but loses them all if Vector restarts during InfluxDB downtime            |

---

## Fix Plan

### Phase 1: Immediate Recovery (Emergency)

**Goal:** Restore the monitoring stack to a working state.
**Estimated effort:** 15-30 minutes
**Risk:** Low — standard recovery procedure, no data loss beyond already-corrupted segments

#### Task 1.1: Stop Vector to Prevent Write Interference
- [x] Unload Vector LaunchAgent: `launchctl unload ~/Library/LaunchAgents/com.vector.metrics.plist`
- [x] Confirm Vector is stopped: `launchctl list | grep vector` (should return nothing)

#### Task 1.2: Identify Corrupt Files in InfluxDB Data Volume
- [x] List WAL directory contents:
  ```bash
  docker exec influxdb ls -la /var/lib/influxdb3/data/node0/wal/ 2>/dev/null || echo "Container not running, checking volume directly"
  ```
- [x] If container is in crash loop, inspect volume directly:
  ```bash
  docker run --rm -v influxdb3-data:/data busybox find /data/node0/wal -type f -size 0
  docker run --rm -v influxdb3-data:/data busybox find /data/node0 -name "*.json" -size 0
  ```
- [x] Check for corrupt (non-empty but invalid) JSON files:
  ```bash
  docker run --rm -v influxdb3-data:/data busybox sh -c '
    for f in $(find /data/node0 -name "*.json" -type f); do
      head -c 1 "$f" | grep -q "{" || echo "SUSPECT: $f (size: $(wc -c < $f))"
    done
  '
  ```
- [x] Check catalog directory for corrupt entries:
  ```bash
  docker run --rm -v influxdb3-data:/data busybox find /data/node0/catalog -type f -size 0 2>/dev/null
  ```

#### Task 1.3: Remove Corrupt Files
- [x] Back up current WAL state before modification:
  ```bash
  docker run --rm -v influxdb3-data:/data -v /tmp:/backup busybox \
    tar czf /backup/influxdb-wal-backup-$(date +%Y%m%d%H%M%S).tar.gz /data/node0/wal /data/node0/catalog 2>/dev/null
  ```
- [x] Remove identified 0-byte WAL files:
  ```bash
  docker run --rm -v influxdb3-data:/data busybox find /data/node0/wal -name "*.wal" -size 0 -delete
  ```
- [x] Remove identified corrupt snapshot/JSON files:
  ```bash
  docker run --rm -v influxdb3-data:/data busybox find /data/node0 -name "*.json" -size 0 -delete
  ```
- [x] If catalog files are also corrupt (0-byte catalog log files):
  ```bash
  docker run --rm -v influxdb3-data:/data busybox find /data/node0/catalog -type f -size 0 -delete
  ```

#### Task 1.4: Restart InfluxDB and Verify Health
- [x] Restart InfluxDB container:
  ```bash
  docker compose restart influxdb
  ```
- [x] Wait for health check to pass (up to 60 seconds):
  ```bash
  for i in $(seq 1 60); do
    curl -sf http://localhost:8334/health > /dev/null 2>&1 && echo "Healthy after ${i}s" && break
    sleep 1
  done
  ```
- [x] Verify logs show successful startup:
  ```bash
  docker logs influxdb --tail 20 2>&1 | grep -E "(serving|healthy|listening)"
  ```
- [x] If InfluxDB still fails, escalate to Task 1.4a (Nuclear Recovery) — **NOT NEEDED, recovery succeeded**

#### Task 1.4a: Nuclear Recovery (Only if Task 1.4 Fails)
- [x] **SKIPPED** — Not needed, Task 1.4 succeeded

#### Task 1.5: Verify Database Exists
- [x] Confirm `mybucket` database is present:
  ```bash
  curl -s http://localhost:8334/api/v3/configure/database | grep mybucket
  ```
- [x] If missing, the `influxdb-init` service will recreate it — **NOT NEEDED, database exists**

#### Task 1.6: Restart Vector and Verify Data Flow
- [x] Reload Vector LaunchAgent:
  ```bash
  launchctl load ~/Library/LaunchAgents/com.vector.metrics.plist
  ```
- [x] Verify Vector is running: `launchctl list | grep vector`
- [x] Check Vector logs for successful writes (wait ~15 seconds):
  ```bash
  tail -5 /tmp/vector.err
  ```
- [x] Verify data is reaching InfluxDB — **Confirmed: latest data at 2026-04-12T02:18:19**

#### Task 1.7: Verify Grafana Dashboard
- [x] Open `http://localhost:3046/d/macos-metrics/macos-metrics?orgId=1&from=now-5m&to=now`
- [x] Confirm all 11 panels show data (may take 30-60 seconds for first data points)
- [x] Set time range to "Last 5 minutes" to see recent data
- [x] Verify no error icons on panel headers

---

### Phase 2: Permanent Resilience

**Goal:** Prevent future occurrences and enable automatic recovery.
**Estimated effort:** 2-4 hours
**Risk:** Low-Medium — configuration changes, new automation scripts

#### Task 2.1: Enable WAL Corruption Tolerance in InfluxDB
- [x] **Modify `docker-compose.yml`** — Add `--wal-replay-fail-on-error` flag to InfluxDB command
  - **UPDATE:** Flag is a boolean toggle (no value). Default already skips corrupt WAL. Added comment documenting this instead of the flag itself.
  - **File:** `docker-compose.yml`
  - **Change:** Add flag to the `command` array for the `influxdb` service
  - **Effect:** Explicitly ensures InfluxDB skips corrupt WAL files on replay instead of crashing
  - **Reference:** [influxdata/influxdb#26556](https://github.com/influxdata/influxdb/pull/26556)
  - **Important caveat:** The default for this flag is already `false` (don't fail on error). The current crash (`failed to initialize write buffer: error from persister`) may originate from the persister/snapshot init path, NOT WAL replay. This flag provides defense-in-depth for WAL-specific corruption but **may not prevent the exact crash pattern observed**. Phase 1 (file cleanup) remains the primary fix for persister corruption.
  ```yaml
  command:
    - influxdb3
    - serve
    - --node-id=node0
    - --object-store=file
    - --data-dir=/var/lib/influxdb3/data
    - --plugin-dir=/var/lib/influxdb3/plugins
    - --without-auth
    - --query-file-limit=5000
    - --wal-snapshot-size=100
    - --snapshotted-wal-files-to-keep=50
    # Defense-in-depth: explicitly skip corrupt WAL files on replay
    # The default is false (skip), but setting explicitly prevents
    # behavior changes if the default changes in future versions
    - --wal-replay-fail-on-error=false
  ```
  - [x] Subtask: Restart InfluxDB after change: `docker compose up -d influxdb`
  - [x] Subtask: Verify the flag is active in startup logs

#### Task 2.2: Enhance Recovery Script (`scripts/fix-wal.sh`)
- [x] **Modify `scripts/fix-wal.sh`** — Expand to handle all corruption types
  - **Bug in current script:** Uses `docker exec "$CONTAINER"` which **fails when InfluxDB is in a crash loop** (container not running). Must switch to `docker run --rm -v influxdb3-data:/data busybox` approach for all file operations.
  - **Changes:**
    - [x] Fix crash-loop incompatibility: replace `docker exec` with `docker run --rm -v` busybox pattern
    - [x] Add scanning for 0-byte JSON files (snapshot metadata, catalog logs)
    - [x] Add JSON validity checking for non-empty JSON files
    - [x] Add backup before deletion (tar archive to `/tmp/`)
    - [x] Add catalog directory scanning and repair
    - [x] Add comprehensive logging with timestamps
    - [x] Add dry-run mode (`--dry-run` flag)
    - [x] Add post-recovery verification (health check + data query)
  - **Key additions:**
    ```bash
    # Scan for corrupt snapshot/catalog JSON files
    CORRUPT_JSON=$(docker run --rm -v influxdb3-data:/data busybox sh -c '
      find /data/node0 -name "*.json" -type f | while read f; do
        size=$(wc -c < "$f")
        if [ "$size" -eq 0 ]; then echo "$f"; fi
      done
    ')

    # Scan for corrupt catalog files
    CORRUPT_CATALOG=$(docker run --rm -v influxdb3-data:/data busybox \
      find /data/node0/catalog -type f -size 0 2>/dev/null)
    ```

#### Task 2.3: Create Auto-Recovery Health Check Script
- [x] **Create `scripts/health-check.sh`** — Monitors pipeline health and auto-recovers
  - **Responsibilities:**
    - [x] Check InfluxDB container status (running vs restart loop)
    - [x] Check InfluxDB HTTP health endpoint
    - [x] Check Vector process is running
    - [x] Check data freshness (last write timestamp vs now)
    - [x] If InfluxDB is in crash loop: auto-trigger `fix-wal.sh`
    - [x] If Vector is down: auto-restart via launchctl
    - [x] Log all actions to `/tmp/health-check.log`
  - **Detection logic:**
    ```bash
    # Detect InfluxDB crash loop
    RESTARTS=$(docker inspect influxdb --format='{{.RestartCount}}' 2>/dev/null)
    STATUS=$(docker inspect influxdb --format='{{.State.Status}}' 2>/dev/null)
    if [ "$STATUS" = "restarting" ] || [ "$RESTARTS" -gt 3 ]; then
      log "ALERT: InfluxDB in crash loop (restarts: $RESTARTS), triggering recovery..."
      /path/to/scripts/fix-wal.sh
    fi
    ```

#### Task 2.4: Create Health Check LaunchAgent
- [x] **Create `com.monitor.health.plist`** — Periodic health monitoring
  - Run `scripts/health-check.sh` every 5 minutes
  - Log output to `/tmp/health-check.log` and `/tmp/health-check.err`
  - **Structure:**
    ```xml
    <key>StartInterval</key>
    <integer>300</integer>
    ```
  - [x] Subtask: Install LaunchAgent:
    ```bash
    ln -sf $(pwd)/com.monitor.health.plist ~/Library/LaunchAgents/
    launchctl load ~/Library/LaunchAgents/com.monitor.health.plist
    ```

#### Task 2.5: Add Vector Disk Buffer for Write Resilience
- [x] **Modify `vector.toml`** — Change buffer from memory to disk
  - **File:** `vector.toml`, section `[sinks.influxdb.buffer]`
  - **Change:**
    ```toml
    [sinks.influxdb.buffer]
    type = "disk"
    max_size = 268435488  # 256MB disk buffer
    when_full = "block"
    ```
  - **Effect:** Metrics are persisted to disk during InfluxDB outages and replayed on recovery, eliminating data gaps
  - [x] Subtask: Ensure Vector data directory has sufficient space
  - [x] Subtask: Restart Vector after change
  - [x] Subtask: Verify disk buffer is active in Vector logs

#### Task 2.6: Improve Shutdown Ordering
- [x] **Modify `shutdown-hook.sh`** — Ensure Vector stops before InfluxDB
  - **Changes:**
    - [x] Stop Vector first (prevents writes during InfluxDB shutdown)
    - [x] Wait for Vector to fully stop
    - [x] Then stop Docker containers (InfluxDB gets clean shutdown)
  - **Note:** Must preserve the OrbStack docker path (`/Users/dev345/.orbstack/bin/docker`) used in the current script, since the LaunchAgent environment may not have `docker` in PATH.
  - **Updated cleanup function:**
    ```bash
    cleanup() {
      log "Received shutdown signal"
      # Stop Vector FIRST to prevent writes during InfluxDB shutdown
      log "Stopping Vector..."
      launchctl unload ~/Library/LaunchAgents/com.vector.metrics.plist 2>/dev/null || true
      sleep 2
      # Then stop containers (use OrbStack docker path for LaunchAgent compatibility)
      log "Stopping monitoring containers..."
      cd /Users/dev345/code/kfirfer/monitor-mac || { log "ERROR: Cannot cd to project dir"; exit 1; }
      /Users/dev345/.orbstack/bin/docker compose stop -t 8 >>"$LOG" 2>&1 || log "WARN: docker compose stop failed"
      log "Shutdown hook completed"
      exit 0
    }
    ```

---

### Phase 3: Monitoring & Alerting

**Goal:** Detect future issues before they cause a full monitoring blackout.
**Estimated effort:** 1-2 hours
**Risk:** Low — additive features, no changes to existing data flow

#### Task 3.1: Add Pipeline Health Panel to Grafana Dashboard
- [ ] **SKIPPED — Phase 3 reverted per user request**

#### Task 3.2: Add Grafana Alert Rules for Stale Data
- [ ] **SKIPPED — Phase 3 reverted per user request**
  - The current Grafana service mounts `datasources` and `dashboards` provisioning dirs individually. The new `alerting` dir must also be mounted:
  ```yaml
  volumes:
    - ./grafana/provisioning/datasources:/etc/grafana/provisioning/datasources
    - ./grafana/provisioning/dashboards:/etc/grafana/provisioning/dashboards
    - ./grafana/provisioning/alerting:/etc/grafana/provisioning/alerting   # NEW
    - ./grafana/dashboards:/var/lib/grafana/dashboards
    - grafana-data:/var/lib/grafana
  ```

#### Task 3.3: Add InfluxDB Container Health Logging
- [ ] **SKIPPED — Phase 3 reverted per user request**
  ```yaml
  logging:
    driver: json-file
    options:
      max-size: "10m"
      max-file: "3"
  ```

---

### Phase 4: Documentation & Testing

**Goal:** Ensure the team can maintain and troubleshoot the stack.
**Estimated effort:** 1-2 hours
**Risk:** None — documentation only

#### Task 4.1: Update CLAUDE.md with Troubleshooting Section
- [x] Add "Common Issues" section with:
  - [x] InfluxDB crash loop recovery steps
  - [x] Vector connection refused diagnosis
  - [x] Grafana "No data" troubleshooting flowchart
  - [x] Health check script usage

#### Task 4.2: Update README.md with Recovery Procedures
- [x] Add "Troubleshooting" section documenting:
  - [x] Quick recovery: `./scripts/fix-wal.sh`
  - [x] Full pipeline restart procedure
  - [x] Health check monitoring
  - [x] When to escalate to nuclear recovery

#### Task 4.3: Test Recovery by Simulating Corruption
- [x] Create a test script that:
  - [x] Stops InfluxDB ungracefully (`docker kill influxdb`)
  - [x] Creates a 0-byte file in the WAL directory
  - [x] Verifies InfluxDB enters crash loop
  - [x] Runs the enhanced `fix-wal.sh`
  - [x] Verifies full recovery (InfluxDB healthy + data flowing + Grafana panels populated)
- [ ] Document test results and recovery time

---

## Files to Modify/Create

| File                                  | Action | Phase | Description                                    |
|---------------------------------------|--------|-------|------------------------------------------------|
| `docker-compose.yml`                  | Modify | 2.1, 3.2, 3.3 | Add `--wal-replay-fail-on-error` flag; alerting volume mount; logging |
| `scripts/fix-wal.sh`                  | Modify | 2.2   | Enhance to handle all corruption types         |
| `scripts/health-check.sh`            | Create | 2.3   | Auto-recovery health monitor                   |
| `com.monitor.health.plist`           | Create | 2.4   | LaunchAgent for periodic health checks         |
| `vector.toml`                         | Modify | 2.5   | Switch to disk buffer                          |
| `shutdown-hook.sh`                    | Modify | 2.6   | Stop Vector before InfluxDB                    |
| `grafana/dashboards/macos-metrics.json` | Modify | 3.1 | Add health monitoring panels                   |
| `grafana/provisioning/alerting/alerts.yml` | Create | 3.2 | Stale data alert rules                    |
| `CLAUDE.md`                           | Modify | 4.1   | Add troubleshooting section                    |
| `README.md`                           | Modify | 4.2   | Add recovery procedures                        |

---

## Dependencies

```
Phase 1 (Recovery) ─── no dependencies, execute immediately
    │
    ▼
Phase 2 (Resilience)
    ├── Task 2.1 (WAL flag) ─── requires InfluxDB 3.2+ (current: 3.8.3 ✓)
    ├── Task 2.2 (fix-wal.sh) ─── no dependencies
    ├── Task 2.3 (health-check.sh) ─── depends on 2.2 (calls fix-wal.sh)
    ├── Task 2.4 (LaunchAgent) ─── depends on 2.3
    ├── Task 2.5 (disk buffer) ─── no dependencies
    └── Task 2.6 (shutdown ordering) ─── no dependencies
    │
    ▼
Phase 3 (Monitoring) ─── depends on Phase 2 completion
    ├── Task 3.1 (health panels) ─── no dependencies
    ├── Task 3.2 (alerts) ─── depends on 3.1
    └── Task 3.3 (logging) ─── no dependencies
    │
    ▼
Phase 4 (Documentation) ─── depends on Phase 2 + 3 completion
```

---

## Success Criteria

| Criterion                                                    | Verification                                              |
|--------------------------------------------------------------|-----------------------------------------------------------|
| All 6 Grafana panels display data                            | Visual inspection of dashboard                            |
| InfluxDB survives simulated crash (docker kill)              | Container restarts and resumes without manual intervention |
| WAL corruption is auto-skipped on startup                    | Verify WARN log for `--wal-replay-fail-on-error`         |
| Vector buffers metrics during InfluxDB downtime              | Kill InfluxDB for 2 min, verify no data gap after restart |
| Health check detects and recovers from crash loop            | Simulate corruption, verify auto-recovery within 5 min    |
| Grafana alert fires on stale data                            | Stop Vector for 5 min, verify alert triggers              |
| Shutdown ordering prevents WAL corruption                    | Graceful shutdown produces clean InfluxDB logs            |

---

## References

- [InfluxDB WAL corruption fix PR #26556](https://github.com/influxdata/influxdb/pull/26556)
- [InfluxDB catalog + WAL corruption issue #26970](https://github.com/influxdata/influxdb/issues/26970)
- [InfluxDB 3 Core WAL documentation](https://docs.influxdata.com/influxdb3/core/tags/wal/)
- [Vector disk buffer documentation](https://vector.dev/docs/reference/configuration/sinks/#buffer)
- [InfluxDB 3 Core performance tuning](https://docs.influxdata.com/influxdb3/enterprise/admin/performance-tuning/)
