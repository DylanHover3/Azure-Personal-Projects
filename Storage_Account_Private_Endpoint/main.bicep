@description('The location into which the resources should be deployed.')
param location string = resourceGroup().location

@description('The name of the Azure storage account.')
param storageAccountName string = 'hyperechostorage${(resourceGroup().id)}'

@description('The name of the virtual network for virtual network integration.')
param vnetName string = 'vnet-${uniqueString(resourceGroup().id)}'

@description('The name of the virtual network subnet used for private endpoint.')
param privateEndpointSubnetName string = 'Subnet1'

@description('The IP address space used for the virtual network.')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('The IP address space used for the private endpoints.')
param privateEndpointSubnetAddressPrefix string = '10.0.0.0/24'

var privateStorageFileDnsZoneName = 'privatelink.file.${environment().suffixes.storage}'
var privateEndpointStorageFileName = '${storageAccountName}-file-private-endpoint'
var fileShareName = 'hyperecho-content-share'

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: privateEndpointSubnetName
        properties: {
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          addressPrefix: privateEndpointSubnetAddressPrefix
        }
      }
    ]
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    publicNetworkAccess: 'Disabled'
    allowBlobPublicAccess: false
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
    }
  }
}

resource privateStorageFileDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: privateStorageFileDnsZoneName
  location: 'global'
}

resource privateStorageFileDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateStorageFileDnsZone
  name: '${privateStorageFileDnsZoneName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource privateEndpointStorageFile 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: privateEndpointStorageFileName
  location: location
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, privateEndpointSubnetName)
    }
    privateLinkServiceConnections: [
      {
        name: 'MyStorageFilePrivateLinkConnection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'file'
          ]
        }
      }
    ]
  }
  dependsOn: [
    vnet
  ]
}

resource privateEndpointStorageFilePrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpointStorageFile
  name: 'filePrivateDnsZoneGroup'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config'
        properties: {
          privateDnsZoneId: privateStorageFileDnsZone.id
        }
      }
    ]
  }
}

resource fileService 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  name: '${storageAccountName}/default/${fileShareName}'
  dependsOn: [
    storageAccount
  ]
}
