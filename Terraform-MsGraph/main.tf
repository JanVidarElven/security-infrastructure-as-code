// Main Input Variabules for Deployment
// TODO: Change these to match your environment
variable "environment" { default = "Dev" }
variable "applicationName" { default = "NIC Rebel Edition 2025" }
variable "customerName" { default = "Elven" }
variable "location" { default = "Norway East" }
variable "deploymentType" { default = "TerraformGraph" }

// Resource Tags for all resources deployed with this Bicep file
// TODO: Change these to match your environment
locals {
  defaultTags = {
    Dataclassification = "Open"
    Criticality        = "Normal"
    Costcenter         = "Operations"
    Owner              = "Jan Vidar Elven"
  }
}

// Resource Group for the deployment
resource "azurerm_resource_group" "rg" {
  name     = "rg-${lower(var.customerName)}-${lower(replace(var.applicationName, " ", ""))}-${lower(var.deploymentType)}"
  location = var.location
  tags = merge(local.defaultTags, {
    Environment    = "${var.environment}"
    Application    = "${var.applicationName}-${var.environment}"
    Service        = "${var.customerName} ${var.applicationName}"
    Business       = "${var.customerName}"
    Deploymenttype = "${var.deploymentType}"
  })
}

// Using AVM module for User Assigned Managed Identity
module "userAssignedIdentity" {
  source           = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version          = "~> 0.3"
  enable_telemetry = false

  location            = azurerm_resource_group.rg.location
  name                = "mi-${lower(replace(var.applicationName, " ", ""))}-${lower(var.deploymentType)}"
  resource_group_name = azurerm_resource_group.rg.name

  tags = merge(local.defaultTags, {
    Environment    = "${var.environment}"
    Application    = "${var.applicationName}-${var.environment}"
    Service        = "${var.customerName} ${var.applicationName}"
    Business       = "${var.customerName}"
    Deploymenttype = "${var.deploymentType}"
  })
}

locals {
  MicrosoftGraphAppId = "00000003-0000-0000-c000-000000000000"
}

// Get the Resource Id of the Graph resource in the tenant
data "msgraph_resource" "servicePrincipal_msgraph" {
  url = "servicePrincipals"
  query_parameters = {
    "$filter" = ["appId eq '${local.MicrosoftGraphAppId}'"]
  }
  response_export_values = {
    all = "@"
  }
}

// Get the Service Principal Id of the User Managed Identity resource
data "msgraph_resource" "servicePrincipal_userAssignedIdentity" {
  url = "servicePrincipals"
  query_parameters = {
    "$filter" = ["appId eq '${module.userAssignedIdentity.client_id}'"]
  }
  response_export_values = {
    all = "@"
  }
}


// Define the App Roles to assign to the Managed Identity
variable "appRoles" {
  type = list(string)
  default = [
    "User.Read.All",
    "Device.Read.All"
  ]
}

locals {
  appRoles = toset(var.appRoles)
  appRoleIds = { for role in data.msgraph_resource.servicePrincipal_msgraph.output.all.value[0].appRoles : role.value => role.id }
}

// Looping through the App Roles and assigning them to the Managed Identity
resource "msgraph_resource" "appRoleAssignment" {
  for_each = local.appRoles
  url = "servicePrincipals/${data.msgraph_resource.servicePrincipal_msgraph.output.all.value[0].id}/appRoleAssignments"
  body = {
    appRoleId   = local.appRoleIds[each.value]
    principalId = data.msgraph_resource.servicePrincipal_userAssignedIdentity.output.all.value[0].id
    resourceId  = data.msgraph_resource.servicePrincipal_msgraph.output.all.value[0].id
  }
}

// Using AVM module for Logic App Workflow
module "avm-res-logic-workflow" {
  source           = "Azure/avm-res-logic-workflow/azurerm"
  version          = "~> 0.1.2"
  enable_telemetry = false

  location            = azurerm_resource_group.rg.location
  name                = "logicapp-${lower(replace(var.applicationName, " ", ""))}-${lower(var.deploymentType)}"
  resource_group_id   = azurerm_resource_group.rg.id
  resource_group_name = azurerm_resource_group.rg.name

  managed_identities = {
    system_assigned            = false
    user_assigned_resource_ids = [module.userAssignedIdentity.resource_id]
  }

  logic_app_definition = {
    "$schema" : "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
    "contentVersion" : "1.0.0.0",
    "triggers" : {
      "request" : {
        "type" : "Request",
        "kind" : "Http",
        "inputs" : {
          "schema" : {}
        }
      }
    },
    "actions" : {
      "HTTP" : {
        "type" : "Http",
        "inputs" : {
          "uri" : "https://graph.microsoft.com/v1.0/users/$count?$filter=userType%20ne%20'guest'",
          "method" : "GET",
          "headers" : {
            "consistencyLevel" : "eventual"
          },
          "authentication" : {
            "type" : "ManagedServiceIdentity",
            "identity" : module.userAssignedIdentity.resource_id,
            "audience" : "https://graph.microsoft.com"
          }
        },
        "runAfter" : {}
      },
      "Response" : {
        "type" : "Response",
        "inputs" : {
          "statusCode" : 200,
          "body" : "@body('HTTP')"
        },
        "runAfter" : {
          "HTTP" : [
            "Succeeded"
          ]
        }
      }
    },
    "parameters" : {
      "$connections" : {
        "type" : "Object",
        "defaultValue" : {}
      }
    }
  }

  tags = merge(local.defaultTags, {
    Environment    = "${var.environment}"
    Application    = "${var.applicationName}-${var.environment}"
    Service        = "${var.customerName} ${var.applicationName}"
    Business       = "${var.customerName}"
    Deploymenttype = "${var.deploymentType}"
  })
}