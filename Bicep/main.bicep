
// Main Bicep deployment file for Azure and Graph resources
// Topic: NIC Rebel Edition 2025
// Created by: Jan Vidar Elven
// Last Updated: 28.10.2025

targetScope = 'subscription'

// Main Parameters for Deployment
// TODO: Change these to match your environment
param environment string = 'Dev'
param applicationName string = 'NIC Rebel Edition 2025'
param customerName string = 'Elven'
param location string = 'norwayeast'
param deploymentType string = 'Bicep'
param resourceGroupName string = 'rg-${toLower(customerName)}-${toLower(replace(applicationName,' ',''))}-${toLower(deploymentType)}'

// Resource Tags for all resources deployed with this Bicep file
// TODO: Change these to match your environment
var defaultTags = {
  Environment: environment
  Application: '${applicationName}-${environment}'
  Dataclassification: 'Open'
  Costcenter: 'Operations'
  Criticality: 'Normal'
  Service: '${customerName} ${applicationName}'
  Deploymenttype: deploymentType
  Owner: 'Jan Vidar Elven'
  Business: customerName
}

// Parameters for Workload Identity Federation (WIF)
// TODO: Change these for your environment
@description('Tenant ID where the Workload Identity Federation (WIF) is created.')
param tenantId string = deployer().tenantId // Defaults to the tenant of the deployer, or override
@description('Subject of the GitHub Actions workflow\'s federated identity credentials (FIC) that is checked before issuing an Entra ID access token to access Azure resources. GitHub Actions subject examples can be found in https://docs.github.com/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect#example-subject-claims')
param githubActionsFicSubject string = 'repo:JanVidarElven/security-infrastructure-as-code:ref:refs/heads/main'
@description('This federation subject identifier is automatically created for this Service connection. Azure DevOps guarantees only this service connection will use that identity globally.')
param adoServiceConnectionFicSubject string = '<Unique Service Connection Identifier from Azure DevOps Service Connection>'

// Build the issuer URL for Azure DevOps Service Connection FIC
var adoServiceConnectionFicIssuer string = 'https://login.microsoftonline.com/${tenantId}/v2.0'

// Resource Group for the deployment
resource rg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroupName
  location: location
  tags: defaultTags
}

// Using AVM module for User Assigned Managed Identity
module userAssignedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.0' = {
  name: 'userAssignedIdentityDeployment'
  scope: resourceGroup(rg.name)  
  params: {
    // Required parameters
    name: 'mi-${toLower(replace(applicationName,' ',''))}-${toLower(deploymentType)}'
  }
}

// Initialize the Graph provider
extension microsoftGraphV1

// Get the Principal Id of the User Managed Identity resource
resource miSpn 'Microsoft.Graph/servicePrincipals@v1.0' existing = {
  appId: userAssignedIdentity.outputs.clientId

}

// Get the Resource Id of the Graph resource in the tenant
resource graphSpn 'Microsoft.Graph/servicePrincipals@v1.0' existing = {
  appId: '00000003-0000-0000-c000-000000000000'
}

// Define the App Roles to assign to the Managed Identity
param appRoles array = [
  'User.Read.All'
  'Device.Read.All'
]

// Looping through the App Roles and assigning them to the Managed Identity
resource assignAppRole 'Microsoft.Graph/appRoleAssignedTo@v1.0' = [for appRole in appRoles: {
  appRoleId: (filter(graphSpn.appRoles, role => role.value == appRole)[0]).id
  principalId: miSpn.id
  resourceId: graphSpn.id
}]

// Using AVM Module for Logic App Workflow
module logicApp 'br/public:avm/res/logic/workflow:0.4.0' = {
  name: 'logicAppDeployment'
  scope: resourceGroup(rg.name)
  params: {
    // Required parameters
    name: 'logicapp-${toLower(replace(applicationName,' ',''))}-${toLower(deploymentType)}'
    location: location
    managedIdentities: {
      userAssignedResourceIds: [
        userAssignedIdentity.outputs.resourceId
      ]
    }
    tags: defaultTags
    workflowTriggers: {
      request: {
        type: 'Request'
        kind: 'Http'
        inputs: {
          schema: {}
        }
      }
    }
    workflowActions: {
      HTTP: {
        type: 'Http'
        runAfter: {}
        inputs: {
          uri: 'https://graph.microsoft.com/v1.0/users/$count?$filter=userType%20ne%20\'guest\''
          method: 'GET'
          headers: {
            consistencyLevel: 'eventual'
          }
          authentication: {
            type: 'ManagedServiceIdentity'
            identity: userAssignedIdentity.outputs.resourceId
            audience: 'https://graph.microsoft.com'
          }
        }
      }
      Response: {
        runAfter: {
          HTTP: [
            'Succeeded'
          ]
        }
        type: 'Response'
        inputs: {
          statusCode: 200
          body: '@body(\'HTTP\')'
        }
      }        
    }    
  }
}

// Creating Workload Identity Federation for GitHub Actions and Azure DevOps Pipelines
@description('Role definition ID to be assigned')
param roleDefinitionId string = 'b24988ac-6180-42a0-ab88-20f7382dd24c' // Contributor

var githubOIDCProvider = 'https://token.actions.githubusercontent.com'
var microsoftEntraAudience = 'api://AzureADTokenExchange'

resource federatedCredsApp 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: 'federatedCredsApp'
  displayName: 'WI-${customerName}-${applicationName}-Federated Credentials App-${deploymentType}'

  resource githubFic 'federatedIdentityCredentials' = {
    name: '${federatedCredsApp.uniqueName}/githubFic'
    audiences: [microsoftEntraAudience]
    description: 'FIC for Github Actions to access Entra protected resources'
    issuer: githubOIDCProvider
    subject: githubActionsFicSubject
  }
  resource adoFic 'federatedIdentityCredentials' = {
    name: '${federatedCredsApp.uniqueName}/adoFic'
    audiences: [microsoftEntraAudience]
    description: 'FIC for Azure DevOps Pipelines to access Entra protected resources'
    issuer: adoServiceConnectionFicIssuer
    subject: adoServiceConnectionFicSubject
  }

}

// Creating a Service Principal for the Application to be assigned roles and access to Entra ID and Azure
resource federatedCredsAppSp 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: federatedCredsApp.appId
}

// The service principal needs to be assigned the necessary role to access the resources
// In this example, it is assigned with the `Contributor` role to the resource group
// which will allow GitHub actions and Azure DevOps pipelines to access Azure resources in the resource group via Az PS/CLI
var roleAssignmentName = guid(userAssignedIdentity.name, roleDefinitionId, rg.id)
module roleAssignmentSpn 'modules/role-assign/roleAssignment.bicep' = {
  name: 'roleAssignment'
  scope: resourceGroup(rg.name)
  params: {
    roleAssignmentName: roleAssignmentName
    principalId: federatedCredsAppSp.id
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleDefinitionId
  }
}
