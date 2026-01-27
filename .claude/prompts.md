Please write here 1 docker compose file that run 2 services: influxdb and grafana.
The grafana should connect to the influxdb service as a data source.
the login to grafana should be annonymous without any authentication.
grafana port should be mapped to 3046 and influxdb port should be mapped to 8334.
then run the docker compose after and check that everything is working fine using playwright mcp connecting to grafana.
Automatically leverage Context7 MCP for retrieving documentation, code examples, best practices, and external guidance when planning.
Use Perplexity Ask MCP automatically to search official documentation or authoritative sources whenever encountering unfamiliar tools or concepts.


Please install telegraf and ensure it is configured to send Mac OS metrics to influxdb.
The telegraf configurations should be documented at this folder.
Then use grafana to visualize the Mac OS metrics collected by telegraf by using playwright mcp.
Read @docker-compose.yml for influxdb and grafana details.
Automatically leverage Context7 MCP for retrieving documentation, code examples, best practices, and external guidance when planning.
Use Perplexity Ask MCP automatically to search official documentation or authoritative sources whenever encountering unfamiliar tools or concepts.

export the dashboard just created to a json file in grafana directory and make that it will be mounted successfully when running docker-compose.yml from scratch
Automatically leverage Context7 MCP for retrieving documentation, code examples, best practices, and external guidance when planning.
Use Perplexity Ask MCP automatically to search official documentation or authoritative sources whenever encountering unfamiliar tools or concepts.

I want the metrics will include CPU and Memory usage per process.
Please check if @telegraf.conf have the right configuration to collect Mac OS metrics and send them to influxdb.
Then use grafana to visualize the Mac OS metrics collected by telegraf by using playwright mcp.
Clone and Edit existing grafana dashboard named "macOS Metrics" to visualize CPU and Memory usage per process.
After finish editing the new edited grafana dashboard, export it to a json file in grafana directory and make sure that it will be mounted successfully when running docker-compose.yml from scratch.
Automatically leverage Context7 MCP for retrieving documentation, code examples, best practices, and external guidance when planning.
Use Perplexity Ask MCP automatically to search official documentation or authoritative sources whenever encountering unfamiliar tools or concepts.




At grafana dashboard "macOS Metrics" at the panel "CPU Usage per Process (Top 10)" I can see this issue:
max series limit exceeded (count is 1001)
and also I can see that its including everything including cmdline etc..  I want only process name visually at the table.
and change from top 10 to top 200 and the table sort will be based on the latest cpu usage or memory usage.
Use playwright mcp to use grafana.
Clone and Edit existing grafana dashboard named "macOS Metrics" to apply the changes.
After finish editing the new edited grafana dashboard, export it to a json file in grafana directory and make sure that it will be mounted successfully when running docker-compose.yml from scratch.
Automatically leverage Context7 MCP for retrieving documentation, code examples, best practices, and external guidance when planning.
Use Perplexity Ask MCP automatically to search official documentation or authoritative sources whenever encountering unfamiliar tools or concepts.



At grafana dashboard "macOS Metrics" at the panel "CPU Usage per Process (Top 10)" and the memory top per process I can see this issue:
max series limit exceeded (count is 1001)
and also I can see that its including everything including cmdline etc..  I want only process name visually at the table.
and change from top 10 to top 500 and the table sort will be based on the latest cpu usage or memory usage.
change the dashboard json directly to apply these changes at @grafana/dashboards/macos-metrics.json, then restart grafana service to refresh the dashboard with the new changes.
And then go to grafana using playwright mcp and validate that the changes working good at the grafana dashboard visually.
Automatically leverage Context7 MCP for retrieving documentation, code examples, best practices, and external guidance when planning.
Use Perplexity Ask MCP automatically to search official documentation or authoritative sources whenever encountering unfamiliar tools or concepts.


Configure data at influxdb is persistent only for 7 days. after 7 days the data should be deleted automatically.
Influxdb setup at @docker-compose.yml file.
Automatically leverage Context7 MCP for retrieving documentation, code examples, best practices, and external guidance when planning.
Use Perplexity Ask MCP automatically to search official documentation or authoritative sources whenever encountering unfamiliar tools or concepts.



At grafana dashboard "macOS Metrics" at the panel "CPU Usage per Process Over Time" and "Memory Usage per Process Over Time" duplicate them and change process name to cmdline.
change the dashboard json directly to apply these changes at @grafana/dashboards/macos-metrics.json, then restart grafana service to refresh the dashboard with the new changes.
And then go to grafana using playwright mcp and validate that the changes working good at the grafana dashboard visually.
Automatically leverage Context7 MCP for retrieving documentation, code examples, best practices, and external guidance when planning.
Use Perplexity Ask MCP automatically to search official documentation or authoritative sources whenever encountering unfamiliar tools or concepts.



Please install `vector.dev` as a replacement for telegraf to collect Mac OS metrics and send them to influxdb.
disable telegraf and make sure it will not run when starting when starting Mac OS.
And make sure vector.dev collecting per process CPU and Memory usage and sending them to influxdb.
The vector configurations should be documented at this folder.
Then change the grafana dashboard json directly and relevant panels and apply these changes at @grafana/dashboards/macos-metrics.json, then restart grafana service to refresh the dashboard with the new changes.
Automatically leverage Context7 MCP for retrieving documentation, code examples, best practices, and external guidance when planning.
Use Perplexity Ask MCP automatically to search official documentation or authoritative sources whenever encountering unfamiliar tools or concepts.




Each time the vector.dev writing metrics to influxdb, influxdb spikes cpu usage to around 10%.
Please check how influxdb can be optimized to reduce cpu usage when writing metrics from vector.dev.
Automatically leverage Context7 MCP for retrieving documentation, code examples, best practices, and external guidance when planning.
Use Perplexity Ask MCP automatically to search official documentation or authoritative sources whenever encountering unfamiliar tools or concepts.

---

Please change the grafana dashboard panels "CPU Usage per Process Over Time (by PID)" and "Memory Usage per Process Over Time (by PID)" not to be by PID. but only by name.
And aggregate the cpu and memory usage per process name. since there are lots of PID for the same process name.
change the dashboard json directly to apply these changes at @grafana/dashboards/macos-metrics.json, then restart grafana service to refresh the dashboard with the new changes.
And then go to grafana using playwright mcp and validate that the changes working good at the grafana dashboard visually.
Automatically leverage Context7 MCP for retrieving documentation, code examples, best practices, and external guidance when planning.
Use Perplexity Ask MCP automatically to search official documentation or authoritative sources whenever encountering unfamiliar tools or concepts.

at grafana dashboard panel "CPU Usage" i want it to be line graph instead of points graph, similar as "Memory Usage" panel.
and also aggregate all the cpu cores into one , i dont like its shows per core.
change the dashboard json directly to apply these changes at @grafana/dashboards/macos-metrics.json, then restart grafana service to refresh the dashboard with the new changes.
And then go to grafana using playwright mcp and validate that the changes working good at the grafana dashboard visually.
Automatically leverage Context7 MCP for retrieving documentation, code examples, best practices, and external guidance when planning.
Use Perplexity Ask MCP automatically to search official documentation or authoritative sources whenever encountering unfamiliar tools or concepts.

When see "CPU Usage per Process Over Time" for the last 3 hours, i can see "env" is in the top 1 when order by "Mean".
But it had only slightly for few second spike and thats all, he consumes almost no CPU at all if we go through all the 3 hours.
There are many more processes that consumes more CPU but they are not in the top when order by "Mean".
Please change the query to be more accurate and reflect the real CPU consumption per process over time.

At "Disk Usage" graph, shows only device, filesystem , and mountpoint values. 
currently its shows :
value {collector="filesystem", device="/dev/disk3s1s1", filesystem="apfs", host="dev345-MacBook-Pro-2.local", metric_type="gauge", mountpoint="/"}
I want i will shows only:
device="/dev/disk3s1s1" - filesystem="apfs" - mountpoint="/"


❯ I have some issue with the dashboard or metrics.. i get to see "prl_vm_app" at the panel "CPU Usage per Process Over Time" and "Memory Usage per Process Over Time"..  but i want to see the name of the process such as the image:   please check with perplexity mcp what can be         
done and change accordingely.   

