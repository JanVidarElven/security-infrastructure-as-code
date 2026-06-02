
// Workload Identity Federation (WIF) Bootstrap Bicep deployment file for Graph resources
// Topic: Experts Live Netherlands 2026 - Security Infrastructure as Code with Bicep and AVM
// Created by: Jan Vidar Elven
// Last Updated: 01.06.2026

targetScope = 'subscription'

// Main Parameters for Deployment
// TODO: Change these to match your environment
param applicationName string = 'Experts Live NL 2026'
param customerName string = 'Elven'
param deploymentType string = 'Bicep-Wif-Bootstrap'

// Parameters for Workload Identity Federation (WIF)
// TODO: Change these for your environment
@description('Tenant ID where the Workload Identity Federation (WIF) is created.')
param tenantId string = deployer().tenantId // Defaults to the tenant of the deployer, or override
@description('Subject of the GitHub Actions workflow\'s federated identity credentials (FIC) that is checked before issuing an Entra ID access token to access Azure resources. GitHub Actions subject examples can be found in https://docs.github.com/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect#example-subject-claims')
param githubActionsFicSubject string = 'repo:JanVidarElven/security-infrastructure-as-code:environment:production' // if by branch 'repo:JanVidarElven/security-infrastructure-as-code:ref:refs/heads/main'
@description('This federation subject identifier is automatically created for this Service connection. Azure DevOps guarantees only this service connection will use that identity globally.')
param adoServiceConnectionFicSubject string = '<Unique Service Connection Identifier from Azure DevOps Service Connection>'

// Build the issuer URL for Azure DevOps Service Connection FIC
var adoServiceConnectionFicIssuer string = 'https://login.microsoftonline.com/${tenantId}/v2.0'


// Initialize the Graph provider
extension microsoftGraphV1

// Get the Resource Id of the Graph resource in the tenant
resource graphSpn 'Microsoft.Graph/servicePrincipals@v1.0' existing = {
  appId: '00000003-0000-0000-c000-000000000000'
}

// Creating Workload Identity Federation for GitHub Actions and Azure DevOps Pipelines
@description('Role definition ID to be assigned')

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

// Define the App Roles to assign to the Managed Identity
param appRoles array = [
  'Application.Read.All'
  'AppRoleAssignment.ReadWrite.All'
]

// Looping through the App Roles and assigning them to the Managed Identity
resource assignAppRole 'Microsoft.Graph/appRoleAssignedTo@v1.0' = [for appRole in appRoles: {
  appRoleId: (filter(graphSpn.appRoles, role => role.value == appRole)[0]).id
  principalId: federatedCredsAppSp.id
  resourceId: graphSpn.id
}]
