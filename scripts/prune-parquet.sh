#!/usr/bin/env bash
# prune-parquet.sh — Remove old Parquet files to prevent query-file-limit issues
# Usage: ./scripts/prune-parquet.sh [retention_days]
# Default retention: 7 days
set -euo pipefail

RETENTION_DAYS="${1:-7}"
CONTAINER="influxdb"
DATA_DIR="/var/lib/influxdb3/data/node0/dbs"
LOG="/tmp/parquet-prune.log"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }

log "Starting Parquet pruning (retention: ${RETENTION_DAYS} days)"

# Calculate cutoff date
CUTOFF_DATE=$(date -v-${RETENTION_DAYS}d '+%Y-%m-%d')
log "Cutoff date: $CUTOFF_DATE (deleting data older than this)"

# Get count before
BEFORE=$(docker exec "$CONTAINER" find "$DATA_DIR" -name "*.parquet" 2>/dev/null | wc -l | tr -d ' ')
log "Parquet files before pruning: $BEFORE"

# Find and delete date-partitioned directories older than cutoff
# Directory structure: dbs/<db_id>/<table_id>/<date>/...
docker exec "$CONTAINER" find "$DATA_DIR" -mindepth 3 -maxdepth 3 -type d | while read -r dir; do
    dirname=$(basename "$dir")
    # Check if directory name is a date (YYYY-MM-DD)
    if [[ "$dirname" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        if [[ "$dirname" < "$CUTOFF_DATE" ]]; then
            log "Removing old partition: $dir"
            docker exec "$CONTAINER" rm -rf "$dir"
        fi
    fi
done

# Get count after
AFTER=$(docker exec "$CONTAINER" find "$DATA_DIR" -name "*.parquet" 2>/dev/null | wc -l | tr -d ' ')
log "Parquet files after pruning: $AFTER (removed $((BEFORE - AFTER)))"
log "Pruning complete"
