variable "subscription_id" {
  description = "ID de la suscripción de Azure donde se despliega el demo."
  type        = string
}

variable "location" {
  description = "Región de Azure."
  type        = string
  default     = "eastus2"
}

variable "prefix" {
  description = "Prefijo corto (solo minúsculas y números) usado en el nombre de todos los recursos."
  type        = string
  default     = "sdaks"

  validation {
    condition     = can(regex("^[a-z0-9]{3,10}$", var.prefix))
    error_message = "El prefijo debe tener entre 3 y 10 caracteres, solo minúsculas y números (el ACR no admite guiones)."
  }
}

variable "environment" {
  description = "Nombre del ambiente (dev, demo, prod...)."
  type        = string
  default     = "demo"
}

# ---------------------------------------------------------------------------
# AKS
# ---------------------------------------------------------------------------
variable "kubernetes_version" {
  description = "Versión de Kubernetes. null = la versión por defecto que ofrece AKS en la región."
  type        = string
  default     = null
}

variable "system_node_vm_size" {
  description = "Tamaño de VM del node pool de SISTEMA (CoreDNS, metrics-server, agentes...)."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "system_node_count" {
  description = "Número de nodos del pool de sistema. En producción se recomiendan 3 (uno por zona)."
  type        = number
  default     = 1
}

variable "user_node_vm_size" {
  description = "Tamaño de VM del node pool de USUARIO (donde corren las aplicaciones)."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "user_node_min_count" {
  description = "Mínimo de nodos del pool de aplicaciones (cluster autoscaler)."
  type        = number
  default     = 1
}

variable "user_node_max_count" {
  description = "Máximo de nodos del pool de aplicaciones (cluster autoscaler)."
  type        = number
  default     = 3
}

# ---------------------------------------------------------------------------
# ACR
# ---------------------------------------------------------------------------
variable "acr_sku" {
  description = "SKU del Azure Container Registry: Basic, Standard o Premium (Premium = geo-replicación y Private Link)."
  type        = string
  default     = "Standard"
}

variable "tags" {
  description = "Tags adicionales para todos los recursos."
  type        = map(string)
  default     = {}
}
