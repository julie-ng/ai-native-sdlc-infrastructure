output "summary" {
  value = {
    suffix     = local.suffix
    networking = module.networking
    shared     = module.shared
    identities = module.identities
    cluster    = module.cluster.summary
    kubernetes = module.kubernetes
  }
}
