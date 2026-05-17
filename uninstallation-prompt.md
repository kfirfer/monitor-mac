Please read @README.md and @README-vector.md and uninstall the monitoring tools such as influxdb, grafana, and vector.

This includes:
- Stop and remove the Docker containers (influxdb, grafana) via `docker compose down -v` and remove related volumes/data.
- Unload and remove all LaunchAgents: `com.vector.metrics.plist`, `com.monitor.shutdown.plist`, `com.monitor.prune.plist`, `com.monitor.health.plist` (use `launchctl unload` / `launchctl bootout` then delete the symlinks from `~/Library/LaunchAgents/`).
- Uninstall Vector via Homebrew (`brew uninstall vector` and optionally `brew untap vectordotdev/brew`).
- Remove leftover log files in `/tmp/` (e.g. `vector.err`, `shutdown-hook.log`, `parquet-prune.log`, `health-check.log`).
- Confirm ports 8334 and 3046 are no longer listening and no related processes remain.

Validate with playwright that http://localhost:3046 is no longer reachable (Grafana is fully down).

Thank you. Good luck.
