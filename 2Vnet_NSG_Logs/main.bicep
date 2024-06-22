/*
Author: Dylan Hover
Objective: To deploy a Bastion Hub and Spoke network topology to test NSG flow logs.
Initial Publication Date: 06/08/2024

Most Recent Update Date: 06/11/2024
Changes Made:

Description:
This Bicep file will deploy a Hub network with a Bastion host. There will be two vnets peered together with a vm in each of them. There will also be a NSG associated to the subnets in the Hub and Spoke networks. Network watcher will be enabled for the region that these Vnets are deployed in. This deployment will be used for testing and learning the NSG flow logs. 
*/

@description('The location of all resources')
param location string = resourceGroup().location

@description('The name of the Hub network')
param hubNetworkName string = 'Hub1'

@description('The address prefix of the Hub network')
param hubNetworkPrefix string = '10.0.0.0/16'

@description('The name of the Bastion host')
param bastionHostName string = 'hubBastion'

@description('Hub network Bastion subnet name')
param bastionSubnetName string = 'AzureBastionSubnet'

@description('Bastion subnet IP prefix MUST be within vnet IP prefix address space')
param bastionSubnetIpPrefix string = '10.0.0.0/26'

@description('Bastion PIP Name')
param bastionPIP string = 'Bastion-PIP'

@description('Hubnet network vm subnet name')
param hubSubnet1Name string = 'Subnet1'

@description('Subnet1 address prefix')
param hubSubnet1AddressPrefix string ='10.0.1.0/24'

@description('Spoke1 network name')
param spoke1NetworkName string = 'Spoke1'

@description('Spoke network address prefix')
param spokeAddressPrefix string = '10.1.0.0/16'

@description('Spoke network subnet1 name')
param spoke1Subnet1Name string = 'Subnet1'

@description('Spoke1 subnet1 address prefix')
param spoke1Subnet1Prefix string = '10.1.1.0/24'

@description('Hub subnet1 NSG name')
param hubSubNSGName string = 'Hub-Subnet1-NSG'

@description('Spoke1 subnet1 NSG name')
param spokeSubNSGName string = 'Spoke1-Subnet1-NSG'

@description('Hub Ubuntu vm name')
param hubUbuntuName string = 'Hub-vm'

@description('Spoke Ubuntu vm name')
param spokeUbuntuName string = 'Spoke-vm'

@description('The Ubuntu Sku for the VM.')
@allowed([
  '16_04-lts-gen2'
  '20_04-lts-gen2'
  '22_04-lts-gen2'
])
param OSVersion string = '20_04-lts-gen2'

@description('Size of the virtual machine.')
param vmSize string = 'Standard_B1ms'

@description('Security Type of the Virtual Machine.')
@allowed([
  'Standard'
  'TrustedLaunch'
])
param securityType string = 'Standard'

@description('Type of authentication to use on the Virtual Machine. SSH key is recommended.')
@allowed([
  'sshPublicKey'
  'password'
])
param authenticationType string = 'password'

@description('VMs Admin Username')
param userName string

@description('Admin Account for VMs password')
@minLength(12)
@secure()
param adminPassword string

var linuxConfiguration = {
  disablePasswordAuthentication: true
  ssh: {
    publicKeys: [
      {
        path: '/home/${userName}/.ssh/authorized_keys'
        keyData: null
      }
    ]
  }
}

var securityProfileJson = {
  uefiSettings: {
    secureBootEnabled: true
    vTpmEnabled: true
  }
  securityType: securityType
}

resource hubVirtualNetwork 'Microsoft.Network/virtualNetworks@2023-11-01' = {
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
        name: hubSubnet1Name
        properties: {
          addressPrefix: hubSubnet1AddressPrefix
          networkSecurityGroup: {
            id: hubNetworkSecurityGroup.id
          }
        }
      }
    ]
  }
}

resource spokeVirtualNetwork 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: spoke1NetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        spokeAddressPrefix
      ]
    }
    subnets: [
      {
        name: spoke1Subnet1Name
        properties: {
          addressPrefix: spoke1Subnet1Prefix
          networkSecurityGroup: {
            id: spokeNetworkSecurityGroup.id
          }
        }
      }
    ]
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
            id: hubVirtualNetwork.properties.subnets[0].id
          }
          publicIPAddress: {
            id: publicIPAddress.id
          }
        }
      }
    ]
  }
}

resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: bastionPIP
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource hubNetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: hubSubNSGName
  location: location
  properties: {
    securityRules: [
      {
        name: 'nsgRule1'
        properties: {
          description: 'description'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
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

resource spokeNetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: spokeSubNSGName
  location: location
  properties: {
    securityRules: [
      {
        name: 'nsgRule'
        properties: {
          description: 'description'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
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
  name: 'Hub-vm-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'Ipconfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: hubVirtualNetwork.properties.subnets[1].id
          }
        }
      }
    ]
  }
}

resource spokeNetworkInterface 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: 'Spoke-vm-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'Ipconfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: spokeVirtualNetwork.properties.subnets[0].id
          }
        }
      }
    ]
  }
}

resource hubUbuntuVM 'Microsoft.Compute/virtualMachines@2020-12-01' = {
  name: hubUbuntuName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: hubUbuntuName
      adminUsername: userName
      adminPassword: adminPassword
      linuxConfiguration: ((authenticationType == 'password') ? null : linuxConfiguration)
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-focal'
        sku: OSVersion
        version: 'latest'
      }
      osDisk: {
        name: 'hub-vm-disk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
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
        enabled: false
      }
    }
    securityProfile: (securityType == 'TrustedLaunch') ? securityProfileJson : null
  }
}

resource spokeUbuntuVM 'Microsoft.Compute/virtualMachines@2020-12-01' = {
  name: spokeUbuntuName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: spokeUbuntuName
      adminUsername: userName
      adminPassword: adminPassword
      linuxConfiguration: ((authenticationType == 'password') ? null : linuxConfiguration)
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-focal'
        sku: OSVersion
        version: 'latest'
      }
      osDisk: {
        name: 'spoke-vm-disk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: spokeNetworkInterface.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: false
      }
    }
    securityProfile: (securityType == 'TrustedLaunch') ? securityProfileJson : null
  }
}

resource hubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2020-07-01' = {
  parent: hubVirtualNetwork
  name: 'Hub-to-Spoke'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: spokeVirtualNetwork.id
    }
  }
}

resource spokePeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2020-07-01' = {
  parent: spokeVirtualNetwork
  name: 'Spoke-to-Hub'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: hubVirtualNetwork.id
    }
  }
}
