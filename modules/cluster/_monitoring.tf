# ====================
#  Container Insights
# ====================
# With managed identity auth, Terraform must create the data collection rule and association itself.
# Shape follows Microsoft's onboarding sample:
# https://github.com/microsoft/Docker-Provider/tree/ci_prod/scripts/onboarding/aks/onboarding-msi-terraform

locals {
  # Logs/events preset: omit historical performance and extra inventory tables for the POC.
  container_insights_streams = [
    "Microsoft-ContainerLogV2",
    "Microsoft-KubeEvents",
    "Microsoft-KubePodInventory",
  ]
}

# Must be in the Log Analytics workspace region, not the cluster region.
# Keep in sync with modules/shared/log-analytics.tf
resource "azurerm_monitor_data_collection_rule" "container_insights" {
  name                = "MSCI-northeurope-${azurerm_kubernetes_cluster.aks.name}" # naming convention used by AKS itself
  resource_group_name = azurerm_resource_group.cluster_rg.name
  location            = "northeurope"
  description         = "POC logs and events; pod inventory every five minutes"
  tags                = var.tags

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace_id
      name                  = "ciworkspace"
    }
  }

  data_flow {
    streams      = local.container_insights_streams
    destinations = ["ciworkspace"]
  }

  # Namespace filtering here covers events/inventory, not stdout/stderr; see kubernetes/_monitoring.tf.
  data_sources {
    extension {
      name           = "ContainerInsightsExtension"
      extension_name = "ContainerInsights"
      streams        = local.container_insights_streams
      extension_json = jsonencode({
        dataCollectionSettings = {
          interval               = "5m"
          namespaceFilteringMode = "Include"
          namespaces             = [var.platform_namespace, var.argo_namespace, var.github_broker_namespace, "agents"]
          enableContainerLogV2   = true
        }
      })
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "container_insights" {
  name                    = "ContainerInsightsExtension"
  target_resource_id      = azurerm_kubernetes_cluster.aks.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.container_insights.id
  description             = "Association of container insights data collection rule. Deleting this association will break the data collection for this AKS Cluster."
}
