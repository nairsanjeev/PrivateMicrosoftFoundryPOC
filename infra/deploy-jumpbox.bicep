/*
  Jump Box VM + Azure Bastion in VNet 1 (Foundry BYO VNet)
  
  Provides access to private Foundry endpoint and all PE-connected resources.
  Access the VM via Azure Portal → Bastion (no public IP on the VM).
*/

param location string = 'swedencentral'
param vnetName string = 'foundry-poc-vnet'
param adminUsername string = 'azureadmin'

@secure()
param adminPassword string

// ── Add subnets to existing VNet ─────────────────────────────────────
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' existing = {
  name: vnetName
}

resource vmSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' = {
  parent: vnet
  name: 'vm-subnet'
  properties: {
    addressPrefix: '192.168.3.0/24'
    networkSecurityGroup: { id: vmNsg.id }
  }
}

resource bastionSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' = {
  parent: vnet
  name: 'AzureBastionSubnet'
  properties: {
    addressPrefix: '192.168.4.0/24'
  }
  dependsOn: [vmSubnet] // serialize subnet creates
}

// ── NSG for VM subnet ────────────────────────────────────────────────
resource vmNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: 'nsg-jumpbox'
  location: location
  properties: {
    securityRules: []
  }
}

// ── VM NIC (no public IP) ────────────────────────────────────────────
resource nic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: 'nic-jumpbox'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: { id: vmSubnet.id }
        }
      }
    ]
  }
}

// ── Windows VM ───────────────────────────────────────────────────────
resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: 'vm-jumpbox'
  location: location
  properties: {
    hardwareProfile: { vmSize: 'Standard_D2s_v3' }
    osProfile: {
      computerName: 'jumpbox'
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsDesktop'
        offer: 'windows-11'
        sku: 'win11-24h2-pro'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'Premium_LRS' }
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: nic.id }]
    }
  }
}

// ── Install Edge + Python + Azure CLI via custom script ──────────────
resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent: vm
  name: 'setup-tools'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      commandToExecute: 'powershell -Command "Start-Process msiexec.exe -ArgumentList \'/i https://aka.ms/installazurecliwindowsx64 /quiet\' -Wait"'
    }
  }
}

// ── Azure Bastion (portal-based RDP) ─────────────────────────────────
resource bastionPip 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: 'pip-bastion'
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2024-01-01' = {
  name: 'bastion-foundry'
  location: location
  sku: { name: 'Basic' }
  properties: {
    ipConfigurations: [
      {
        name: 'bastionIpConfig'
        properties: {
          publicIPAddress: { id: bastionPip.id }
          subnet: { id: bastionSubnet.id }
        }
      }
    ]
  }
}

// ── Outputs ──────────────────────────────────────────────────────────
output vmName string = vm.name
output vmPrivateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output bastionName string = bastion.name
