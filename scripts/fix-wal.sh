#!/usr/bin/env bash
# fix-wal.sh — Recover from InfluxDB WAL corruption
# Usage: ./scripts/fix-wal.sh
set -euo pipefail

CONTAINER="influxdb"
WAL_DIR="/var/lib/influxdb3/data/node0/wal"

echo "=== InfluxDB WAL Recovery ==="

# 1. Find corrupt (0-byte) WAL files
echo "Scanning for corrupt WAL files..."
CORRUPT=$(docker exec "$CONTAINER" find "$WAL_DIR" -name "*.wal" -size 0 2>/dev/null)

if [ -z "$CORRUPT" ]; then
    echo "No corrupt WAL files found."
    exit 0
fi

echo "Found corrupt WAL files:"
echo "$CORRUPT"
echo ""

# 2. Stop Vector to prevent write attempts
echo "Stopping Vector..."
launchctl unload ~/Library/LaunchAgents/com.vector.metrics.plist 2>/dev/null || true

# 3. Delete corrupt files
echo "Deleting corrupt WAL files..."
docker exec "$CONTAINER" find "$WAL_DIR" -name "*.wal" -size 0 -delete

# 4. Restart InfluxDB
echo "Restarting InfluxDB..."
cd /Users/dev345/code/kfirfer/monitor-mac
docker compose restart influxdb

# 5. Wait for health
echo "Waiting for InfluxDB to be healthy..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:8334/health > /dev/null 2>&1; then
        echo "InfluxDB is healthy."
        break
    fi
    sleep 1
done

# 6. Restart Vector
echo "Starting Vector..."
launchctl load ~/Library/LaunchAgents/com.vector.metrics.plist

echo "=== Recovery complete ==="
