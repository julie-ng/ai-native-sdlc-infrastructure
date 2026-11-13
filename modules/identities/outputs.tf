output "resource_group" {
  value = {
    name = azurerm_resource_group.identities_rg.name
    id   = azurerm_resource_group.identities_rg.id
  }
}

output "control_plane" {
  value = {
    id           = azurerm_user_assigned_identity.control_plane_mi.id
    name         = azurerm_user_assigned_identity.control_plane_mi.name
    client_id    = azurerm_user_assigned_identity.control_plane_mi.client_id
    principal_id = azurerm_user_assigned_identity.control_plane_mi.principal_id
  }

  # The cluster needs these grants, not just an existing principal.
  depends_on = [
    azurerm_role_assignment.control_plane_on_kubelet_mi,
    azurerm_role_assignment.control_plane_on_nodes_subnet,
    azurerm_role_assignment.control_plane_on_egress_ip,
  ]
}

output "kubelet" {
  value = {
    id           = azurerm_user_assigned_identity.kubelet_mi.id
    name         = azurerm_user_assigned_identity.kubelet_mi.name
    client_id    = azurerm_user_assigned_identity.kubelet_mi.client_id
    principal_id = azurerm_user_assigned_identity.kubelet_mi.principal_id
  }

  # Nodes must be able to pull images when the cluster starts.
  depends_on = [azurerm_role_assignment.kubelet_acr_pull]
}

output "workloads" {
  value = {
    for k, mi in azurerm_user_assigned_identity.workloads : k => {
      id           = mi.id
      name         = mi.name
      client_id    = mi.client_id
      principal_id = mi.principal_id
    }
  }
}
output "github_agent_images_acr_push" {
  value = {
    id           = azurerm_user_assigned_identity.github_agent_images_mi.id
    name         = azurerm_user_assigned_identity.github_agent_images_mi.name
    client_id    = azurerm_user_assigned_identity.github_agent_images_mi.client_id
    principal_id = azurerm_user_assigned_identity.github_agent_images_mi.principal_id
  }

  # Nodes must be able to pull images when the cluster starts.
  depends_on = [azurerm_role_assignment.github_agent_images_acr_push]
}

output "github_platform_services_acr_push" {
  value = {
    id           = azurerm_user_assigned_identity.github_platform_services_mi.id
    name         = azurerm_user_assigned_identity.github_platform_services_mi.name
    client_id    = azurerm_user_assigned_identity.github_platform_services_mi.client_id
    principal_id = azurerm_user_assigned_identity.github_platform_services_mi.principal_id
  }

  # Nodes must be able to pull images when the cluster starts.
  depends_on = [azurerm_role_assignment.github_platform_services_acr_push]
}

output "github_broker_acr_push" {
  value = {
    id           = azurerm_user_assigned_identity.github_broker_mi.id
    name         = azurerm_user_assigned_identity.github_broker_mi.name
    client_id    = azurerm_user_assigned_identity.github_broker_mi.client_id
    principal_id = azurerm_user_assigned_identity.github_broker_mi.principal_id
  }

  # Export only after the workflow identity has its push grant.
  depends_on = [azurerm_role_assignment.github_broker_acr_push]
}
