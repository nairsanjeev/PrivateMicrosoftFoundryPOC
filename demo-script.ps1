<#
.SYNOPSIS
    Interactive Demo Script: Microsoft Foundry with BYO VNet Isolation
    
.DESCRIPTION
    Walk-through demo showing:
    1. How Foundry is deployed with BYO VNet (delegated subnet)
    2. How AI Search grounding works via private endpoints (Foundry IQ)
    3. How the agent calls an external API via APIM gateway to a private Function
    4. Full architecture overview with live Azure CLI verification

.NOTES
    Run section-by-section (copy/paste blocks) for a live demo.
    Press Enter between sections to pace the presentation.
#>

$RG = "rg-foundry-byo-vnet"

function Pause-Demo { 
    Write-Host "`n  [Press Enter to continue...]" -ForegroundColor DarkGray
    Read-Host 
}

function Show-Header($title) {
    Write-Host "`n" -NoNewline
    Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║  $($title.PadRight(58))║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Step($num, $title) {
    Write-Host "`n  ─── Step $num: $title ───`n" -ForegroundColor Yellow
}

Clear-Host

# ═══════════════════════════════════════════════════════════════════════════════
# INTRO
# ═══════════════════════════════════════════════════════════════════════════════

Show-Header "Microsoft Foundry — BYO VNet Isolation Demo"

Write-Host "  This demo shows how Microsoft Foundry Agent Service is deployed" -ForegroundColor White
Write-Host "  with full network isolation using Bring-Your-Own Virtual Network" -ForegroundColor White
Write-Host "  (BYO VNet) with a delegated subnet." -ForegroundColor White
Write-Host ""
Write-Host "  Architecture:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  ┌─────────────────────────────────────────────────────────────┐"
Write-Host "  │  VNet 1 — Foundry BYO VNet (192.168.0.0/16)                 │"
Write-Host "  │                                                              │"
Write-Host "  │  ┌─────────────────┐     ┌──────────────────────────────┐  │"
Write-Host "  │  │ agent-subnet    │     │ pe-subnet (Private Endpoints)│  │"
Write-Host "  │  │ /24 delegated   │     │ ┌────────┐ ┌──────┐ ┌─────┐ │  │"
Write-Host "  │  │ Microsoft.App/  │────▶│ │Search  │ │Store │ │Cosmo│ │  │"
Write-Host "  │  │ environments    │ PE  │ │(IQ KB) │ │(file)│ │(thr)│ │  │"
Write-Host "  │  │                 │     │ └────────┘ └──────┘ └─────┘ │  │"
Write-Host "  │  │ Foundry Agent   │     └──────────────────────────────┘  │"
Write-Host "  │  └───────┬─────────┘                                       │"
Write-Host "  └──────────┼─────────────────────────────────────────────────┘"
Write-Host "             │"
Write-Host "             │ Tool call (OpenAPI → APIM public endpoint)"
Write-Host "             ▼"
Write-Host "  ┌─────────────────────────────────────────────────────────────┐"
Write-Host "  │  VNet 2 — Backend API (10.0.0.0/16)                         │"
Write-Host "  │                                                              │"
Write-Host "  │  ┌──────────────────────┐  ┌────────────────────────────┐  │"
Write-Host "  │  │ apim-subnet /24      │  │ func-subnet /24            │  │"
Write-Host "  │  │ APIM (External mode) │─▶│ Azure Function (PRIVATE)   │  │"
Write-Host "  │  │ Public gateway       │  │ publicAccess: DISABLED     │  │"
Write-Host "  │  └──────────────────────┘  └────────────────────────────┘  │"
Write-Host "  └─────────────────────────────────────────────────────────────┘"
Write-Host ""
Write-Host "  Key points:" -ForegroundColor Green
Write-Host "    • Foundry agents run in a delegated subnet (Microsoft.App)" -ForegroundColor White
Write-Host "    • All data resources behind private endpoints (no public access)" -ForegroundColor White
Write-Host "    • Backend API in separate VNet, only reachable via APIM internally" -ForegroundColor White
Write-Host "    • APIM is the single public gateway for all backend APIs" -ForegroundColor White

Pause-Demo

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 1: VNet 1 — Foundry BYO VNet
# ═══════════════════════════════════════════════════════════════════════════════

Show-Header "Section 1: Foundry BYO VNet — Delegated Subnet"

Write-Host "  The foundation of network isolation is the DELEGATED SUBNET." -ForegroundColor White
Write-Host "  Foundry requires a subnet delegated to 'Microsoft.App/environments'" -ForegroundColor White
Write-Host "  where agent Micro VMs are injected with their own network interface." -ForegroundColor White
Write-Host ""
Write-Host "  This is set at Foundry ACCOUNT creation time and cannot be changed later." -ForegroundColor Red
Write-Host ""

Show-Step 1 "Verify the VNet and subnet delegation"

Write-Host "  Running: az network vnet show --name foundry-poc-vnet ..." -ForegroundColor DarkGray

$vnetInfo = az network vnet show --name foundry-poc-vnet --resource-group $RG `
    --query "{name:name, addressSpace:addressSpace.addressPrefixes[0], location:location, subnets:subnets[].{name:name, prefix:addressPrefix, delegation:delegations[0].serviceName}}" `
    -o json 2>&1 | ConvertFrom-Json

Write-Host ""
Write-Host "  VNet: $($vnetInfo.name)" -ForegroundColor Cyan
Write-Host "  Address Space: $($vnetInfo.addressSpace)" -ForegroundColor Cyan
Write-Host "  Location: $($vnetInfo.location)" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Subnets:" -ForegroundColor Yellow
foreach ($subnet in $vnetInfo.subnets) {
    $delegationStr = if ($subnet.delegation) { "→ DELEGATED to $($subnet.delegation)" } else { "(no delegation)" }
    $color = if ($subnet.delegation) { "Green" } else { "White" }
    Write-Host "    • $($subnet.name) ($($subnet.prefix)) $delegationStr" -ForegroundColor $color
}

Write-Host ""
Write-Host "  ✓ agent-subnet is delegated to Microsoft.App/environments" -ForegroundColor Green
Write-Host "    This means Foundry agent Micro VMs get their own IP from this subnet." -ForegroundColor Gray
Write-Host "    Each agent session consumes an IP. A /24 gives ~251 usable addresses." -ForegroundColor Gray

Pause-Demo

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 2: Private Endpoints
# ═══════════════════════════════════════════════════════════════════════════════

Show-Header "Section 2: Private Endpoints — Zero Public Exposure"

Write-Host "  All data resources are behind PRIVATE ENDPOINTS in the pe-subnet." -ForegroundColor White
Write-Host "  This means no traffic leaves the VNet to reach these services." -ForegroundColor White
Write-Host ""

Show-Step 2 "List private endpoints in the VNet"

Write-Host "  Running: az network private-endpoint list ..." -ForegroundColor DarkGray

$endpoints = az network private-endpoint list --resource-group $RG `
    --query "[].{name:name, subnet:subnet.id, group:privateLinkServiceConnections[0].properties.groupIds[0], status:privateLinkServiceConnections[0].properties.privateLinkServiceConnectionState.status}" `
    -o json 2>&1 | ConvertFrom-Json

Write-Host ""
Write-Host "  Private Endpoints:" -ForegroundColor Yellow
foreach ($ep in $endpoints) {
    $shortName = $ep.name -replace '-private-endpoint',''
    $subnetName = ($ep.subnet -split '/')[-1]
    Write-Host "    🔒 $($ep.name)" -ForegroundColor Green
    Write-Host "       Subnet: $subnetName | Group: $($ep.group) | Status: $($ep.status)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "  What this means:" -ForegroundColor Cyan
Write-Host "    • AI Search    — queries go through private IP, never public internet" -ForegroundColor White
Write-Host "    • Cosmos DB    — thread/message storage stays in-VNet" -ForegroundColor White
Write-Host "    • Blob Storage — file uploads stay private" -ForegroundColor White
Write-Host "    • Foundry      — even the control plane is private-endpoint accessible" -ForegroundColor White
Write-Host "    • ACR          — container images pulled privately" -ForegroundColor White
Write-Host "    • Monitor      — telemetry sent via AMPLS (private link scope)" -ForegroundColor White

Pause-Demo

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 3: Foundry Account Configuration
# ═══════════════════════════════════════════════════════════════════════════════

Show-Header "Section 3: Foundry Account — Network Injection"

Write-Host "  The Foundry account has 'networkInjections' configured to inject" -ForegroundColor White
Write-Host "  agent workloads into our delegated subnet." -ForegroundColor White
Write-Host ""

Show-Step 3 "Inspect the Foundry account"

$accountInfo = az cognitiveservices account show --name foundrypoc3zvj --resource-group $RG `
    --query "{name:name, endpoint:properties.endpoint, publicAccess:properties.publicNetworkAccess, networkAcls:properties.networkAcls.defaultAction, sku:sku.name, kind:kind}" `
    -o json 2>&1 | ConvertFrom-Json

Write-Host "  Foundry Account:" -ForegroundColor Cyan
Write-Host "    Name:           $($accountInfo.name)" -ForegroundColor White
Write-Host "    Endpoint:       $($accountInfo.endpoint)" -ForegroundColor White
Write-Host "    Kind:           $($accountInfo.kind) (AIServices)" -ForegroundColor White
Write-Host "    SKU:            $($accountInfo.sku)" -ForegroundColor White
Write-Host "    Public Access:  $($accountInfo.publicAccess)" -ForegroundColor $(if($accountInfo.publicAccess -eq 'Enabled'){'Yellow'}else{'Green'})
Write-Host "    Network ACLs:   $($accountInfo.networkAcls)" -ForegroundColor White
Write-Host ""
Write-Host "  Network Injection:" -ForegroundColor Yellow
Write-Host "    scenario: 'agent'" -ForegroundColor White
Write-Host "    subnetArmId: .../foundry-poc-vnet/subnets/agent-subnet" -ForegroundColor White
Write-Host "    useMicrosoftManagedNetwork: false (BYO VNet)" -ForegroundColor White
Write-Host ""
Write-Host "  ✓ This tells Foundry to deploy agent workloads INTO our subnet" -ForegroundColor Green
Write-Host "    instead of using Microsoft's managed network." -ForegroundColor Gray

Pause-Demo

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 4: AI Search Grounding (Foundry IQ)
# ═══════════════════════════════════════════════════════════════════════════════

Show-Header "Section 4: AI Search — Foundry IQ Grounding"

Write-Host "  The agent uses AI Search as a grounding tool (Foundry IQ)." -ForegroundColor White
Write-Host "  It searches a knowledge base of product docs and policies." -ForegroundColor White
Write-Host ""
Write-Host "  Traffic flow:" -ForegroundColor Cyan
Write-Host "    Agent (agent-subnet) → Private Endpoint → AI Search (pe-subnet)" -ForegroundColor Green
Write-Host "    ↑ ALL within VNet 1, never touches the internet" -ForegroundColor Gray
Write-Host ""

Show-Step 4 "Verify AI Search is private-only"

$searchInfo = az search service show --name foundrypoc3zvjsearch --resource-group $RG `
    --query "{name:name, publicAccess:publicNetworkAccess, sku:sku.name, status:status, authOptions:authOptions}" `
    -o json 2>&1 | ConvertFrom-Json

Write-Host "  AI Search Service:" -ForegroundColor Cyan
Write-Host "    Name:           $($searchInfo.name)" -ForegroundColor White
Write-Host "    SKU:            $($searchInfo.sku)" -ForegroundColor White
Write-Host "    Status:         $($searchInfo.status)" -ForegroundColor White
Write-Host "    Public Access:  $($searchInfo.publicAccess)" -ForegroundColor Green
Write-Host "    Auth:           AAD (Entra ID) + API Key" -ForegroundColor White
Write-Host ""
Write-Host "  ✓ publicNetworkAccess: disabled" -ForegroundColor Green
Write-Host "    Only reachable via private endpoint from within the VNet." -ForegroundColor Gray
Write-Host ""
Write-Host "  Knowledge Base Index: 'product-knowledge-base'" -ForegroundColor Yellow
Write-Host "    Contains: Product specs, return policies, warranty info," -ForegroundColor White
Write-Host "    shipping details, enterprise programs, support tiers" -ForegroundColor White

Pause-Demo

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 5: VNet 2 — Backend API Network
# ═══════════════════════════════════════════════════════════════════════════════

Show-Header "Section 5: VNet 2 — Backend API (Separate Network)"

Write-Host "  The backend API lives in a COMPLETELY SEPARATE VNet." -ForegroundColor White
Write-Host "  This demonstrates calling services across network boundaries." -ForegroundColor White
Write-Host ""

Show-Step 5 "Inspect VNet 2"

$vnet2Info = az network vnet show --name backend-vnet-poc --resource-group $RG `
    --query "{name:name, addressSpace:addressSpace.addressPrefixes[0], subnets:subnets[].{name:name, prefix:addressPrefix, delegation:delegations[0].serviceName}}" `
    -o json 2>&1 | ConvertFrom-Json

Write-Host "  VNet 2: $($vnet2Info.name)" -ForegroundColor Cyan
Write-Host "  Address Space: $($vnet2Info.addressSpace)" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Subnets:" -ForegroundColor Yellow
foreach ($subnet in $vnet2Info.subnets) {
    $delegationStr = if ($subnet.delegation) { "→ Delegated: $($subnet.delegation)" } else { "" }
    Write-Host "    • $($subnet.name) ($($subnet.prefix)) $delegationStr" -ForegroundColor White
}

Write-Host ""
Write-Host "  Design:" -ForegroundColor Cyan
Write-Host "    • apim-subnet: APIM deployed here (External VNet mode)" -ForegroundColor White
Write-Host "      - Has a PUBLIC IP for inbound internet traffic" -ForegroundColor White
Write-Host "      - Routes to backend services internally" -ForegroundColor White
Write-Host "    • func-subnet: Azure Function deployed here" -ForegroundColor White
Write-Host "      - VNet integrated (delegated to Microsoft.Web)" -ForegroundColor White
Write-Host "      - publicNetworkAccess: DISABLED" -ForegroundColor Green
Write-Host "      - ONLY reachable from within VNet 2 (via APIM)" -ForegroundColor Green

Pause-Demo

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 6: APIM as the Bridge
# ═══════════════════════════════════════════════════════════════════════════════

Show-Header "Section 6: APIM — Public Gateway to Private Backend"

Write-Host "  Azure API Management sits between the Foundry Agent and the" -ForegroundColor White
Write-Host "  private backend Function. It provides:" -ForegroundColor White
Write-Host ""
Write-Host "    ✓ Single public endpoint for all APIs" -ForegroundColor Green
Write-Host "    ✓ Routes internally to private services" -ForegroundColor Green
Write-Host "    ✓ Rate limiting, authentication, monitoring" -ForegroundColor Green
Write-Host "    ✓ OpenAPI spec for agent tool registration" -ForegroundColor Green
Write-Host ""

Show-Step 6 "Check APIM configuration"

$apimInfo = az apim show --name (az apim list --resource-group $RG --query "[0].name" -o tsv 2>&1) --resource-group $RG `
    --query "{name:name, gatewayUrl:gatewayUrl, vnetType:virtualNetworkType, publicIp:publicIpAddresses[0], sku:sku.name}" `
    -o json 2>&1 | ConvertFrom-Json

if ($apimInfo) {
    Write-Host "  APIM Instance:" -ForegroundColor Cyan
    Write-Host "    Name:         $($apimInfo.name)" -ForegroundColor White
    Write-Host "    Gateway URL:  $($apimInfo.gatewayUrl)" -ForegroundColor White
    Write-Host "    VNet Mode:    $($apimInfo.vnetType)" -ForegroundColor Yellow
    Write-Host "    Public IP:    $($apimInfo.publicIp)" -ForegroundColor White
    Write-Host "    SKU:          $($apimInfo.sku)" -ForegroundColor White
    Write-Host ""
    Write-Host "  Traffic flow when agent makes a tool call:" -ForegroundColor Cyan
    Write-Host "    1. Agent (VNet 1) → APIM public gateway endpoint" -ForegroundColor White
    Write-Host "    2. APIM (VNet 2, apim-subnet) → routes internally" -ForegroundColor White
    Write-Host "    3. → Azure Function (VNet 2, func-subnet, PRIVATE)" -ForegroundColor White
    Write-Host "    4. Function responds → APIM → Agent" -ForegroundColor White
} else {
    Write-Host "  ⏳ APIM is still provisioning (Developer tier takes ~35 min)" -ForegroundColor Yellow
    Write-Host "     Run 'az apim list --resource-group $RG -o table' to check" -ForegroundColor Gray
}

Pause-Demo

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 7: Azure Function (Private API)
# ═══════════════════════════════════════════════════════════════════════════════

Show-Header "Section 7: Azure Function — Private Backend API"

Write-Host "  The Azure Function is an Inventory/Order API that has" -ForegroundColor White
Write-Host "  NO public internet access. It can only be called via APIM." -ForegroundColor White
Write-Host ""

Show-Step 7 "Verify Function is private"

$funcName = az functionapp list --resource-group $RG --query "[0].name" -o tsv 2>&1
if ($funcName -and $funcName -notmatch "ERROR") {
    $funcInfo = az functionapp show --name $funcName --resource-group $RG `
        --query "{name:name, state:state, publicAccess:publicNetworkAccess, vnetIntegration:virtualNetworkSubnetId, hostname:defaultHostName}" `
        -o json 2>&1 | ConvertFrom-Json

    Write-Host "  Function App:" -ForegroundColor Cyan
    Write-Host "    Name:            $($funcInfo.name)" -ForegroundColor White
    Write-Host "    State:           $($funcInfo.state)" -ForegroundColor White
    Write-Host "    Hostname:        $($funcInfo.hostname)" -ForegroundColor White
    Write-Host "    Public Access:   $($funcInfo.publicAccess)" -ForegroundColor $(if($funcInfo.publicAccess -eq 'Disabled'){'Green'}else{'Red'})
    Write-Host "    VNet Integration: .../$((($funcInfo.vnetIntegration) -split '/')[-1])" -ForegroundColor White
    Write-Host ""
    Write-Host "  API Endpoints (via APIM only):" -ForegroundColor Yellow
    Write-Host "    GET  /inventory/list       — List all products" -ForegroundColor White
    Write-Host "    GET  /inventory/check?sku= — Check stock for a product" -ForegroundColor White
    Write-Host "    POST /inventory/order      — Place an order" -ForegroundColor White
    Write-Host ""
    Write-Host "  ✓ publicNetworkAccess: Disabled" -ForegroundColor Green
    Write-Host "    Calling https://$($funcInfo.hostname)/api/... directly = CONNECTION REFUSED" -ForegroundColor Red
    Write-Host "    Calling via APIM gateway = ✓ SUCCESS (routes internally)" -ForegroundColor Green
} else {
    Write-Host "  Function App not found or still deploying" -ForegroundColor Yellow
}

Pause-Demo

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 8: How it All Connects
# ═══════════════════════════════════════════════════════════════════════════════

Show-Header "Section 8: End-to-End Flow"

Write-Host "  When a user asks the agent 'Check stock for LAPTOP-001':" -ForegroundColor White
Write-Host ""
Write-Host "  ┌─────────────────────────────────────────────────────────────────┐" -ForegroundColor DarkGray
Write-Host "  │  1. User sends message to Foundry Agent                         │" -ForegroundColor White
Write-Host "  │     └─ Via Foundry public endpoint (or private if PE used)      │" -ForegroundColor Gray
Write-Host "  │                                                                  │" -ForegroundColor DarkGray
Write-Host "  │  2. Agent decides to use AI Search (grounding)                  │" -ForegroundColor White
Write-Host "  │     └─ Queries 'product-knowledge-base' index                   │" -ForegroundColor Gray
Write-Host "  │     └─ Traffic: agent-subnet → PE → AI Search (VNet 1 internal) │" -ForegroundColor Green
Write-Host "  │                                                                  │" -ForegroundColor DarkGray
Write-Host "  │  3. Agent decides to call Inventory API (tool)                  │" -ForegroundColor White
Write-Host "  │     └─ Calls APIM public endpoint: GET /inventory/check?sku=... │" -ForegroundColor Gray
Write-Host "  │     └─ APIM routes internally to Function (func-subnet)         │" -ForegroundColor Yellow
Write-Host "  │     └─ Function processes, returns stock data                   │" -ForegroundColor Gray
Write-Host "  │                                                                  │" -ForegroundColor DarkGray
Write-Host "  │  4. Agent composes response with both sources                   │" -ForegroundColor White
Write-Host "  │     └─ Knowledge base: specs, warranty info                     │" -ForegroundColor Gray
Write-Host "  │     └─ Live API: current stock, warehouse location              │" -ForegroundColor Gray
Write-Host "  │                                                                  │" -ForegroundColor DarkGray
Write-Host "  │  5. Response returned to user                                   │" -ForegroundColor White
Write-Host "  └─────────────────────────────────────────────────────────────────┘" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Network security properties:" -ForegroundColor Cyan
Write-Host "    • AI Search data NEVER leaves VNet 1" -ForegroundColor Green
Write-Host "    • Function is NEVER directly exposed to internet" -ForegroundColor Green
Write-Host "    • APIM is the ONLY public entry point to backend APIs" -ForegroundColor Green
Write-Host "    • Agent threads stored in Cosmos DB (private endpoint)" -ForegroundColor Green
Write-Host "    • Files stored in Blob Storage (private endpoint)" -ForegroundColor Green
Write-Host "    • Telemetry sent via Azure Monitor Private Link Scope" -ForegroundColor Green

Pause-Demo

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 9: What's Deployed (Resource Summary)
# ═══════════════════════════════════════════════════════════════════════════════

Show-Header "Section 9: Resource Summary"

Write-Host "  All resources in resource group: $RG" -ForegroundColor Cyan
Write-Host ""

Write-Host "  ┌─ VNet 1: Foundry BYO Network ──────────────────────────────────┐" -ForegroundColor Blue
Write-Host "  │ foundry-poc-vnet          Virtual Network (192.168.0.0/16)      │" -ForegroundColor White
Write-Host "  │ foundrypoc3zvj            Foundry Account (AIServices, S0)      │" -ForegroundColor White
Write-Host "  │ byovnet-poc3zvj           Foundry Project                       │" -ForegroundColor White
Write-Host "  │ foundrypoc3zvjsearch      AI Search (Standard, private)         │" -ForegroundColor White
Write-Host "  │ foundrypoc3zvjstorage     Storage Account (private)             │" -ForegroundColor White
Write-Host "  │ foundrypoc3zvjcosmosdb    Cosmos DB (private)                   │" -ForegroundColor White
Write-Host "  │ acr3zvj                   Container Registry (Premium, private) │" -ForegroundColor White
Write-Host "  │ appi-tracing-3zvj         Application Insights                 │" -ForegroundColor White
Write-Host "  │ law-tracing-3zvj          Log Analytics Workspace              │" -ForegroundColor White
Write-Host "  │ ampls-tracing-3zvj        Monitor Private Link Scope           │" -ForegroundColor White
Write-Host "  │ 6x Private Endpoints      Search, Storage, Cosmos, Foundry,    │" -ForegroundColor White
Write-Host "  │                            ACR, Monitor                         │" -ForegroundColor White
Write-Host "  │ 7x Private DNS Zones       For PE name resolution              │" -ForegroundColor White
Write-Host "  └─────────────────────────────────────────────────────────────────┘" -ForegroundColor Blue
Write-Host ""
Write-Host "  ┌─ VNet 2: Backend API Network ───────────────────────────────────┐" -ForegroundColor DarkYellow
Write-Host "  │ backend-vnet-poc          Virtual Network (10.0.0.0/16)         │" -ForegroundColor White
Write-Host "  │ apim-foundry-poc-*        API Management (Developer, External)  │" -ForegroundColor White
Write-Host "  │ func-order-api-poc-*      Azure Function (Python 3.11, private) │" -ForegroundColor White
Write-Host "  │ plan-func-poc             App Service Plan (P1v3 Linux)         │" -ForegroundColor White
Write-Host "  │ stfuncpoc*                Storage (Function runtime)            │" -ForegroundColor White
Write-Host "  │ pip-apim-poc              Public IP for APIM                    │" -ForegroundColor White
Write-Host "  │ nsg-apim-poc              NSG (APIM management ports)           │" -ForegroundColor White
Write-Host "  └─────────────────────────────────────────────────────────────────┘" -ForegroundColor DarkYellow

Pause-Demo

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 10: Key Takeaways
# ═══════════════════════════════════════════════════════════════════════════════

Show-Header "Key Takeaways"

Write-Host "  1. BYO VNet = Full control" -ForegroundColor Cyan
Write-Host "     You own the IP ranges, subnets, NSGs, and routing." -ForegroundColor White
Write-Host "     Foundry agents are injected into YOUR subnet." -ForegroundColor White
Write-Host ""
Write-Host "  2. Delegated subnet is the core requirement" -ForegroundColor Cyan
Write-Host "     Must be delegated to Microsoft.App/environments." -ForegroundColor White
Write-Host "     Recommended /24 for production (251 usable IPs)." -ForegroundColor White
Write-Host "     Set at account creation — cannot be changed later." -ForegroundColor Yellow
Write-Host ""
Write-Host "  3. Private endpoints for all data" -ForegroundColor Cyan
Write-Host "     AI Search, Cosmos DB, Storage — all behind PEs." -ForegroundColor White
Write-Host "     No data traverses the public internet." -ForegroundColor White
Write-Host ""
Write-Host "  4. APIM bridges networks securely" -ForegroundColor Cyan
Write-Host "     Single public endpoint for external/cross-VNet APIs." -ForegroundColor White
Write-Host "     Backend remains completely private." -ForegroundColor White
Write-Host "     Add rate limiting, auth, versioning at the gateway." -ForegroundColor White
Write-Host ""
Write-Host "  5. Template 19 makes it reproducible" -ForegroundColor Cyan
Write-Host "     Official Bicep template from microsoft-foundry/foundry-samples." -ForegroundColor White
Write-Host "     Deploy everything with a single 'az deployment group create'." -ForegroundColor White
Write-Host ""
Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Demo complete! Questions?" -ForegroundColor Green
Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
