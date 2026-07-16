<#
.SYNOPSIS
    Post-deployment configuration: deploys Function code, configures APIM APIs, creates the agent.

.DESCRIPTION
    Run AFTER backend-deploy-2 completes (APIM takes ~35 min).
    1. Deploys Function code (zip deploy)
    2. Configures APIM to route to the private Function
    3. Creates the Foundry Agent with AI Search + OpenAPI tool (via APIM)
#>

$ErrorActionPreference = "Stop"
$RG = "rg-foundry-byo-vnet"

Write-Host "`n===========================================`n" -ForegroundColor Cyan
Write-Host "  Post-Deployment Configuration" -ForegroundColor Cyan
Write-Host "`n===========================================`n" -ForegroundColor Cyan

# ─── Step 1: Verify deployments completed ───
Write-Host "[1/5] Verifying deployments..." -ForegroundColor Yellow

$mainDeploy = az deployment group show --resource-group $RG --name "foundry-byo-vnet-deploy" --query "properties.provisioningState" -o tsv 2>&1
$backendDeploy = az deployment group show --resource-group $RG --name "backend-deploy-2" --query "properties.provisioningState" -o tsv 2>&1

Write-Host "  Foundry infra:  $mainDeploy"
Write-Host "  Backend (APIM): $backendDeploy"

if ($backendDeploy -ne "Succeeded") {
    Write-Host "  ⏳ Backend still deploying. APIM Developer tier takes ~35 min." -ForegroundColor Yellow
    Write-Host "  Run this script again when deployment completes." -ForegroundColor Yellow
    exit 0
}
Write-Host "  ✅ Both deployments succeeded" -ForegroundColor Green

# ─── Step 2: Discover resources ───
Write-Host "`n[2/5] Discovering resources..." -ForegroundColor Yellow

$outputs = az deployment group show --resource-group $RG --name "backend-deploy-2" --query "properties.outputs" -o json | ConvertFrom-Json

$apimName = $outputs.apimName.value
$apimGatewayUrl = $outputs.apimGatewayUrl.value
$funcAppName = $outputs.functionAppName.value
$funcHostname = $outputs.functionAppHostname.value

$aiAccount = az cognitiveservices account list --resource-group $RG --query "[0].name" -o tsv
$searchService = az search service list --resource-group $RG --query "[0].name" -o tsv
$foundryEndpoint = az cognitiveservices account show --name $aiAccount --resource-group $RG --query "properties.endpoint" -o tsv 2>&1

Write-Host "  APIM Name:        $apimName" -ForegroundColor Cyan
Write-Host "  APIM Gateway:     $apimGatewayUrl" -ForegroundColor Cyan
Write-Host "  Function App:     $funcAppName" -ForegroundColor Cyan
Write-Host "  Function Host:    $funcHostname" -ForegroundColor Cyan
Write-Host "  Foundry Endpoint: $foundryEndpoint" -ForegroundColor Cyan

# ─── Step 3: Deploy Function code ───
Write-Host "`n[3/5] Deploying Function code..." -ForegroundColor Yellow

# Enable temporary public access on Function for zip deploy
az functionapp update --name $funcAppName --resource-group $RG --set publicNetworkAccess=Enabled --only-show-errors -o none 2>&1

Push-Location "C:\PrivateMicrosoftFoundryPOC\azure-function"
$zipPath = "C:\PrivateMicrosoftFoundryPOC\azure-function\function.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath }
Compress-Archive -Path host.json, requirements.txt, InventoryApi -DestinationPath $zipPath -Force
az functionapp deployment source config-zip --resource-group $RG --name $funcAppName --src $zipPath --only-show-errors 2>&1
Pop-Location

# Disable public access again
az functionapp update --name $funcAppName --resource-group $RG --set publicNetworkAccess=Disabled --only-show-errors -o none 2>&1

Write-Host "  ✅ Function code deployed, public access re-disabled" -ForegroundColor Green

# ─── Step 4: Configure APIM to route to private Function ───
Write-Host "`n[4/5] Configuring APIM API..." -ForegroundColor Yellow

# Import the OpenAPI spec into APIM, pointing backend to the Function's internal hostname
$funcBackendUrl = "https://$funcHostname/api"

# Create the API in APIM
az apim api import `
    --resource-group $RG `
    --service-name $apimName `
    --api-id "inventory-api" `
    --path "inventory" `
    --display-name "Inventory API" `
    --specification-format OpenApi `
    --specification-path "C:\PrivateMicrosoftFoundryPOC\azure-function\openapi.json" `
    --service-url $funcBackendUrl `
    --subscription-required false `
    --protocols https `
    --only-show-errors 2>&1

Write-Host "  ✅ APIM API configured: ${apimGatewayUrl}/inventory" -ForegroundColor Green
Write-Host "  Backend routes to: $funcBackendUrl (private, VNet internal)" -ForegroundColor Cyan

# ─── Step 5: Create the Foundry Agent ───
Write-Host "`n[5/5] Creating Foundry Agent..." -ForegroundColor Yellow

# Get search connection name from the project
$subscriptionId = az account show --query id -o tsv
$projects = az rest --method get `
    --url "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$aiAccount/projects?api-version=2025-04-01-preview" --only-show-errors `
    2>$null | ConvertFrom-Json
$projectName = $projects.value[0].name
$projectResourceId = "/subscriptions/$subscriptionId/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$aiAccount/projects/$projectName"

$connections = az rest --method get `
    --url "https://management.azure.com${projectResourceId}/connections?api-version=2025-04-01-preview" `
    --only-show-errors 2>$null | ConvertFrom-Json

$searchConnectionId = ""
foreach ($conn in $connections.value) {
    if ($conn.properties.category -eq "CognitiveSearch") {
        $searchConnectionId = $conn.properties.resourceId
        Write-Host "  Search Connection: $($conn.name)" -ForegroundColor Cyan
        break
    }
}

$env:PROJECT_ENDPOINT = $foundryEndpoint
$env:SEARCH_CONNECTION_NAME = $searchConnectionId
$env:APIM_GATEWAY_URL = $apimGatewayUrl
$env:MODEL_DEPLOYMENT = "gpt-4.1"

C:/Users/SystemAdministrator/AppData/Local/Programs/Python/Python314/python.exe C:\PrivateMicrosoftFoundryPOC\agent-setup\create_agent.py

# ─── Done ───
Write-Host "`n===========================================`n" -ForegroundColor Green
Write-Host "  ✅ POC Setup Complete!" -ForegroundColor Green
Write-Host "`n===========================================`n" -ForegroundColor Green
Write-Host ""
Write-Host "  Architecture:" -ForegroundColor Cyan
Write-Host "    VNet 1 (192.168.0.0/16): Foundry Agent + AI Search (private)" -ForegroundColor White
Write-Host "    VNet 2 (10.0.0.0/16):    APIM (public gateway) + Function (private)" -ForegroundColor White
Write-Host ""
Write-Host "  Endpoints:" -ForegroundColor Cyan
Write-Host "    Foundry: $foundryEndpoint" -ForegroundColor White
Write-Host "    APIM:    $apimGatewayUrl" -ForegroundColor White
Write-Host ""
Write-Host "  Test APIM endpoint:" -ForegroundColor Yellow
Write-Host "    curl ${apimGatewayUrl}/inventory/list" -ForegroundColor White
Write-Host ""
Write-Host "  To run the React UI:" -ForegroundColor Yellow
Write-Host "    cd C:\PrivateMicrosoftFoundryPOC\react-ui && npm install && npm start" -ForegroundColor White
Write-Host ""

# Save config
@{
    foundryEndpoint = $foundryEndpoint
    apimGatewayUrl  = $apimGatewayUrl
    apimName        = $apimName
    functionApp     = $funcAppName
    searchEndpoint  = "https://${searchService}.search.windows.net"
    vnet1           = "foundry-poc-vnet (192.168.0.0/16)"
    vnet2           = "backend-vnet-poc (10.0.0.0/16)"
    resourceGroup   = $RG
} | ConvertTo-Json | Set-Content "C:\PrivateMicrosoftFoundryPOC\poc-config.json"
Write-Host "  Config saved to poc-config.json" -ForegroundColor Green
