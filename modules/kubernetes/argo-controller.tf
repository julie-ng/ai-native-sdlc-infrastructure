# =================
#  Argo Controller
# =================
# The controller lives in argo but manages workflows only in agents.
# Helm creates no RBAC. Based on chart 2.0.16 controller rules, without PVCs,
# workflow PDBs, cluster templates or artifact credentials (unused in the POC).
# https://github.com/argoproj/argo-helm/blob/argo-workflows-2.0.16/charts/argo-workflows/templates/controller/workflow-controller-cluster-roles.yaml

resource "kubernetes_role_v1" "argo_controller" {
  metadata {
    name      = "argo-workflow-controller"
    namespace = kubernetes_namespace_v1.ns[var.agents_namespace].metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["create", "get", "list", "watch", "update", "patch", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/exec"]
    verbs      = ["create"]
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["argoproj.io"]
    resources  = ["workflows", "workflows/finalizers", "workflowtasksets", "workflowtasksets/finalizers", "workflowtasksets/status", "workflowartifactgctasks", "cronworkflows", "cronworkflows/finalizers"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["argoproj.io"]
    resources  = ["workflowtemplates", "workflowtemplates/finalizers"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["argoproj.io"]
    resources  = ["workflowtaskresults", "workflowtaskresults/finalizers"]
    verbs      = ["list", "watch", "deletecollection"]
  }

  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["serviceaccounts"]
    verbs      = ["get", "list"]
  }

  # Argo resolves this legacy token Secret by convention; never read its value in Terraform.
  rule {
    api_groups     = [""]
    resources      = ["secrets"]
    resource_names = ["${kubernetes_service_account_v1.argo_executor.metadata[0].name}.service-account-token"]
    verbs          = ["get"]
  }
}

resource "kubernetes_role_binding_v1" "argo_controller" {
  metadata {
    name      = "argo-workflow-controller"
    namespace = kubernetes_namespace_v1.ns[var.agents_namespace].metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.argo_controller.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.platform["${var.argo_namespace}/argo-workflow-controller"].metadata[0].name
    namespace = kubernetes_namespace_v1.ns[var.argo_namespace].metadata[0].name
  }
}

# Configuration is in the controller namespace, separate from workflow resources.
resource "kubernetes_role_v1" "argo_controller_config" {
  metadata {
    name      = "argo-workflow-controller-config"
    namespace = kubernetes_namespace_v1.ns[var.argo_namespace].metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_role_binding_v1" "argo_controller_config" {
  metadata {
    name      = "argo-workflow-controller-config"
    namespace = kubernetes_namespace_v1.ns[var.argo_namespace].metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.argo_controller_config.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.platform["${var.argo_namespace}/argo-workflow-controller"].metadata[0].name
    namespace = kubernetes_namespace_v1.ns[var.argo_namespace].metadata[0].name
  }
}
