# ====================
#  Monitor Collection
# ====================
# The DCR namespace filter does not apply to container stdout/stderr.
# Filter system logs at the agent before upload; both stdout and stderr remain useful for agent runs.

locals {
  monitor_excluded_log_namespaces = [
    "kube-system",
    "gatekeeper-system",
    "azure-arc",
    "kube-public",
    "kube-node-lease",
    "calico-system",
    "default",
  ]
}

resource "kubernetes_config_map_v1" "monitor_agent" {
  metadata {
    name      = "container-azm-ms-agentconfig"
    namespace = "kube-system"
  }

  data = {
    "schema-version"               = "v1"
    "config-version"               = "poc-v1"
    "log-data-collection-settings" = <<-TOML
      [log_collection_settings]
        [log_collection_settings.stdout]
          enabled = true
          exclude_namespaces = ${jsonencode(local.monitor_excluded_log_namespaces)}
        [log_collection_settings.stderr]
          enabled = true
          exclude_namespaces = ${jsonencode(local.monitor_excluded_log_namespaces)}
        [log_collection_settings.env_var]
          enabled = false
        [log_collection_settings.collect_all_kube_events]
          enabled = false
        [log_collection_settings.schema]
          containerlog_schema_version = "v2"
    TOML
  }
}
