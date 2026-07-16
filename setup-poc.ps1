<#
.SYNOPSIS
    End-to-end setup script for Foundry BYO VNet POC.
    
.DESCRIPTION
    This script:
    1. Waits for the Foundry infrastructure deployment to complete
    2. Discovers deployed resource names
    3. Deploys the Azure Function into the MCP subnet
    4. Sets up the AI Search knowledge base
    5. Creates the Foundry Agent
    6. Outputs all configuration needed for the React UI

.NOTES
    Run from the C:\PrivateMicrosoftFoundryPOC directory.
    Requires: Azure CLI, Python 3.10+, pip
#>

$ErrorActionPreference = "Stop"
$RG = "rg-foundry-byo-vnet"
$LOCATION = "swedencentral"
$TEMPLATE_DIR = "C:\PrivateMicrosoftFoundryPOC\foundry-samples\infrastructure\infrastructure-setup-bicep\19-private-network-agent-tools"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Foundry BYO VNet POC - Setup Script" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ─── Step 1: Check if infrastructure deployment is complete ───
Write-Host "[1/6] Checking infrastructure deployment status..." -ForegroundColor Yellow

$deployStatus = az deployment group show `
    --resource-group $RG `
    --name "foundry-byo-vnet-deploy" `
    --query "properties.provisioningState" `
    -o tsv 2>$null

if ($deployStatus -ne "Succeeded") {
    Write-Host "  ⏳ Deployment status: $deployStatus" -ForegroundColor Yellow
    Write-Host "  Waiting for deployment to complete (this can take 15-25 minutes)..." -ForegroundColor Yellow
    
    az deployment group wait `
        --resource-group $RG `
        --name "foundry-byo-vnet-deploy" `
        --created 2>$null
    
    $deployStatus = az deployment group show `
        --resource-group $RG `
        --name "foundry-byo-vnet-deploy" `
        --query "properties.provisioningState" `
        -o tsv
    
    if ($deployStatus -ne "Succeeded") {
        Write-Host "  ❌ Deployment failed with status: $deployStatus" -ForegroundColor Red
        Write-Host "  Check the deployment error:" -ForegroundColor Red
        az deployment group show --resource-group $RG --name "foundry-byo-vnet-deploy" --query "properties.error" -o json
        exit 1
    }
}
Write-Host "  ✅ Infrastructure deployment: $deployStatus" -ForegroundColor Green

# ─── Step 2: Discover deployed resources ───
Write-Host "`n[2/6] Discovering deployed resources..." -ForegroundColor Yellow

$outputs = az deployment group show `
    --resource-group $RG `
    --name "foundry-byo-vnet-deploy" `
    --query "properties.outputs" `
    -o json | ConvertFrom-Json

# Get resource names from the RG
$aiAccount = az cognitiveservices account list --resource-group $RG --query "[0].name" -o tsv
$aiAccountEndpoint = az cognitiveservices account show --name $aiAccount --resource-group $RG --query "properties.endpoint" -o tsv
$searchService = az search service list --resource-group $RG --query "[0].name" -o tsv
$searchEndpoint = "https://$searchService.search.windows.net"
$storageAccount = az storage account list --resource-group $RG --query "[0].name" -o tsv
$vnetName = az network vnet list --resource-group $RG --query "[0].name" -o tsv
$cosmosAccount = az cosmosdb list --resource-group $RG --query "[0].name" -o tsv

# Get project endpoint
$projectEndpoint = az cognitiveservices account show --name $aiAccount --resource-group $RG `
    --query "properties.endpoints['AI Foundry Portal']" -o tsv 2>$null

# List projects
$projects = az rest --method get `
    --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$aiAccount/projects?api-version=2025-04-01-preview" --only-show-errors `
    2>$null | ConvertFrom-Json

$projectName = $projects.value[0].name
$projectResourceId = $projects.value[0].id

Write-Host "  AI Account: $aiAccount" -ForegroundColor Cyan
Write-Host "  AI Search:  $searchService" -ForegroundColor Cyan
Write-Host "  Storage:    $storageAccount" -ForegroundColor Cyan
Write-Host "  VNet:       $vnetName" -ForegroundColor Cyan
Write-Host "  Cosmos DB:  $cosmosAccount" -ForegroundColor Cyan
Write-Host "  Project:    $projectName" -ForegroundColor Cyan

# ─── Step 3: Deploy Azure Function into MCP subnet ───
Write-Host "`n[3/6] Deploying Azure Function into MCP subnet..." -ForegroundColor Yellow

$funcAppName = "func-inventory-${aiAccount}"
# Truncate to 60 chars max for function app name
if ($funcAppName.Length -gt 60) {
    $funcAppName = $funcAppName.Substring(0, 60)
}

az deployment group create `
    --resource-group $RG `
    --template-file "C:\PrivateMicrosoftFoundryPOC\azure-function\deploy-function.bicep" `
    --parameters `
        functionAppName=$funcAppName `
        vnetName=$vnetName `
        mcpSubnetName="mcp-subnet" `
        peSubnetName="pe-subnet" `
        storageAccountName=$storageAccount `
        location=$LOCATION `
    --name "func-deploy" `
    --only-show-errors

$funcHostname = az functionapp show --name $funcAppName --resource-group $RG --query "defaultHostName" -o tsv
$funcUrl = "https://$funcHostname"
Write-Host "  ✅ Function App: $funcAppName" -ForegroundColor Green
Write-Host "  URL: $funcUrl" -ForegroundColor Cyan

# Deploy function code via zip deploy
Write-Host "  Deploying function code..." -ForegroundColor Yellow
Push-Location "C:\PrivateMicrosoftFoundryPOC\azure-function"
$zipPath = "C:\PrivateMicrosoftFoundryPOC\azure-function\function.zip"
Compress-Archive -Path host.json, requirements.txt, InventoryApi -DestinationPath $zipPath -Force
az functionapp deployment source config-zip --resource-group $RG --name $funcAppName --src $zipPath --only-show-errors
Pop-Location
Write-Host "  ✅ Function code deployed" -ForegroundColor Green

# ─── Step 4: Set up AI Search knowledge base ───
Write-Host "`n[4/6] Setting up AI Search knowledge base..." -ForegroundColor Yellow

# Install Python deps
pip install azure-search-documents azure-identity azure-ai-projects flask --quiet 2>$null

$env:SEARCH_ENDPOINT = $searchEndpoint
python C:\PrivateMicrosoftFoundryPOC\agent-setup\setup_knowledge_base.py

Write-Host "  ✅ Knowledge base indexed" -ForegroundColor Green

# ─── Step 5: Get connection details and create agent ───
Write-Host "`n[5/6] Creating Foundry Agent..." -ForegroundColor Yellow

# Get the project endpoint for SDK
$sdkEndpoint = az cognitiveservices account show --name $aiAccount --resource-group $RG `
    --query "properties.endpoint" -o tsv

# Find the AI Search connection name
$searchConnectionName = ""
try {
    $connections = az rest --method get `
        --url "https://management.azure.com${projectResourceId}/connections?api-version=2025-04-01-preview" `
        2>$null | ConvertFrom-Json
    
    foreach ($conn in $connections.value) {
        if ($conn.properties.category -eq "CognitiveSearch") {
            $searchConnectionName = $conn.name
            break
        }
    }
} catch {
    Write-Host "  ⚠ Could not find search connection automatically" -ForegroundColor Yellow
}

Write-Host "  Project Endpoint: $sdkEndpoint" -ForegroundColor Cyan
Write-Host "  Search Connection: $searchConnectionName" -ForegroundColor Cyan

$env:PROJECT_ENDPOINT = $sdkEndpoint
$env:SEARCH_CONNECTION_NAME = $searchConnectionName
$env:FUNCTION_APP_URL = $funcUrl
$env:MODEL_DEPLOYMENT = "gpt-4.1"

python C:\PrivateMicrosoftFoundryPOC\agent-setup\create_agent.py

# ─── Step 6: Output configuration ───
Write-Host "`n[6/6] Setup Complete!" -ForegroundColor Green
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Configuration for React UI" -ForegroundColor Cyan  
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Project Endpoint: $sdkEndpoint" -ForegroundColor White
Write-Host "  Function URL:     $funcUrl" -ForegroundColor White
Write-Host ""
Write-Host "  To start the React UI:" -ForegroundColor Yellow
Write-Host "    cd C:\PrivateMicrosoftFoundryPOC\react-ui" -ForegroundColor White
Write-Host "    npm install && npm run build" -ForegroundColor White
Write-Host "    cd C:\PrivateMicrosoftFoundryPOC" -ForegroundColor White
Write-Host "    python server.py" -ForegroundColor White
Write-Host ""
Write-Host "  Then open http://localhost:3001 and enter:" -ForegroundColor Yellow
Write-Host "    Project Endpoint: $sdkEndpoint" -ForegroundColor White
Write-Host "    Agent ID: (from the agent creation output above)" -ForegroundColor White
Write-Host ""

# Save config to file
@{
    projectEndpoint = $sdkEndpoint
    functionAppUrl  = $funcUrl
    searchEndpoint  = $searchEndpoint
    searchConnection = $searchConnectionName
    vnetName        = $vnetName
    resourceGroup   = $RG
    aiAccount       = $aiAccount
} | ConvertTo-Json | Set-Content "C:\PrivateMicrosoftFoundryPOC\poc-config.json"

Write-Host "  Config saved to: C:\PrivateMicrosoftFoundryPOC\poc-config.json" -ForegroundColor Green
