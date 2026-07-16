<#
.SYNOPSIS
    Run this on the Jump Box VM (via Bastion) to set up and create the agent.
    
.DESCRIPTION
    1. Installs Python packages
    2. Logs into Azure
    3. Verifies private DNS resolution (Function resolves to private IP)
    4. Creates the prompt agent with OpenAPI tool

.NOTES
    Connect to vm-jumpbox via Azure Bastion first.
    Username: azureadmin / Password: <SET-YOUR-VM-PASSWORD>
#>

Write-Host "`n=====================================" -ForegroundColor Cyan
Write-Host "  Jump Box VM - Agent Setup" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

$RG = "rg-foundry-byo-vnet"

# Step 1: Discover resource names and verify DNS
Write-Host "`n[1] Discovering resources..." -ForegroundColor Yellow
$aiAccount = az cognitiveservices account list --resource-group $RG --query "[0].name" -o tsv
$foundryHostname = "$aiAccount.cognitiveservices.azure.com"
$funcAppName = az functionapp list --resource-group $RG --query "[0].name" -o tsv
$funcHostname = az functionapp show --name $funcAppName --resource-group $RG --query "defaultHostName" -o tsv
Write-Host "  Foundry Account:  $aiAccount" -ForegroundColor Cyan
Write-Host "  Function App:     $funcAppName" -ForegroundColor Cyan
Write-Host "  Function Host:    $funcHostname" -ForegroundColor Cyan

Write-Host "`n[2] Verifying private DNS resolution..." -ForegroundColor Yellow
$dns = Resolve-DnsName $funcHostname -ErrorAction SilentlyContinue
if ($dns) {
    $ip = ($dns | Where-Object { $_.Type -eq 'A' }).IPAddress
    Write-Host "  ✅ Function resolves to: $ip (should be private IP)" -ForegroundColor Green
    Write-Host "  This proves DNS resolves via Private Endpoint inside VNet" -ForegroundColor Gray
} else {
    Write-Host "  ⚠️  DNS resolution pending — may need a moment" -ForegroundColor Yellow
}

$fdns = Resolve-DnsName $foundryHostname -ErrorAction SilentlyContinue
if ($fdns) {
    $fip = ($fdns | Where-Object { $_.Type -eq 'A' }).IPAddress
    Write-Host "  ✅ Foundry resolves to: $fip (should be private IP)" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  Foundry DNS resolution pending" -ForegroundColor Yellow
}

# Step 2: Test connectivity to the Function
Write-Host "`n[3] Testing Function API via private endpoint..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod "https://$funcHostname/api/inventory/list"
    Write-Host "  ✅ Function responds: $($response | ConvertTo-Json -Compress)" -ForegroundColor Green
    Write-Host "  Traffic path: VM (vm-subnet) → PE (pe-subnet) → Function (VNet 2, func-subnet)" -ForegroundColor Gray
} catch {
    Write-Host "  ❌ Function call failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  The Function may need a moment after PE creation. Try again in 1-2 min." -ForegroundColor Yellow
}

# Step 3: Install Python packages
Write-Host "`n[4] Installing Python packages..." -ForegroundColor Yellow
pip install azure-ai-projects azure-identity --quiet 2>$null
Write-Host "  ✅ Packages installed" -ForegroundColor Green

# Step 4: Login to Azure (if not already)
Write-Host "`n[5] Checking Azure login..." -ForegroundColor Yellow
$account = az account show --query name -o tsv 2>$null
if ($account) {
    Write-Host "  ✅ Logged in as: $account" -ForegroundColor Green
} else {
    Write-Host "  Running 'az login'..." -ForegroundColor Yellow
    az login
}

# Step 5: Set environment variables for the agent
Write-Host "`n[6] Setting agent environment..." -ForegroundColor Yellow
$env:PROJECT_ENDPOINT = az cognitiveservices account show --name $aiAccount --resource-group $RG --query "properties.endpoint" -o tsv
$env:FUNCTION_HOSTNAME = $funcHostname
$env:MODEL_DEPLOYMENT = "gpt-4.1"

# Get AI Search connection for Foundry IQ grounding
$subscriptionId = az account show --query id -o tsv
$projects = az rest --method get `
    --url "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$aiAccount/projects?api-version=2025-04-01-preview" --only-show-errors `
    2>$null | ConvertFrom-Json
$projectName = $projects.value[0].name
$projectResourceId = "/subscriptions/$subscriptionId/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$aiAccount/projects/$projectName"

$connections = az rest --method get `
    --url "https://management.azure.com${projectResourceId}/connections?api-version=2025-04-01-preview" `
    --only-show-errors 2>$null | ConvertFrom-Json
foreach ($conn in $connections.value) {
    if ($conn.properties.category -eq "CognitiveSearch") {
        $env:SEARCH_CONNECTION_ID = $conn.properties.resourceId
        Write-Host "  Search Connection: $($conn.name)" -ForegroundColor Cyan
        break
    }
}

Write-Host "  PROJECT_ENDPOINT:   $($env:PROJECT_ENDPOINT)" -ForegroundColor Cyan
Write-Host "  FUNCTION_HOSTNAME:  $($env:FUNCTION_HOSTNAME)" -ForegroundColor Cyan
Write-Host "  SEARCH_CONNECTION:  $($env:SEARCH_CONNECTION_ID)" -ForegroundColor Cyan

# Step 6: Create the grounded agent (Foundry IQ + Private Function)
Write-Host "`n[7] Creating the Grounded Procurement Agent..." -ForegroundColor Yellow
Write-Host "  → Foundry IQ (AI Search) for knowledge grounding" -ForegroundColor Gray
Write-Host "  → Private Function (VNet 2) for real-time inventory" -ForegroundColor Gray
python C:\PrivateMicrosoftFoundryPOC\agent-setup\create_grounded_agent.py --demo

Write-Host "`n=====================================" -ForegroundColor Green
Write-Host "  Done! Test in Azure AI Foundry Portal" -ForegroundColor Green
Write-Host "  (access from this VM via Edge browser)" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
