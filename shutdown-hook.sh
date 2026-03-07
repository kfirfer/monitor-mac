#!/bin/bash
# Pre-shutdown hook: gracefully stop monitoring containers before macOS shuts down
# This ensures InfluxDB flushes WAL/catalog files properly

cd /Users/dev345/code/kfirfer/monitor-mac
/Users/dev345/.orbstack/bin/docker compose stop -t 10 2>/tmp/shutdown-hook.log
