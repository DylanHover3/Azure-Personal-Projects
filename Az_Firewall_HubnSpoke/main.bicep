/*
Author: Dylan Hover
Objective: To deploy a Bastion Hub and Spoke network topology with Azure Firewall for POC testing.
Initial Publication Date: 06/16/2024

Most Recent Update Date: 06/20/2024
Changes Made:

- Added seperate route table for Jumpbox subnet.
- Added additional routes to manage manage routes between Vnets, and from Vnets to internet.

Description:
This Bicep file will deploy a Hub network with Azure Firewall and Azure Bastion for remoting into VMs. It will deploy a specified number of spoke networks each with their own NSG associated to their subnet. It will also deploy a VM to the subnet of each Spoke network. Lastly it will peer the Hub network to the Spoke networks to allow for connectivity to each of the spoke networks from the Hub. This deployment will be used for POC for Azure Firewalls
*/

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Hub Vnet name')
param hubVirtualNetworkName string = 'hub-vnet'

@description('Number of spoke networks to be created')
param spokeNetworkCount int = 2

@description('Names for the IP Groups to use in Az Firewall rules')
param ipgroups_name1 string = 'Jumpserver-IPgroup'
param ipgroups_name2 string = 'Servers-IPgroup'

@description('Username for the Virtual Machine.')
param adminUsername string

@description('SSH Key or password for the Virtual Machine. SSH key is recommended.')
@secure()
param adminPasswordOrKey string

/*@description('Type of authentication to use on the Virtual Machine.')
@allowed([
  'sshPublicKey'
  'password'
])
param authenticationType string = 'password' */

@description('Zone numbers e.g. 1,2,3.')
param vmSize string = 'Standard_B1ms'

@description('The Windows version for the VM. This will pick a fully patched image of this given Windows version.')
@allowed([
  '2016-datacenter-gensecond'
  '2016-datacenter-server-core-g2'
  '2016-datacenter-server-core-smalldisk-g2'
  '2016-datacenter-smalldisk-g2'
  '2016-datacenter-with-containers-g2'
  '2016-datacenter-zhcn-g2'
  '2019-datacenter-core-g2'
  '2019-datacenter-core-smalldisk-g2'
  '2019-datacenter-core-with-containers-g2'
  '2019-datacenter-core-with-containers-smalldisk-g2'
  '2019-datacenter-gensecond'
  '2019-datacenter-smalldisk-g2'
  '2019-datacenter-with-containers-g2'
  '2019-datacenter-with-containers-smalldisk-g2'
  '2019-datacenter-zhcn-g2'
  '2022-datacenter-azure-edition'
  '2022-datacenter-azure-edition-core'
  '2022-datacenter-azure-edition-core-smalldisk'
  '2022-datacenter-azure-edition-smalldisk'
  '2022-datacenter-core-g2'
  '2022-datacenter-core-smalldisk-g2'
  '2022-datacenter-g2'
  '2022-datacenter-smalldisk-g2'
])
param OSVersion string = '2019-datacenter-gensecond'

@description('Security Type of the Virtual Machine.')
@allowed([
  'Standard'
  'TrustedLaunch'
])
param securityType string = 'Standard'

@description('Number of public IP addresses for the Azure Firewall')
@minValue(1)
@maxValue(100)
param numberOfFirewallPublicIPAddresses int = 1

var hubVnetAddressPrefix = '10.0.0.0/16'
var jumpBoxSubnetName = 'JumpboxSubnet'
var jumpboxSubnetPrefix = '10.0.1.0/24'
var JumpBoxSubnetNSGName = '${jumpBoxSubnetName}-nsg'
var spokeNetworkName = ['Spoke1-Vnet', 'Spoke2-Vnet']
var spokeVnetAddressPrefix = ['10.1.0.0/16', '10.2.0.0/16']
var spokeSubnetName = ['Spoke1-ServersSubnet', 'Spoke2-ServersSubnet']
var spokeSubnetAddressPrefixes = ['10.1.1.0/24', '10.2.1.0/24']
var jumpBoxPublicIPAddressName = 'JumpHostPublicIP'
var jumpBoxNicName = 'JumpHostNic'
var jumpBoxSubnetId = resourceId('Microsoft.Network/virtualNetworks/subnets', hubVirtualNetworkName, jumpBoxSubnetName)
var spokeServerNicName = 'ServerNic'
var storageAccountName = 'sajumpbox${uniqueString(resourceGroup().id)}'
var hubRouteTableName = 'HubRouteTable'
var spokeRouteTableName = 'SpokeRouteTable'
var nextHopIP = '10.0.120.4'
var bastionHostName = 'hubBastion'
var bastionSubnetName = 'AzureBastionSubnet'
var bastionSubnetPrefix = '10.0.60.0/26'
var bastionSubnetID = resourceId('Microsoft.Network/virtualNetworks/subnets', hubVirtualNetworkName, bastionSubnetName)
var firewallName = 'hub-firewall'
var azureFirewallSubnetName = 'AzureFirewallSubnet'
var azureFirewallSubnetPrefix = '10.0.120.0/26'
var azureFiewallPIPNamePrefix = 'Firewall-PIP'
var azureFirewallSubnetId = resourceId('Microsoft.Network/virtualNetworks/subnets', hubVirtualNetworkName, azureFirewallSubnetName)
var azureFirewallIpConfigurations = [for i in range(0, numberOfFirewallPublicIPAddresses): {
  name: 'IpConf${i}'
  properties: {
    subnet: {
      id: (i == 0) ? azureFirewallSubnetId : null
    }
    publicIPAddress: {
      id: FirewallPIP[i].id
    }
  }
}]
/*var linuxConfiguration = {
  disablePasswordAuthentication: true
  ssh: {
    publicKeys: [
      {
        path: '/home/${adminUsername}/.ssh/authorized_keys'
        keyData: adminPasswordOrKey
      }
    ]
  }
}*/
var securityProfileJson = {
  uefiSettings: {
    secureBootEnabled: true
    vTpmEnabled: true
  }
  securityType: securityType
}

resource hubVirtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: hubVirtualNetworkName
  location: location
  tags: {
    displayName: hubVirtualNetworkName
  }
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubVnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: jumpBoxSubnetName
        properties: {
          addressPrefix: jumpboxSubnetPrefix
          routeTable: {
            id: hubRouteTable.id
          }
          networkSecurityGroup: {
            id: jumpBoxSubnetNsg.id
          }
        }
      }
      {
        name: bastionSubnetName
        properties: {
          addressPrefix: bastionSubnetPrefix
        }
      }
      {
        name: azureFirewallSubnetName
        properties: {
          addressPrefix: azureFirewallSubnetPrefix
        }
      }   
    ]
  }
}

resource spokeVirtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = [for i in range(0, spokeNetworkCount): {
  name: spokeNetworkName[i]
  location: location
  tags: {
    displayName: spokeNetworkName[i]
  }
  properties: {
    addressSpace: {
      addressPrefixes: [
        spokeVnetAddressPrefix[i]
      ]
    }
    subnets: [
      {
        name: spokeSubnetName[i]
        properties: {
          addressPrefix: spokeSubnetAddressPrefixes[i]
          routeTable: {
            id: spokeRouteTable.id
          }
          networkSecurityGroup: {
            id: spokeSubnetNSG[i].id
          }
        }
      }
    ]
  }
}]

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {}
}

resource hubRouteTable 'Microsoft.Network/routeTables@2023-09-01' = {
  name: hubRouteTableName
  location: location
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'InternetDefaultRoute'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: nextHopIP
        }
      }
      {
        name: 'To-Spoke1Vnet'
        properties: {
          addressPrefix: '10.1.0.0/16'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: nextHopIP
        }
      }
      {
        name: 'To-Spoke2Vnet'
        properties: {
          addressPrefix: '10.2.0.0/16'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: nextHopIP
        }
      }
    ]
  }
}

resource spokeRouteTable 'Microsoft.Network/routeTables@2023-09-01' = {
  name: spokeRouteTableName
  location: location
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'InternetDefaultRoute'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: nextHopIP
        }
      }
      {
        name: 'To-JumpserverSubnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: nextHopIP
        }
      }
      {
        name: 'To-Spoke1Vnet'
        properties: {
          addressPrefix: '10.1.0.0/16'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: nextHopIP
        }
      }
      {
        name: 'To-Spoke2Vnet'
        properties: {
          addressPrefix: '10.2.0.0/16'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: nextHopIP
        }
      }
    ]
  }
}

resource jumpBoxPublicIPAddress 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: jumpBoxPublicIPAddressName
  location: location
  properties: {
    publicIPAllocationMethod: 'Dynamic'
  }
}

resource jumpBoxSubnetNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: JumpBoxSubnetNSGName
  location: location
  properties: {}
}

resource JumpBoxNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: jumpBoxNicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: jumpBoxPublicIPAddress.id
          }
          subnet: {
            id: jumpBoxSubnetId
          }
        }
      }
    ]
  }
  dependsOn: [
    hubVirtualNetwork
  ]
}

/*
Hub Linux Machine Deployment
resource hubJumpBoxLinuxVm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: 'JumpBox'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'UbuntuServer'
        sku: '18.04-LTS'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
      }
    }
    osProfile: {
      computerName: 'JumpBox'
      adminUsername: adminUsername
      adminPassword: adminPasswordOrKey
      linuxConfiguration: ((authenticationType == 'password') ? null : linuxConfiguration)
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: JumpBoxNic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: storageAccount.properties.primaryEndpoints.blob
      }
    }
  }
}
  */

resource hubJumpBoxWindowsVM 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: 'JumpBox'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'JumpBox'
      adminUsername: adminUsername
      adminPassword: adminPasswordOrKey
    }
    storageProfile: {
       imageReference: {
         publisher: 'MicrosoftWindowsServer'
         offer: 'WindowsServer'
         sku: OSVersion
         version: 'latest'
       }
       osDisk: {
         createOption: 'FromImage'
         managedDisk: {
           storageAccountType: 'StandardSSD_LRS'
         }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: JumpBoxNic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: storageAccount.properties.primaryEndpoints.blob
      }
    }
    securityProfile: ((securityType == 'TrustedLaunch') ? securityProfileJson : null)
  }
}

resource spokeSubnetNSG 'Microsoft.Network/networkSecurityGroups@2023-09-01' = [for i in range(0, spokeNetworkCount): {
  name: 'Spoke${i + 1}-NSG'
  location: location
  properties: {}
}]

resource spokeServerNic 'Microsoft.Network/networkInterfaces@2023-09-01' = [for i in range(0, spokeNetworkCount): {
  name: '${spokeServerNicName}-${i + 1}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: resourceId('Microsoft.Network/VirtualNetworks/subnets', spokeVirtualNetwork[i].name, spokeSubnetName[i])
          }
        }
      }
    ]
  }
  dependsOn: [
    spokeVirtualNetwork
  ]
}]

/*
Spoke Linux Machine Deployment
resource spoke1ServerLinuxVm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: 'Spoke1-Server'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2012-R2-Datacenter'
        version: 'latest'
      }
      osDisk: {
        name: 'Spoke1-Server'
        caching: 'ReadWrite'
        createOption: 'FromImage'
      }
    }
    osProfile: {
      computerName: 'Server'
      adminUsername: adminUsername
      adminPassword: adminPasswordOrKey
      linuxConfiguration: ((authenticationType == 'password') ? null : linuxConfiguration)
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: spoke1ServerNic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: storageAccount.properties.primaryEndpoints.blob
      }
    }
  }
}
  */

resource spoke1ServerWindowsVM 'Microsoft.Compute/virtualMachines@2024-03-01' = [for i in range(0, spokeNetworkCount): {
  name: 'Spoke${i + 1}-Server'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'Spoke1-Server'
      adminUsername: adminUsername
      adminPassword: adminPasswordOrKey
    }
    storageProfile: {
       imageReference: {
         publisher: 'MicrosoftWindowsServer'
         offer: 'WindowsServer'
         sku: OSVersion
         version: 'latest'
       }
       osDisk: {
         createOption: 'FromImage'
         managedDisk: {
           storageAccountType: 'StandardSSD_LRS'
         }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: spokeServerNic[i].id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: storageAccount.properties.primaryEndpoints.blob
      }
    }
    securityProfile: ((securityType == 'TrustedLaunch') ? securityProfileJson : null)
  }
}]

resource bastionPublicIPAddress 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'Bastion-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastionHost 'Microsoft.Network/bastionHosts@2023-11-01' = {
  name: bastionHostName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          subnet: {
            id: bastionSubnetID
          }
          publicIPAddress: {
            id: bastionPublicIPAddress.id
          }
        }
      }
    ]
  }
  dependsOn: [
    hubVirtualNetwork
  ]
}

resource FirewallPIP 'Microsoft.Network/publicIPAddresses@2023-09-01' = [for i in range(0, numberOfFirewallPublicIPAddresses): {
  name: '${azureFiewallPIPNamePrefix}${i + 1}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}]

resource firewall 'Microsoft.Network/azureFirewalls@2023-11-01' = {
  name: firewallName
  location: location
  dependsOn: [
    hubVirtualNetwork
    FirewallPIP
  ]
  properties: {
    ipConfigurations: azureFirewallIpConfigurations
  }
}

resource ipgroup1 'Microsoft.Network/ipGroups@2023-09-01' = {
  name: ipgroups_name1
  location: location
  properties: {
    ipAddresses: [
      '10.0.1.0/24'
    ]
  }
}

resource ipgroup2 'Microsoft.Network/ipGroups@2023-09-01' = {
  name: ipgroups_name2
  location: location
  properties: {
    ipAddresses: [
      '10.1.1.0/24'
      '10.2.1.0/24'
    ]
  }
}

resource hubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2020-07-01' = [for i in range(0, spokeNetworkCount): {
  parent: hubVirtualNetwork
  name: 'Hub-to-Spoke${i + 1}'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: spokeVirtualNetwork[i].id
    }
  }
}]

resource spokePeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2020-07-01' = [for i in range(0, spokeNetworkCount): {
  parent: spokeVirtualNetwork[i]
  name: 'Spoke${i + 1}-to-Hub'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: hubVirtualNetwork.id
    }
  }
}]


output location string = location
output name string = firewall.name
output resourceGroupName string = resourceGroup().name
output resourceId string = firewall.id
