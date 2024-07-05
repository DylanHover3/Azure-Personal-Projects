/*
Author: Dylan Hover
Objective: 
Initial Publication Date: 

Most Recent Update Date: 
Changes Made:

Description:

*/

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Main virtual networks name')
param vnetName string = 'Infra-Vnet'

@description('Main virtual network address prefix')
param vnetAddressSpace string = '10.0.0.0/16'

@description('Application gateway name')
param appGatewayName string = 'App-GW1'

//Parameters for Windows IIS Servers Backend Pool

param adminUsername string
@secure()
param adminPassword string
param vmIISCount int = 3

@description('Name of the VM')
param vmName string = 'WinVmIIS'

@description('Size of the VM')
param vmSize string = 'Standard_B1ms'

@description('Type of the Storage for disks')
@allowed([
  'Standard_LRS'
  'StandardSSD_LRS'
  'Premium_LRS'
])
param diskType string = 'StandardSSD_LRS'

@description('Image SKU')
@allowed([
  '2012-R2-Datacenter'
  '2016-Datacenter'
  '2019-Datacenter'
])
param imageSKU string = '2019-Datacenter'

// Parameters for App Service Plan and Static Web Apps Backend Pool
@description('App Service plan name')
param appServicePlanName string = 'AppServicePlan-.netWebApps'

@description('Describes plan\'s pricing tier and instance size. Check details at https://azure.microsoft.com/en-us/pricing/details/app-service/')
@allowed([
  'F1'
  'D1'
  'B1'
  'B2'
  'B3'
  'S1'
  'S2'
  'S3'
  'P1'
  'P2'
  'P3'
  'P4'
])
param sku string = 'F1'

@description('Web app name.')
@minLength(2)
param webAppName string = 'staticWebApp-${uniqueString(resourceGroup().id)}'

@description('Count for number of static web apps')
param staticWebAppCount int = 3

@description('The language stack of the app.')
@allowed([
  '.net'
  'php'
  'node'
  'html'
])
param language string = '.net'

@description('Optional Git Repo URL, if empty a \'hello world\' app will be deploy from the Azure-Samples repo')
param repoUrl string = ''

var subnetAppGatewayName = 'AppGatewaySubnet'
var subnetWinIISName = 'Win-IIS-Servers-subnet'
var subnetWebAppName = 'Web-app-subnet'
var subnetAppGatewayAddressSpace = '10.0.0.0/24'
var subnetWinIISAddressSpace = '10.0.1.0/24'
var subnetWebAppAddressSpace = '10.0.2.0/24'

var gitRepoReference = {
  '.net': 'https://github.com/Azure-Samples/app-service-web-dotnet-get-started'
  node: 'https://github.com/Azure-Samples/nodejs-docs-hello-world'
  php: 'https://github.com/Azure-Samples/php-docs-hello-world'
  html: 'https://github.com/Azure-Samples/html-docs-hello-world'
}
var gitRepoUrl = (empty(repoUrl) ? gitRepoReference[language] : repoUrl)
var configReference = {
  '.net': {
    comments: '.Net app. No additional configuration needed.'
  }
  html: {
    comments: 'HTML app. No additional configuration needed.'
  }
  php: {
    phpVersion: '7.4'
  }
  node: {
    appSettings: [
      {
        name: 'WEBSITE_NODE_DEFAULT_VERSION'
        value: '12.15.0'
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpace
      ]
    }
    subnets: [
      {
        name: subnetAppGatewayName
        properties: {
          addressPrefix: subnetAppGatewayAddressSpace
        }
      }
      {
        name: subnetWinIISName
        properties: {
          addressPrefix: subnetWinIISAddressSpace
          networkSecurityGroup: {
            id: nsgWinIIS.id
          }
        }
      }
      {
        name: subnetWebAppName
        properties: {
          addressPrefix: subnetWebAppAddressSpace
          networkSecurityGroup: {
            id: nsgWebApp.id
          }
        }
      }
    ]
  }
}

resource nsgWinIIS 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${subnetWinIISName}-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'default-allow-80'
        properties: {
          priority: 1000
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '80'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'default-allow-443'
        properties: {
          priority: 1001
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '443'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'default-allow-3389'
        properties: {
          priority: 1002
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '3389'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource nsgWebApp 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${subnetWebAppName}-nsg'
  location: location
  properties: {
    securityRules: []
  }
}

resource appGWPublicIPAddress 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: '${appGatewayName}-pip'
  location: location
  properties: {
    publicIPAllocationMethod: 'Dynamic'
  }
}

resource appGateway 'Microsoft.Network/applicationGateways@2023-11-01' = {
  name: appGatewayName
  location: location
  properties: {
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
      capacity: 2
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: vnet.properties.subnets[0].id
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGatewayFrontendIP'
        properties: {
          publicIPAddress: {
            id: appGWPublicIPAddress.id
          }
        }
      }
    ]
    backendAddressPools: [
    ]
    frontendPorts: [
    ]
  }
}

resource asp 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: sku
  }
}

resource webApp 'Microsoft.Web/sites@2023-12-01' = [for i in range(0, staticWebAppCount): {
  name: '${webAppName}-${i + 1}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    siteConfig: union(configReference[language],{
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      ftpsState: 'FtpsOnly'
    })
    serverFarmId: asp.id
    httpsOnly: true
  }
}]

resource gitsource 'Microsoft.Web/sites/sourcecontrols@2023-12-01' = [for i in range(0, staticWebAppCount): {
  parent: webApp[i]
  name: 'web'
  properties: {
    repoUrl: gitRepoUrl
    branch: 'master'
    isManualIntegration: true
  }
}]

resource vmWinIIS 'Microsoft.Compute/virtualMachines@2024-03-01' = [for i in range(0, vmIISCount): {
  name: '${vmName}-${i + 1}'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'WinIISVM${i + 1}'
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: imageSKU
        version: 'latest'
      }
      osDisk: {
        name: '${vmName}${i + 1}_OSDisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: diskType
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nicWinIIS[i].id
        }
      ]
    }
  }
}]

resource nicWinIIS 'Microsoft.Network/networkInterfaces@2023-11-01' = [for i in range(0, vmIISCount): {
  name: 'nicWinIISVM${i + 1}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipConfig1'
        properties: {
          subnet: {
            id: vnet.properties.subnets[1].id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}]

//Add public IPs for the VMs and FrontendPort resource for Application Gateway
