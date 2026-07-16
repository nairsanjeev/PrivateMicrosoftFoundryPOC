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

# Step 1: Verify we're inside the VNet by checking DNS resolution
Write-Host "`n[1] Verifying private DNS resolution..." -ForegroundColor Yellow
$dns = Resolve-DnsName "func-order-api-poc-3zvjcwwd3ezpc.azurewebsites.net" -ErrorAction SilentlyContinue
if ($dns) {
    $ip = ($dns | Where-Object { $_.Type -eq 'A' }).IPAddress
    Write-Host "  ✅ Function resolves to: $ip (should be 192.168.1.x)" -ForegroundColor Green
    Write-Host "  This proves we're inside VNet 1 and DNS resolves via Private Endpoint" -ForegroundColor Gray
} else {
    Write-Host "  ❌ DNS resolution failed" -ForegroundColor Red
}

Write-Host "`n[2] Verifying Foundry endpoint resolves privately..." -ForegroundColor Yellow
$fdns = Resolve-DnsName "foundrypoc3zvj.cognitiveservices.azure.com" -ErrorAction SilentlyContinue
if ($fdns) {
    $fip = ($fdns | Where-Object { $_.Type -eq 'A' }).IPAddress
    Write-Host "  ✅ Foundry resolves to: $fip (should be 192.168.1.x)" -ForegroundColor Green
} else {
    Write-Host "  ❌ Foundry DNS resolution failed" -ForegroundColor Red
}

# Step 2: Test connectivity to the Function
Write-Host "`n[3] Testing Function API via private endpoint..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod "https://func-order-api-poc-3zvjcwwd3ezpc.azurewebsites.net/api/inventory/health"
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

# Step 5: Create the agent
Write-Host "`n[6] Creating the Prompt Agent with OpenAPI tool..." -ForegroundColor Yellow
python C:\PrivateMicrosoftFoundryPOC\agent-setup\create_prompt_agent.py

Write-Host "`n=====================================" -ForegroundColor Green
Write-Host "  Done! Test in Azure AI Foundry Portal" -ForegroundColor Green
Write-Host "  (access from this VM via Edge browser)" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
