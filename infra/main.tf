#############################################################################
# Demo AKS - Curso Arquitecto Azure
#
#   Resource Group
#   ├── Log Analytics Workspace   (observabilidad: Container Insights)
#   ├── Azure Container Registry  (imágenes privadas)
#   └── AKS
#       ├── node pool "system"   (solo add-ons críticos del cluster)
#       └── node pool "apps"     (cargas de trabajo, con autoscaler)
#
#   + Role assignment AcrPull: la identidad kubelet de AKS puede bajar
#     imágenes del ACR sin usuarios/contraseñas (Managed Identity).
#############################################################################

resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

locals {
  suffix = random_string.suffix.result
  name   = "${var.prefix}-${var.environment}-${local.suffix}"

  tags = merge({
    project     = "aks-store-demo"
    environment = var.environment
    managed_by  = "terraform"
    course      = "smartdata-az305"
  }, var.tags)
}

# ---------------------------------------------------------------------------
# Resource Group
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# Observabilidad
# ---------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${local.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# Azure Container Registry
# ---------------------------------------------------------------------------
resource "azurerm_container_registry" "this" {
  # El nombre del ACR es global (xxx.azurecr.io): solo alfanumérico, 5-50 chars.
  name                = "acr${var.prefix}${var.environment}${local.suffix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = var.acr_sku

  # Buena práctica: sin usuario admin. AKS se autentica con Managed Identity.
  admin_enabled = false

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Azure Kubernetes Service
# ---------------------------------------------------------------------------
resource "azurerm_kubernetes_cluster" "this" {
  name                = "aks-${local.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = "aks-${local.name}"
  kubernetes_version  = var.kubernetes_version

  # RG gestionado por Azure donde viven las VMSS, discos, IPs y el Load Balancer.
  node_resource_group = "rg-${local.name}-nodes"

  # Free = sin SLA financiero del control plane (ideal para demos).
  # Standard = SLA 99.95% con zonas. Premium = + soporte LTS.
  sku_tier = "Free"

  # Mantenimiento automático: parches de Kubernetes y de la imagen del nodo.
  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  # Base para Workload Identity (pods que acceden a Azure sin secretos).
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # --- Node pool de SISTEMA ---------------------------------------------
  default_node_pool {
    name       = "system"
    vm_size    = var.system_node_vm_size
    node_count = var.system_node_count

    # Taint CriticalAddonsOnly=true:NoSchedule -> las apps NO caen aquí.
    only_critical_addons_enabled = true

    # Necesario para poder cambiar propiedades del pool por defecto sin recrear el cluster.
    temporary_name_for_rotation = "systemtmp"

    upgrade_settings {
      max_surge                     = "10%"
      drain_timeout_in_minutes      = 0
      node_soak_duration_in_minutes = 0
    }

    tags = local.tags
  }

  # Identidad administrada del control plane (sin service principals ni secretos).
  identity {
    type = "SystemAssigned"
  }

  # --- Red ---------------------------------------------------------------
  # Azure CNI Overlay: los pods toman IPs de un rango privado (pod_cidr) que NO
  # consume IPs de la VNet -> escala a muchos pods sin planear subredes enormes.
  # Cilium (eBPF) como dataplane y motor de Network Policies.
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    load_balancer_sku   = "standard"
    pod_cidr            = "10.244.0.0/16"
    service_cidr        = "10.0.0.0/16"
    dns_service_ip      = "10.0.0.10"
  }

  # --- Monitoreo (Container Insights) ------------------------------------
  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.this.id
    msi_auth_for_monitoring_enabled = true
  }

  tags = local.tags

  lifecycle {
    # El canal de auto-upgrade cambia la versión por fuera de Terraform.
    ignore_changes = [kubernetes_version]
  }
}

# --- Node pool de USUARIO (aplicaciones) -----------------------------------
resource "azurerm_kubernetes_cluster_node_pool" "apps" {
  name                  = "apps"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.user_node_vm_size
  mode                  = "User"

  # Cluster Autoscaler: agrega/quita NODOS según pods pendientes.
  # (El HPA, en cambio, agrega/quita PODS según métricas.)
  auto_scaling_enabled = true
  min_count            = var.user_node_min_count
  max_count            = var.user_node_max_count

  node_labels = {
    "workload" = "apps"
  }

  upgrade_settings {
    max_surge                     = "10%"
    drain_timeout_in_minutes      = 0
    node_soak_duration_in_minutes = 0
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Integración AKS -> ACR
# La identidad "kubelet" (la que usan los nodos para hacer pull) recibe AcrPull.
# Equivalente a: az aks update --attach-acr <acr>
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                            = azurerm_container_registry.this.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}
