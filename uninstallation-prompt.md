Please read @README.md and @README-vector.md and uninstall the monitoring tools such as influxdb, grafana, and vector.

This includes:
- Unload all LaunchAgents and remove their symlinks from `~/Library/LaunchAgents/`:
  - `com.vector.metrics.plist` — `launchctl unload`
  - `com.monitor.health.plist` — `launchctl unload`
  - `com.monitor.shutdown.plist` — `launchctl bootout gui/$(id -u)`
  - `com.monitor.prune.plist` — `launchctl bootout gui/$(id -u)`
- Stop and remove the Docker containers and their data: `docker compose down -v` (this removes the `monitor-mac_influxdb3-data` volume so InfluxDB time-series data is wiped).
- Uninstall Vector: `brew uninstall vector` and optionally `brew untap vectordotdev/brew`.
- Remove leftover log files in `/tmp/`: `vector.log`, `vector.err`, `shutdown-hook.log`, `parquet-prune.log`, `health-check.log`.
- Verify nothing remains: `launchctl list | grep -E 'vector|monitor'` returns nothing, `docker compose ps` is empty, and ports 8334 and 3046 are no longer listening.

Validate with playwright that http://localhost:3046 is no longer reachable (Grafana is fully down).

Thank you. Good luck.
