#!/usr/bin/env bash
# Long-running LaunchAgent that gracefully stops monitoring containers on macOS shutdown
# launchd sends SIGTERM during shutdown; we trap it and run cleanup

set -uo pipefail

LOG=/tmp/shutdown-hook.log

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"; }

cleanup() {
    log "Received shutdown signal, stopping monitoring containers..."
    cd /Users/dev345/code/kfirfer/monitor-mac || { log "ERROR: Cannot cd to project dir"; exit 1; }
    /Users/dev345/.orbstack/bin/docker compose stop -t 8 >>"$LOG" 2>&1 || log "WARN: docker compose stop failed"
    log "Shutdown hook completed"
    exit 0
}

trap cleanup SIGTERM SIGHUP SIGINT

log "Shutdown hook daemon started (PID $$)"

# Sleep indefinitely; wait allows trap to fire immediately on signal
while true; do sleep 86400 & wait $!; done
