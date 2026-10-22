output "namespaces" {
  value = [for ns in kubernetes_namespace_v1.ns : ns.metadata[0].name]
}

output "service_accounts" {
  value = {
    platform = [for sa in kubernetes_service_account_v1.platform : "${sa.metadata[0].namespace}/${sa.metadata[0].name}"]
    agents   = [for sa in kubernetes_service_account_v1.agents : "${sa.metadata[0].namespace}/${sa.metadata[0].name}"]
    executor = "${kubernetes_service_account_v1.argo_executor.metadata[0].namespace}/${kubernetes_service_account_v1.argo_executor.metadata[0].name}"
  }
}
