output "summary" {
  value = {
    suffix     = local.suffix
    networking = module.networking
    shared     = module.shared
    cluster    = module.cluster.summary
    kubernetes = module.kubernetes
  }
}
