# ===============
#  Argo Executor
# ===============
# Agent pods run with automountServiceAccountToken: false (ADR-003). Argo then requires
# `executor.serviceAccountName` and mounts that ServiceAccount's token into the executor
# containers (init, wait) only - not main. Source: argo-workflows workflow/controller/workflowpod.go
#
# Token Secret is NOT created here: Argo reads a Secret named `argo-executor.service-account-token`,
# a legacy non-expiring token. Created by kubectl after apply so the token never lands in
# Terraform state - see README.

resource "kubernetes_service_account_v1" "argo_executor" {
  metadata {
    name      = "argo-executor"
    namespace = kubernetes_namespace_v1.ns["agents"].metadata[0].name
  }

  automount_service_account_token = false
}

# Minimum for the executor to report step results
# https://argo-workflows.readthedocs.io/en/latest/workflow-rbac/
resource "kubernetes_role_v1" "argo_executor" {
  metadata {
    name      = "argo-executor"
    namespace = kubernetes_namespace_v1.ns["agents"].metadata[0].name
  }

  rule {
    api_groups = ["argoproj.io"]
    resources  = ["workflowtaskresults"]
    verbs      = ["create", "patch"]
  }
}

resource "kubernetes_role_binding_v1" "argo_executor" {
  metadata {
    name      = "argo-executor"
    namespace = kubernetes_namespace_v1.ns["agents"].metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.argo_executor.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.argo_executor.metadata[0].name
    namespace = kubernetes_namespace_v1.ns["agents"].metadata[0].name
  }
}
