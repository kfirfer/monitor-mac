#!/usr/bin/env bash
# fix-wal.sh — Recover from InfluxDB WAL/snapshot/catalog corruption
# Usage: ./scripts/fix-wal.sh [--dry-run]
set -euo pipefail

VOLUME="monitor-mac_influxdb3-data"
DRY_RUN=false
LOG_PREFIX="[fix-wal]"

if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=true
fi

log() { printf '%s %s %s\n' "$LOG_PREFIX" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

log "=== InfluxDB WAL Recovery ==="
if $DRY_RUN; then
    log "DRY-RUN MODE — no files will be deleted"
fi

# 1. Stop Vector to prevent write attempts
log "Stopping Vector..."
launchctl unload ~/Library/LaunchAgents/com.vector.metrics.plist 2>/dev/null || true

# 2. Scan for corrupt files using busybox (works even when InfluxDB is crash-looping)
log "Scanning for corrupt files..."

CORRUPT_WAL=$(docker run --rm -v "$VOLUME":/data busybox find /data/node0/wal -name "*.wal" -size 0 2>/dev/null || true)
CORRUPT_JSON=$(docker run --rm -v "$VOLUME":/data busybox find /data/node0 -name "*.json" -size 0 2>/dev/null || true)
CORRUPT_CATALOG=$(docker run --rm -v "$VOLUME":/data busybox find /data/node0/catalog -type f -size 0 2>/dev/null || true)
CORRUPT_PARQUET=$(docker run --rm -v "$VOLUME":/data busybox find /data/node0 -name "*.parquet" -size 0 2>/dev/null || true)

ALL_CORRUPT=""
[ -n "$CORRUPT_WAL" ] && ALL_CORRUPT="${ALL_CORRUPT}${CORRUPT_WAL}"$'\n'
[ -n "$CORRUPT_JSON" ] && ALL_CORRUPT="${ALL_CORRUPT}${CORRUPT_JSON}"$'\n'
[ -n "$CORRUPT_CATALOG" ] && ALL_CORRUPT="${ALL_CORRUPT}${CORRUPT_CATALOG}"$'\n'
[ -n "$CORRUPT_PARQUET" ] && ALL_CORRUPT="${ALL_CORRUPT}${CORRUPT_PARQUET}"$'\n'

if [ -z "$(echo "$ALL_CORRUPT" | tr -d '[:space:]')" ]; then
    log "No corrupt files found."
    log "Starting Vector..."
    launchctl load ~/Library/LaunchAgents/com.vector.metrics.plist 2>/dev/null || true
    log "=== Recovery complete (nothing to fix) ==="
    exit 0
fi

log "Found corrupt files:"
[ -n "$CORRUPT_WAL" ] && log "  WAL files: $(echo "$CORRUPT_WAL" | wc -l | tr -d ' ')"
[ -n "$CORRUPT_JSON" ] && log "  JSON files: $(echo "$CORRUPT_JSON" | wc -l | tr -d ' ')"
[ -n "$CORRUPT_CATALOG" ] && log "  Catalog files: $(echo "$CORRUPT_CATALOG" | wc -l | tr -d ' ')"
[ -n "$CORRUPT_PARQUET" ] && log "  Parquet files: $(echo "$CORRUPT_PARQUET" | wc -l | tr -d ' ')"
echo "$ALL_CORRUPT" | grep -v '^$'

if $DRY_RUN; then
    log "DRY-RUN: Would delete the above files. Exiting."
    log "Starting Vector..."
    launchctl load ~/Library/LaunchAgents/com.vector.metrics.plist 2>/dev/null || true
    exit 0
fi

# 3. Backup before deletion
BACKUP_FILE="/tmp/influxdb-wal-backup-$(date +%Y%m%d%H%M%S).tar.gz"
log "Backing up WAL/catalog/snapshots to $BACKUP_FILE..."
docker run --rm -v "$VOLUME":/data -v /tmp:/backup busybox \
    tar czf "/backup/$(basename "$BACKUP_FILE")" /data/node0/wal /data/node0/catalog /data/node0/snapshots 2>/dev/null || true

# 4. Delete corrupt files
log "Deleting corrupt files..."
docker run --rm -v "$VOLUME":/data busybox find /data/node0/wal -name "*.wal" -size 0 -delete 2>/dev/null || true
docker run --rm -v "$VOLUME":/data busybox find /data/node0 -name "*.json" -size 0 -delete 2>/dev/null || true
docker run --rm -v "$VOLUME":/data busybox find /data/node0/catalog -type f -size 0 -delete 2>/dev/null || true
docker run --rm -v "$VOLUME":/data busybox find /data/node0 -name "*.parquet" -size 0 -delete 2>/dev/null || true

# 5. Restart InfluxDB
log "Restarting InfluxDB..."
cd /Users/dev345/code/kfirfer/monitor-mac
docker compose restart influxdb

# 6. Wait for health
log "Waiting for InfluxDB to be healthy..."
HEALTHY=false
for i in $(seq 1 60); do
    if curl -sf http://localhost:8334/health > /dev/null 2>&1; then
        log "InfluxDB is healthy after ${i}s."
        HEALTHY=true
        break
    fi
    sleep 1
done

if ! $HEALTHY; then
    log "ERROR: InfluxDB did not become healthy within 60s."
    log "Check logs: docker logs influxdb --tail 30"
    exit 1
fi

# 7. Verify data query works
log "Verifying data query..."
RESULT=$(curl -s "http://localhost:8334/api/v3/query_sql?db=mybucket&q=SELECT+1" 2>/dev/null || true)
if echo "$RESULT" | grep -q "Int64"; then
    log "Data query verified successfully."
else
    log "WARN: Data query returned unexpected result: $RESULT"
fi

# 8. Restart Vector
log "Starting Vector..."
launchctl load ~/Library/LaunchAgents/com.vector.metrics.plist

log "=== Recovery complete ==="
