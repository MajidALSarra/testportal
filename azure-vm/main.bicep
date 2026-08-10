// Cloud PC on Azure: Windows VM with a static public IP and RDP (3389)
// open to the internet, so it can be reached from anywhere.

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Name of the VM (also used as the Windows computer name)')
param vmName string = 'cloudpc'

@description('Admin username for RDP login (cannot be "admin" or "administrator")')
param adminUsername string

@description('Admin password for RDP login (12+ chars, must mix upper/lower/digit/symbol)')
@secure()
param adminPassword string

@description('VM size. B2s (2 vCPU / 4 GB) is the practical minimum for a usable Windows desktop.')
param vmSize string = 'Standard_B2s'

@description('Operating system: win11 = Windows 11 Pro (cloud PC feel), server2022 = Windows Server 2022 with desktop')
@allowed([
  'win11'
  'server2022'
])
param osType string = 'win11'

var images = {
  win11: {
    publisher: 'MicrosoftWindowsDesktop'
    offer: 'windows-11'
    sku: 'win11-24h2-pro'
    version: 'latest'
  }
  server2022: {
    publisher: 'MicrosoftWindowsServer'
    offer: 'WindowsServer'
    sku: '2022-datacenter-azure-edition'
    version: 'latest'
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${vmName}-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-RDP-From-Anywhere'
        properties: {
          priority: 1000
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: '${vmName}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/24']
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.0.0.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: '${vmName}-ip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: '${vmName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        patchSettings: {
          patchMode: 'AutomaticByOS'
        }
      }
    }
    storageProfile: {
      imageReference: images[osType]
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          // StandardSSD keeps the desktop responsive at low cost.
          // Change to 'Standard_LRS' (HDD) for the absolute cheapest option.
          storageAccountType: 'StandardSSD_LRS'
        }
        deleteOption: 'Delete'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
    // Windows 11 on Azure requires this license acknowledgment
    licenseType: osType == 'win11' ? 'Windows_Client' : null
  }
}

output publicIpAddress string = publicIp.properties.ipAddress
output rdpCommand string = 'mstsc /v:${publicIp.properties.ipAddress}'
