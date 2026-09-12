terraform {
  required_version = ">= 1.6"

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

  # State remoto no Azure Storage. O container é criado uma única vez pelo
  # scripts/bootstrap-state.sh antes do primeiro terraform init.
  backend "azurerm" {
    resource_group_name  = "pos-tech-fiap"
    storage_account_name = "postechtfstate13soat"
    container_name       = "tfstate"
    key                  = "infra-db.tfstate"
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}
