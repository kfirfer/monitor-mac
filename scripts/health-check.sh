#!/usr/bin/env bash
# health-check.sh — Monitors monitoring pipeline health and auto-recovers
# Usage: ./scripts/health-check.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG=/tmp/health-check.log

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

ISSUES=0

# 1. Check InfluxDB container status
INFLUX_STATUS=$(docker inspect influxdb --format='{{.State.Status}}' 2>/dev/null || echo "not_found")
INFLUX_RESTARTS=$(docker inspect influxdb --format='{{.RestartCount}}' 2>/dev/null || echo "0")

if [ "$INFLUX_STATUS" = "restarting" ] || [ "$INFLUX_RESTARTS" -gt 3 ] 2>/dev/null; then
    log "ALERT: InfluxDB in crash loop (status: $INFLUX_STATUS, restarts: $INFLUX_RESTARTS). Triggering recovery..."
    "$SCRIPT_DIR/fix-wal.sh" >> "$LOG" 2>&1
    ISSUES=$((ISSUES + 1))
elif [ "$INFLUX_STATUS" != "running" ]; then
    log "WARN: InfluxDB not running (status: $INFLUX_STATUS). Attempting restart..."
    cd /Users/dev345/code/kfirfer/monitor-mac && docker compose up -d influxdb >> "$LOG" 2>&1
    ISSUES=$((ISSUES + 1))
fi

# 2. Check InfluxDB health endpoint
if [ "$INFLUX_STATUS" = "running" ]; then
    if ! curl -sf http://localhost:8334/health > /dev/null 2>&1; then
        log "WARN: InfluxDB running but health endpoint not responding."
        ISSUES=$((ISSUES + 1))
    fi
fi

# 3. Check Vector process
# Use `launchctl list LABEL` (exits 113 if missing) instead of piping to grep —
# `grep -q` early-exits on match, causing SIGPIPE 141 under `set -o pipefail`
# which produced persistent "Vector not running" false positives.
if ! launchctl list com.vector.metrics > /dev/null 2>&1; then
    log "ALERT: Vector not running. Restarting..."
    launchctl load ~/Library/LaunchAgents/com.vector.metrics.plist 2>/dev/null || true
    ISSUES=$((ISSUES + 1))
fi

# 4. Check data freshness (last write within 5 minutes)
# Parses the MAX(time) timestamp and compares to wall clock. Triggers recovery
# on stalls — Vector can sit alive with no data flowing (see 2026-04-12 outage).
if curl -sf http://localhost:8334/health > /dev/null 2>&1; then
    LATEST=$(curl -s "http://localhost:8334/api/v3/query_sql?db=mybucket&q=SELECT+MAX(time)+as+latest+FROM+%22host.load1%22" 2>/dev/null || true)
    LATEST_TS=$(printf '%s' "$LATEST" | sed -nE 's/.*"latest":"([^"]+)".*/\1/p')

    if [ -z "$LATEST_TS" ]; then
        log "WARN: No data found in InfluxDB (host.load1 empty or query failed). Response: $LATEST"
        ISSUES=$((ISSUES + 1))
    else
        LATEST_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "${LATEST_TS%.*}" +%s 2>/dev/null || echo "0")
        NOW_EPOCH=$(date -u +%s)
        AGE=$((NOW_EPOCH - LATEST_EPOCH))
        if [ "$LATEST_EPOCH" -eq 0 ]; then
            log "WARN: Could not parse latest timestamp: $LATEST_TS"
            ISSUES=$((ISSUES + 1))
        elif [ "$AGE" -gt 300 ]; then
            log "ALERT: Data is stale (${AGE}s old, latest=$LATEST_TS). Restarting Vector..."
            launchctl unload ~/Library/LaunchAgents/com.vector.metrics.plist 2>/dev/null || true
            sleep 2
            launchctl load ~/Library/LaunchAgents/com.vector.metrics.plist 2>/dev/null || true
            ISSUES=$((ISSUES + 1))
        fi
    fi
fi

if [ "$ISSUES" -eq 0 ]; then
    log "OK: All checks passed."
fi
