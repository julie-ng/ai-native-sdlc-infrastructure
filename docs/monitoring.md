# Monitoring costs

Container Insights sends to Log Analytics in North Europe. The settings below keep the POC cheap.

| Control | POC setting |
|---|---|
| Workspace retention | 30 days; no extended retention configured |
| Daily ingestion cap | 0.1 GB/day (about 100 MB), workspace-wide |
| Collected tables | `ContainerLogV2`, `KubeEvents`, `KubePodInventory` |
| Pod inventory | Every 5 minutes, for `platform`, `argo`, `github-broker`, `agents` |
| Kubernetes events | Non-Normal events in those four namespaces; event-driven |
| Container logs | stdout and stderr; exclude `kube-system`, `gatekeeper-system`, `azure-arc`, `kube-public`, `kube-node-lease`, `calico-system`, `default` at the agent |

The [logs/events preset](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/kubernetes-monitoring-enable#configuration-options) keeps troubleshooting data without ingesting `Perf`, `InsightsMetrics`, or the extra inventory tables. Inventory is sampled more slowly; this does not throttle container logs or events. Historical CPU/memory charts and full Container Insights visualizations are not provided by this configuration. No Managed Prometheus, Grafana, syslog, or AKS audit/control-plane log export is enabled by this repo.

[Retention below 31 days does not reduce Analytics ingestion charges](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/data-retention-configure). The [daily cap](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/daily-cap) is a backstop, not a hard spending limit: overshoot is billable, and collection stops until the workspace reset. 0.1 GB/day is an initial POC choice, not a measured workload requirement. Logs lost during a cap-related collection gap are not guaranteed to be recoverable.

## Apply order

- Apply the workspace cap with `make plan-shared` / `make apply` before the cluster stage.
- Apply `module.kubernetes` immediately after the cluster stage and before deploying workloads: it installs the [monitor agent ConfigMap](https://github.com/microsoft/Docker-Provider/blob/ci_prod/kubernetes/container-azm-ms-agentconfig.yaml). Until then, agent defaults apply.
- The DCR namespace filter covers events/inventory; the ConfigMap separately excludes container logs before upload. Container log filtering is an exclusion list, so review it when adding namespaces.
- App and agent log verbosity still determines volume; avoid debug output and request-body logging by default.
