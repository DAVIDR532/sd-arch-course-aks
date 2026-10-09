terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Para el demo usamos estado LOCAL (terraform.tfstate en esta carpeta).
  # En un proyecto real el estado vive en un Storage Account con bloqueo:
  #
  # backend "azurerm" {
  #   resource_group_name  = "rg-tfstate"
  #   storage_account_name = "sttfstatexxxx"
  #   container_name       = "tfstate"
  #   key                  = "aks-demo.tfstate"
  # }
}

provider "azurerm" {
  features {
    resource_group {
      # AKS / Container Insights crean recursos auxiliares dentro del RG.
      # Lo desactivamos para que `terraform destroy` limpie todo sin errores.
      prevent_deletion_if_contains_resources = false
    }
  }

  subscription_id = var.subscription_id
}
