output "resource_group" {
  value = {
    name = azurerm_resource_group.networking_rg.name
    id   = azurerm_resource_group.networking_rg.id
  }
}

output "virtual_network" {
  value = {
    name          = azurerm_virtual_network.vnet.name
    id            = azurerm_virtual_network.vnet.id
    address_space = azurerm_virtual_network.vnet.address_space
  }
}

output "subnets" {
  value = {
    aks_nodes = {
      name             = azurerm_subnet.aks_nodes.name
      id               = azurerm_subnet.aks_nodes.id
      address_prefixes = azurerm_subnet.aks_nodes.address_prefixes
    }
    firewall = {
      name             = azurerm_subnet.firewall.name
      id               = azurerm_subnet.firewall.id
      address_prefixes = azurerm_subnet.firewall.address_prefixes
    }
  }
}

output "public_ips" {
  value = {
    ingress = {
      name       = azurerm_public_ip.ingress.name
      id         = azurerm_public_ip.ingress.id
      ip_address = azurerm_public_ip.ingress.ip_address
    }
    egress = {
      name       = azurerm_public_ip.egress.name
      id         = azurerm_public_ip.egress.id
      ip_address = azurerm_public_ip.egress.ip_address
    }
  }
}
