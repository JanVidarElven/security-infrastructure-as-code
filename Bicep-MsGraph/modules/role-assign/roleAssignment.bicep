// Azure Role Assignment - Bicep module
// Created by - Jan Vidar Elven

@description('The name of your role assignment')
param roleAssignmentName string

@description('The ID of the Principal to assign the role to')
param principalId string

@description('The type of principal to assign the role to')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
  'ForeignGroup'
  'Device'
])
param principalType string

@description('The role definition ID to assign to the principal')
param roleDefinitionId string

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: roleAssignmentName
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
  }
}
