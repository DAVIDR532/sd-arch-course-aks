output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "node_resource_group" {
  description = "RG administrado por AKS (VMSS, discos, Load Balancer, IPs públicas)."
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "aks_kubernetes_version" {
  value = azurerm_kubernetes_cluster.this.current_kubernetes_version
}

output "acr_name" {
  value = azurerm_container_registry.this.name
}

output "acr_login_server" {
  value = azurerm_container_registry.this.login_server
}

output "oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "get_credentials_command" {
  description = "Comando para configurar kubectl contra el cluster."
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.this.name} --name ${azurerm_kubernetes_cluster.this.name} --overwrite-existing"
}
