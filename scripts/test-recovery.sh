#!/usr/bin/env bash
# test-recovery.sh — Simulate WAL corruption and verify automatic recovery
# Usage: ./scripts/test-recovery.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VOLUME="monitor-mac_influxdb3-data"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

log "=== Recovery Simulation Test ==="

# 1. Verify InfluxDB is healthy before test
log "Step 1: Verifying InfluxDB is healthy..."
if ! curl -sf http://localhost:8334/health > /dev/null 2>&1; then
    log "ERROR: InfluxDB is not healthy. Cannot run test."
    exit 1
fi
log "  InfluxDB is healthy."

# 2. Stop InfluxDB ungracefully
log "Step 2: Killing InfluxDB ungracefully..."
docker kill influxdb 2>/dev/null || true
sleep 2

# 3. Create a 0-byte WAL file to simulate corruption
log "Step 3: Creating corrupt 0-byte WAL file..."
docker run --rm -v "$VOLUME":/data busybox touch /data/node0/wal/00000099999.wal
VERIFY=$(docker run --rm -v "$VOLUME":/data busybox ls -la /data/node0/wal/00000099999.wal 2>/dev/null)
log "  Created: $VERIFY"

# 4. Start InfluxDB — should enter crash loop
log "Step 4: Starting InfluxDB (expecting crash loop)..."
cd /Users/dev345/code/kfirfer/monitor-mac
docker compose up -d influxdb 2>/dev/null
sleep 10

STATUS=$(docker inspect influxdb --format='{{.State.Status}}' 2>/dev/null || echo "not_found")
log "  InfluxDB status after 10s: $STATUS"

if [ "$STATUS" = "running" ]; then
    # Check if it's healthy or just started
    if curl -sf http://localhost:8334/health > /dev/null 2>&1; then
        log "  NOTE: InfluxDB survived the corrupt file (may have skipped it). Cleaning up test file."
        docker run --rm -v "$VOLUME":/data busybox rm -f /data/node0/wal/00000099999.wal
        log "=== Test Result: InfluxDB is resilient to 0-byte WAL files (PASS) ==="
        exit 0
    fi
fi

# 5. Run fix-wal.sh
log "Step 5: Running fix-wal.sh..."
"$SCRIPT_DIR/fix-wal.sh"

# 6. Verify recovery
log "Step 6: Verifying recovery..."
RECOVERED=false
for i in $(seq 1 30); do
    if curl -sf http://localhost:8334/health > /dev/null 2>&1; then
        log "  InfluxDB recovered after ${i}s."
        RECOVERED=true
        break
    fi
    sleep 1
done

if ! $RECOVERED; then
    log "ERROR: InfluxDB did not recover within 30s."
    log "=== Test Result: FAIL ==="
    exit 1
fi

# 7. Verify data is flowing
log "Step 7: Checking data flow..."
sleep 15
RESULT=$(curl -s "http://localhost:8334/api/v3/query_sql?db=mybucket&q=SELECT+MAX(time)+as+latest+FROM+%22host.load1%22" 2>/dev/null)
if echo "$RESULT" | grep -q "latest"; then
    log "  Data is flowing: $RESULT"
else
    log "  WARN: No recent data found."
fi

# 8. Verify Grafana is up
if curl -sf http://localhost:3046/api/health > /dev/null 2>&1; then
    log "  Grafana is healthy."
else
    log "  WARN: Grafana health check failed."
fi

log "=== Test Result: PASS ==="
