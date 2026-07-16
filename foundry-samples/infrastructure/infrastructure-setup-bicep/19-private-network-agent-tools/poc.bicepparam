using './main.bicep'

// -----------------------------------------------------------------------------
// Foundry account & project
// -----------------------------------------------------------------------------
param location = 'swedencentral'
param aiServices = 'foundrypoc'
param firstProjectName = 'byovnet-poc'
param projectDescription = 'Foundry BYO VNet POC with AI Search grounding and Azure Function tools'
param displayName = 'BYO VNet POC Project'

// -----------------------------------------------------------------------------
// Model deployment - using gpt-4.1 for better agent capabilities
// -----------------------------------------------------------------------------
param modelName = 'gpt-4.1'
param modelFormat = 'OpenAI'
param modelVersion = '2025-04-14'
param modelSkuName = 'GlobalStandard'
param modelCapacity = 30

// -----------------------------------------------------------------------------
// Networking - new VNet with three subnets
// -----------------------------------------------------------------------------
param vnetName = 'foundry-poc-vnet'
param agentSubnetName = 'agent-subnet'
param peSubnetName = 'pe-subnet'
param mcpSubnetName = 'mcp-subnet'

param vnetAddressPrefix = '192.168.0.0/16'
param agentSubnetPrefix = '192.168.0.0/24'
param peSubnetPrefix    = '192.168.1.0/24'
param mcpSubnetPrefix   = '192.168.2.0/24'

param existingVnetResourceId = ''
param existingAgentSubnetResourceId = ''
param existingPeSubnetResourceId    = ''
param existingMcpSubnetResourceId   = ''

// -----------------------------------------------------------------------------
// Create all backing resources fresh
// -----------------------------------------------------------------------------
param existingAiSearchResourceId = ''
param existingAzureStorageAccountResourceId = ''
param existingAzureCosmosDBAccountResourceId = ''
param existingFabricWorkspaceResourceId = ''

// -----------------------------------------------------------------------------
// DNS zones - create all new
// -----------------------------------------------------------------------------
param existingDnsZones = {
  'privatelink.services.ai.azure.com':       { subscriptionId: '', resourceGroup: '' }
  'privatelink.openai.azure.com':            { subscriptionId: '', resourceGroup: '' }
  'privatelink.cognitiveservices.azure.com': { subscriptionId: '', resourceGroup: '' }
  'privatelink.search.windows.net':          { subscriptionId: '', resourceGroup: '' }
  'privatelink.blob.core.windows.net':       { subscriptionId: '', resourceGroup: '' }
  'privatelink.documents.azure.com':         { subscriptionId: '', resourceGroup: '' }
  'privatelink.azurecr.io':                  { subscriptionId: '', resourceGroup: '' }
  'privatelink.fabric.microsoft.com':        { subscriptionId: '', resourceGroup: '' }
}
