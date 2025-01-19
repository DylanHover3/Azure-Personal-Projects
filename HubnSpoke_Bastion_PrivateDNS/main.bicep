/*
Author: Dylan Hover
Objective: To deploy a Bastion Hub and Spoke network topology with network peering for POC testing.
Initial Publication Date: 06/08/2024

Most Recent Update Date: 06/08/2024
Changes Made:

Description:
This Bicep file will deploy a Hub network with a Bastion host. It will deploy a specified number of spoke networks each with their own NSG associated to their subnet. It will also deploy a VM to the subnet of each Spoke network. Lastly it will peer the Hub network to the Spoke networks to allow for connectivity to each of the spoke networks from the Hub. 
*/

@description('The location of all resources')
param location string = resourceGroup().location

@description('The name of the Hub network')
param hubNetworkName string = 'Hub1'

@description('The address prefix of the Hub network')
param hubNetworkPrefix string = '10.0.0.0/16'

@description('The name of the Bastion host')
param bastionHostName string = 'hubBastion'

@description('Bastion subnet IP prefix MUST be within vnet IP prefix address space')
param bastionSubnetIpPrefix string = '10.0.0.0/26'

@description('Number of spoke networks to be created')
param spokeNetworkCount int = 3

@description('VMs Admin Username')
param userName string

@description('Admin Account for VMs password')
@minLength(12)
@secure()
param adminPassword string

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

@description('Size of the virtual machine.')
param vmSize string = 'Standard_B1ms'

@description('Security Type of the Virtual Machine.')
@allowed([
  'Standard'
  'TrustedLaunch'
])
param securityType string = 'Standard'

param privateDnsZones_hyperechocloud_com_name string = 'hyperechocloud.com'
param privateEndpoints_spoke3_blob_storage_name string = 'spoke3_blob_storage'
param storageAccounts_name string = 'hyperechoawesomestor'

var bastionSubnetName = 'AzureBastionSubnet'
var hubSubnet2Name = 'Subnet-2'
var spokeName = ['SpokeNetwork1', 'SpokeNetwork2', 'SpokeNetwork3', 'SpokeNetwork4']
var spokeAddressPrefixes = ['10.1.0.0/16', '10.2.0.0/16', '10.3.0.0/16', '10.4.0.0/16']
var spokeSubnetName = 'Subnet-1'
var spokeSubnetAddressPrefixes = ['10.1.1.0/24', '10.2.1.0/24', '10.3.1.0/24', '10.4.1.0/24']
var securityProfileJson = {
  uefiSettings: {
    secureBootEnabled: true
    vTpmEnabled: true
  }
  securityType: securityType
}


/*Deploying Resources: Hub Network, Bastion Host into Hub, Hub-VM for Subnet-2 in Hub network, Spoke Networks with 1 Windows VM in each, NSG for each subnet in Spoke networks, ASGs for VMs, and Peerings between hub network and spoke networks*/

resource hubNetwork 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: hubNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubNetworkPrefix
      ]
    }
    subnets: [
      {
        name: bastionSubnetName
        properties: {
          addressPrefix: bastionSubnetIpPrefix
        }
      }
      {
        name: hubSubnet2Name
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: hubNetworkSecurityGroup.id
          }
        }
      }
    ]
  }
}

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
            id: hubNetwork.properties.subnets[0].id
          }
          publicIPAddress: {
            id: bastionPublicIPAddress.id
          }
        }
      }
    ]
  }
}

resource hubNetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'Hub-Subnet2-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'nsgRule1'
        properties: {
          description: 'description'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: '10.0.0.0/26'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource hubNetworkInterface 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: 'Hub-VM-NIC'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconifig-1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: resourceId('Microsoft.Network/VirtualNetworks/subnets', hubNetwork.name, hubSubnet2Name)
          }
        }
      }
    ]
  }
}

resource hubWindowsVM 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: 'Hub-VM'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'Hub-VM'
      adminUsername: userName
      adminPassword: adminPassword
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
          id: hubNetworkInterface.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
    securityProfile: ((securityType == 'TrustedLaunch') ? securityProfileJson : null)
  }
}

resource spokeNetwork 'Microsoft.Network/virtualNetworks@2023-11-01' = [for i in range(0, spokeNetworkCount): {
   name: spokeName[i]
   location: location
   properties: {
     addressSpace: {
       addressPrefixes: [
         spokeAddressPrefixes[i]
       ]
     }
     subnets: [
       {
         name: spokeSubnetName
         properties: {
           addressPrefix: spokeSubnetAddressPrefixes[i]
           networkSecurityGroup: {
             id: SpokenetworkSecurityGroup[i].id
           }
         }
       }
     ]
    }
  }
]

resource applicationSecurityGroup 'Microsoft.Network/applicationSecurityGroups@2023-11-01' = [for i in range(0, spokeNetworkCount): {
  name: 'Allow-RDM-Spoke${i + 1}-VM'
  location: location
 }
]

resource SpokenetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-11-01' = [for i in range(0, spokeNetworkCount): {
    name: 'Spoke${i + 1}-Subnet1-nsg'
    location: location
    properties: {
      securityRules: [
        {
          name: 'nsgRule1'
          properties: {
            description: 'description'
            protocol: 'Tcp'
            sourcePortRange: '*'
            destinationPortRange: '3389'
            sourceAddressPrefix: '10.0.0.0/26'
            destinationAddressPrefix: '*'
            access: 'Allow'
            priority: 1000
            direction: 'Inbound'
          }
        }
      ]
    }
  }
]

resource networkInterface 'Microsoft.Network/networkInterfaces@2023-11-01' = [for i in range(0, spokeNetworkCount): {
   name: 'Spoke${i + 1}-VM-NIC'
   location: location
   properties: {
     ipConfigurations: [
       {
         name: 'ipconifig-1'
         properties: {
           privateIPAllocationMethod: 'Dynamic'
           subnet: {
             id: resourceId('Microsoft.Network/VirtualNetworks/subnets', spokeNetwork[i].name, spokeSubnetName)
           }
         }
       }
     ]
   }
  }
]

resource spokeWindowsVM 'Microsoft.Compute/virtualMachines@2024-03-01' = [for i in range(0, spokeNetworkCount): {
  name: 'Spoke${i + 1}-VM'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'Spoke${i + 1}-VM'
      adminUsername: userName
      adminPassword: adminPassword
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
          id: networkInterface[i].id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
    securityProfile: ((securityType == 'TrustedLaunch') ? securityProfileJson : null)
  }
}
]

resource hubPeerings 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = [for i in range(0, spokeNetworkCount): {
    parent: hubNetwork
    name: 'hubNetwork-to-SpokeNetwork${i + 1}'
    properties: {
      allowVirtualNetworkAccess: true
      allowForwardedTraffic: true
      allowGatewayTransit: false
      useRemoteGateways: false
      remoteVirtualNetwork: {
        id: spokeNetwork[i].id
      }
    }
  }
]

resource spokePeerings 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = [for i in range(0, spokeNetworkCount): {
    parent: spokeNetwork[i]
    name: 'Spoke${i + 1}-to-${hubNetwork.name}'
    properties: {
      allowVirtualNetworkAccess: true
      allowForwardedTraffic: true
      allowGatewayTransit: false
      useRemoteGateways: false
      remoteVirtualNetwork: {
        id: hubNetwork.id
      }
    }
  }
]

resource privateDnsZones_hyperechocloud_com 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZones_hyperechocloud_com_name
  location: 'global'
  properties: {}
}

resource privateDnsZones_hub_link 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZones_hyperechocloud_com
  name: 'vnet1-link'
  location: 'global'
  properties: {
    registrationEnabled: true
    virtualNetwork: {
      id: hubNetwork.id
    }
  }
}
