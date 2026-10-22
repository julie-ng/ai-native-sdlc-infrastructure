# Address migration only; changing an existing identity resource group still requires replacement.

moved {
  from = module.cluster.azurerm_user_assigned_identity.control_plane_mi
  to   = module.identities.azurerm_user_assigned_identity.control_plane_mi
}

moved {
  from = module.cluster.azurerm_user_assigned_identity.kubelet_mi
  to   = module.identities.azurerm_user_assigned_identity.kubelet_mi
}

moved {
  from = module.cluster.azurerm_user_assigned_identity.workloads
  to   = module.identities.azurerm_user_assigned_identity.workloads
}

moved {
  from = module.cluster.azurerm_role_assignment.control_plane_on_kubelet_mi
  to   = module.identities.azurerm_role_assignment.control_plane_on_kubelet_mi
}

moved {
  from = module.cluster.azurerm_role_assignment.control_plane_on_nodes_subnet
  to   = module.identities.azurerm_role_assignment.control_plane_on_nodes_subnet
}

moved {
  from = module.cluster.azurerm_role_assignment.control_plane_on_egress_ip
  to   = module.identities.azurerm_role_assignment.control_plane_on_egress_ip
}

moved {
  from = module.cluster.azurerm_role_assignment.kubelet_acr_pull
  to   = module.identities.azurerm_role_assignment.kubelet_acr_pull
}

moved {
  from = module.cluster.azurerm_role_assignment.artifact_service_on_blob
  to   = module.identities.azurerm_role_assignment.artifact_service_on_blob
}

moved {
  from = module.cluster.azurerm_role_assignment.artifact_service_delegator
  to   = module.identities.azurerm_role_assignment.artifact_service_delegator
}

moved {
  from = module.cluster.azurerm_role_assignment.argo_controller_on_blob
  to   = module.identities.azurerm_role_assignment.argo_controller_on_blob
}

moved {
  from = module.cluster.azurerm_role_assignment.argo_server_on_blob
  to   = module.identities.azurerm_role_assignment.argo_server_on_blob
}

moved {
  from = module.cluster.azurerm_role_assignment.token_broker_on_kv
  to   = module.identities.azurerm_role_assignment.token_broker_on_kv
}
