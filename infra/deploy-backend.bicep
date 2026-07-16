/*
  Backend Infrastructure: VNet 2 + Azure Function (private) + APIM (public gateway)
  
  Architecture:
  - VNet 2 (10.0.0.0/16) with two subnets:
    - apim-subnet (10.0.0.0/24): APIM injected here (external mode = public IP inbound)
    - func-subnet (10.0.1.0/24): Azure Function VNet integrated (no public access)
  - APIM is the single public endpoint that routes to the private Function
  - The Foundry Agent in VNet 1 calls APIM's public endpoint as an OpenAPI tool
*/

param location string = 'swedencentral'
param suffix string = 'poc'

// ── VNet 2: Backend Network ──────────────────────────────────────────
resource backendVnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: 'backend-vnet-${suffix}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/16']
    }
    subnets: [
      {
        name: 'apim-subnet'
        properties: {
          addressPrefix: '10.0.0.0/24'
          networkSecurityGroup: { id: apimNsg.id }
        }
      }
      {
        name: 'func-subnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
          delegations: [
            {
              name: 'Microsoft.Web.serverFarms'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
    ]
  }
}

// ── NSG for APIM subnet (required ports) ─────────────────────────────
resource apimNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: 'nsg-apim-${suffix}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowAPIMManagement'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3443'
          sourceAddressPrefix: 'ApiManagement'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'AllowHTTPS'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'AllowHTTP'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'AllowLoadBalancer'
        properties: {
          priority: 130
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '6390'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
    ]
  }
}

// ── Storage Account for Function App ─────────────────────────────────
resource funcStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'stfunc${suffix}${uniqueString(resourceGroup().id)}'
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
  }
}

// ── App Service Plan for Function ────────────────────────────────────
resource funcPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'plan-func-${suffix}'
  location: location
  kind: 'linux'
  sku: {
    name: 'P1v3'
    tier: 'PremiumV3'
  }
  properties: {
    reserved: true
  }
}

// ── Azure Function (PRIVATE - no public access) ──────────────────────
resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: 'func-order-api-${suffix}-${uniqueString(resourceGroup().id)}'
  location: location
  kind: 'functionapp,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: funcPlan.id
    virtualNetworkSubnetId: backendVnet.properties.subnets[1].id
    vnetRouteAllEnabled: true
    publicNetworkAccess: 'Disabled'
    siteConfig: {
      linuxFxVersion: 'Python|3.11'
      appSettings: [
        { name: 'AzureWebJobsStorage', value: 'DefaultEndpointsProtocol=https;AccountName=${funcStorage.name};EndpointSuffix=core.windows.net;AccountKey=${funcStorage.listKeys().keys[0].value}' }
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'python' }
        { name: 'WEBSITE_VNET_ROUTE_ALL', value: '1' }
      ]
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
    }
    httpsOnly: true
  }
}

// ── Public IP for APIM ───────────────────────────────────────────────
resource apimPublicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: 'pip-apim-${suffix}'
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: 'apim-foundry-${suffix}-${uniqueString(resourceGroup().id)}'
    }
  }
}

// ── API Management (External mode - public inbound, private backend) ─
resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' = {
  name: 'apim-foundry-${suffix}-${uniqueString(resourceGroup().id)}'
  location: location
  sku: {
    name: 'Developer'
    capacity: 1
  }
  identity: { type: 'SystemAssigned' }
  properties: {
    publisherEmail: 'admin@foundrypoc.example'
    publisherName: 'Foundry POC'
    virtualNetworkType: 'External'
    publicIpAddressId: apimPublicIp.id
    virtualNetworkConfiguration: {
      subnetResourceId: backendVnet.properties.subnets[0].id
    }
  }
}

// ── Outputs ──────────────────────────────────────────────────────────
output apimGatewayUrl string = apim.properties.gatewayUrl
output apimPublicIp string = apimPublicIp.properties.ipAddress
output apimName string = apim.name
output functionAppName string = functionApp.name
output functionAppHostname string = functionApp.properties.defaultHostName
output backendVnetName string = backendVnet.name
output backendVnetId string = backendVnet.id
