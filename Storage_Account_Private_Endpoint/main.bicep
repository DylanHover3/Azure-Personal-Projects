/*
Author: Dylan Hover
Objective: To deploy a Storage Account with a Private endpoint and Private DNS Zone for POC testing.
Initial Publication Date: 01/19/2025

Most Recent Update Date: 01/19/2025
Changes Made:

Description:
This Bicep file will deploy a Storage Account with a File Share. It will setup the storage account with Private Link, Private Endpoint, and Private DNS Zone for DNS resolution. This deployment will link the Private DNS Zone for the Storagae Account File Share to the virtual network that the Private Endpoint is setup in. It will also disable Public IP access so that the storage account is only accessible through the Private IP address of the storage account. This makes the storage account accessible through the virtual network.
*/

@description('The location into which the resources should be deployed.')
param location string = resourceGroup().location

@description('The name of the Azure storage account.')
param storageAccountName string = 'hyperechofilestorage'

@description('The name of an existing virtual network.')
param vnetName string

@description('The resource group of the existing virtual network.')
param vnetResourceGroup string

@description('The name of an existing virtual network subnet used for private endpoint.')
param privateEndpointSubnetName string

var privateStorageFileDnsZoneName = 'privatelink.file.${environment().suffixes.storage}'
var privateEndpointStorageFileName = '${storageAccountName}-file-private-endpoint'
var fileShareName = 'hyperecho-content-share'

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
  scope: resourceGroup(vnetResourceGroup)
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  name: privateEndpointSubnetName
  parent: vnet
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    publicNetworkAccess: 'Disabled'
    allowBlobPublicAccess: false
    networkAcls: {
      bypass: 'AzureServices'
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
  name: '${vnet.name}-link'
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
      id: subnet.id
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
        name: 'storage-file-dns-zone-config'
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
