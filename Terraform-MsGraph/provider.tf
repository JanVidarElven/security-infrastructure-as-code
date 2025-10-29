terraform {
  required_version = ">= 1.9"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.5"
    }
    msgraph = {
      source  = "microsoft/msgraph"
      version = "~> 0.2"
    }
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = "~> 1.11"
    }
  }
}

locals {
  ado_orgname = "TheGotoGuy"
}
variable "subscription_id" {
  sensitive = true
}
variable "tenant_id" {
  sensitive = true
}

provider "azurerm" {
  features {
    virtual_machine {
      delete_os_disk_on_deletion = true
    }
  }
  subscription_id = var.subscription_id
}

provider "msgraph" {
  tenant_id = var.tenant_id
}

variable "devops_entra_token" {
  sensitive   = true
  description = "Microsoft Entra token to access Azure DevOps"
}
# $env:TF_VAR_devops_entra_token = az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query "accessToken" -o tsv

provider "azuredevops" {
  org_service_url = "https://dev.azure.com/${local.ado_orgname}"

  personal_access_token = var.devops_entra_token
}