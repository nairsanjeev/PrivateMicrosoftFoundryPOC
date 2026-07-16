# Microsoft Foundry — BYO VNet Isolation Demo Script

---

## Quick Start — Run the Demo

> **One script. No manual configuration.** Connect to the jump box and run.

### Prerequisites (already deployed)

- Resource group `rg-foundry-byo-vnet` with Foundry infrastructure deployed
- Backend (APIM + Function) deployed via `deploy-backend.bicep`
- Knowledge base indexed via `setup_knowledge_base.py`
- Jump Box VM accessible via Azure Bastion

### Step 1: Connect to the Jump Box

1. Go to **Azure Portal** → Resource Group `rg-foundry-byo-vnet` → `vm-jumpbox`
2. Click **Connect** → **Bastion**
3. Login: `azureadmin` / (password set during deployment)

### Step 2: Run the Demo Script

Open **PowerShell** on the jump box and run:

```powershell
C:\PrivateMicrosoftFoundryPOC\agent-setup\run-on-jumpbox.ps1
```

This single script will:
| Step | What it does | Proves |
|------|--------------|--------|
| 1 | Discovers all deployed resources automatically | No hardcoded values |
| 2 | Resolves Function + Foundry DNS to private IPs | Private DNS zones work |
| 3 | Calls the Function API via private endpoint | Cross-VNet connectivity |
| 4 | Installs Python packages | Dependencies ready |
| 5 | Verifies Azure CLI login | Auth is working |
| 6 | Auto-discovers connection IDs, sets env vars | Zero manual config |
| 7 | Creates the **Contoso Procurement Agent** | Agent is live |
| 7b | Runs 4 demo queries (with `--demo` flag) | End-to-end proof |

### Step 3: Watch the Demo Output

The script will run 4 sample queries that showcase both tools:

| # | Query | Tool Used | Network Path |
|---|-------|-----------|-------------|
| 1 | "What is our return policy for enterprise bulk orders?" | **Foundry IQ** (AI Search) | agent-subnet → PE → AI Search |
| 2 | "Show me all available laptops and their stock levels" | **Inventory API** (Function) | agent-subnet → PE → VNet 2 Function |
| 3 | "ThinkPad X1 Carbon — specs, price, and stock?" | **Both** | KB for specs, API for stock |
| 4 | "Place an order for 25 units of LAPTOP-001" | **Inventory API** (Function) | agent-subnet → PE → VNet 2 Function |

### Step 4: Test Interactively (Optional)

After the agent is created, test in the **Azure AI Foundry portal** (open Edge on the jump box):

```
https://ai.azure.com
```

Find the agent `contoso-procurement-agent` and try:
- "What warranty options do we have?"
- "Check stock for PHONE-001 and TABLET-001"
- "I need 50 keyboards for new hires. What's the bulk discount?"
- "Compare the ThinkPad X1 and MacBook Pro for our dev team"

### Step 5: Show the React UI (Optional)

If the React UI is deployed on the jump box:

```powershell
cd C:\PrivateMicrosoftFoundryPOC\react-ui
npm install
npm start
```

Then open `http://localhost:3000` in Edge on the jump box.

---

### Alternate: Run from Your Workstation (if Foundry has public access enabled)

If the Foundry endpoint has `publicNetworkAccess: Enabled` for testing:

```powershell
# From your local machine (not the jump box)
cd C:\PrivateMicrosoftFoundryPOC

# Set environment variables (auto-discover)
$RG = "rg-foundry-byo-vnet"
$aiAccount = az cognitiveservices account list --resource-group $RG --query "[0].name" -o tsv
$env:PROJECT_ENDPOINT = az cognitiveservices account show --name $aiAccount -g $RG --query "properties.endpoint" -o tsv
$env:FUNCTION_HOSTNAME = az functionapp show --name (az functionapp list -g $RG --query "[0].name" -o tsv) -g $RG --query "defaultHostName" -o tsv
$env:MODEL_DEPLOYMENT = "gpt-4.1"

# Discover Search connection
$subId = az account show --query id -o tsv
$projects = az rest --method get --url "https://management.azure.com/subscriptions/$subId/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$aiAccount/projects?api-version=2025-04-01-preview" --only-show-errors | ConvertFrom-Json
$projId = $projects.value[0].id
$conns = az rest --method get --url "https://management.azure.com${projId}/connections?api-version=2025-04-01-preview" --only-show-errors | ConvertFrom-Json
$env:SEARCH_CONNECTION_ID = ($conns.value | Where-Object { $_.properties.category -eq "CognitiveSearch" }).properties.resourceId

# Create agent and run demo
python agent-setup/create_grounded_agent.py --demo
```

---

## Overview

This demo walks through how Microsoft Foundry Agent Service is deployed with **Bring-Your-Own Virtual Network** (BYO VNet) isolation, how an agent calls a private API through APIM, and how grounded knowledge works via AI Search (Foundry IQ) — all with network isolation.

---

## Demo Architecture

```
┌───────────────────────────────────────────────────────────────────────┐
│  VNet 1 — Foundry BYO VNet (192.168.0.0/16) — swedencentral           │
│                                                                         │
│  ┌──────────────────────┐       ┌────────────────────────────────────┐│
│  │ agent-subnet /24     │       │ pe-subnet /24 (Private Endpoints)  ││
│  │                      │       │                                    ││
│  │ Delegated to:        │       │ ┌──────────┐ ┌────────┐ ┌───────┐ ││
│  │ Microsoft.App/       │──PE──▶│ │AI Search │ │Storage │ │Cosmos │ ││
│  │ environments         │       │ │(Foundry  │ │(Files) │ │(Thread│ ││
│  │                      │       │ │ IQ KB)   │ │        │ │ State)│ ││
│  │ Foundry Agent Service│       │ └──────────┘ └────────┘ └───────┘ ││
│  │ (gpt-4.1 model)      │       └────────────────────────────────────┘│
│  └──────────┬───────────┘                                              │
└─────────────┼──────────────────────────────────────────────────────────┘
              │
              │  OpenAPI tool call → APIM public endpoint
              ▼
┌───────────────────────────────────────────────────────────────────────┐
│  VNet 2 — Backend API (10.0.0.0/16)                                    │
│                                                                         │
│  ┌─────────────────────────────┐   ┌──────────────────────────────┐  │
│  │ apim-subnet /24             │   │ func-subnet /24              │  │
│  │                             │   │                              │  │
│  │ Azure API Management        │   │ Azure Function (Order API)   │  │
│  │ (External VNet mode)        │──▶│ publicNetworkAccess: DISABLED│  │
│  │                             │   │ Only reachable via APIM      │  │
│  │ 🌍 Public IP (gateway)     │   │                              │  │
│  └─────────────────────────────┘   └──────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────┘
```

---

## Section 1: What is BYO VNet for Foundry?

**Talking points:**

- Microsoft Foundry Agent Service supports three networking modes:
  - **Public egress** — no isolation, fastest to get started
  - **Managed VNet** — Microsoft manages the VNet for you
  - **BYO VNet** — You bring your own Virtual Network, full control
- BYO VNet gives you:
  - Your own IP ranges, subnets, NSGs, route tables
  - Full control over what the agent can access
  - Traffic stays on your private network
  - Compliant with enterprise security requirements

**Key requirement:** A subnet **delegated** to `Microsoft.App/environments`. This is where Foundry injects agent Micro VMs.

**Show in Azure Portal or CLI:**

```bash
# Show VNet 1 with the delegated subnet
az network vnet show --name foundry-poc-vnet --resource-group rg-foundry-byo-vnet \
  --query "{addressSpace:addressSpace.addressPrefixes[0], subnets:subnets[].{name:name, prefix:addressPrefix, delegation:delegations[0].serviceName}}" \
  -o table
```

**Expected output:**
| Subnet | Prefix | Delegation |
|--------|--------|-----------|
| agent-subnet | 192.168.0.0/24 | **Microsoft.App/environments** |
| pe-subnet | 192.168.1.0/24 | (none) |
| mcp-subnet | 192.168.2.0/24 | Microsoft.App/environments |

**Key point:** The `agent-subnet` delegation is set at Foundry account creation time and **cannot be changed later**. Size it for scale — a /24 gives ~251 usable IPs, each agent session consumes one.

---

## Section 2: Private Endpoints — Zero Public Exposure

**Talking points:**

- All data resources sit behind **Private Endpoints** in the `pe-subnet`
- This means:
  - No traffic ever leaves the VNet to reach these services
  - Even if someone discovers the public DNS name, it resolves to nothing useful
  - Data exfiltration risk is eliminated at the network layer

**Show:**

```bash
# List all private endpoints
az network private-endpoint list --resource-group rg-foundry-byo-vnet \
  --query "[].{name:name, status:privateLinkServiceConnections[0].properties.privateLinkServiceConnectionState.status}" \
  -o table
```

**Expected output:**
| Private Endpoint | Status |
|-----------------|--------|
| foundrypoc3zvj-private-endpoint | Approved |
| foundrypoc3zvjsearch-private-endpoint | Approved |
| foundrypoc3zvjstorage-private-endpoint | Approved |
| foundrypoc3zvjcosmosdb-private-endpoint | Approved |
| acr3zvj-private-endpoint | Approved |
| ampls-tracing-3zvj-pe | Approved |

**What each one protects:**
- **Foundry** — The control plane itself is PE-accessible
- **AI Search** — Knowledge base queries stay in-VNet
- **Storage** — File uploads stay private
- **Cosmos DB** — Agent threads and message history stay private
- **ACR** — Container images pulled privately
- **Monitor (AMPLS)** — Even telemetry goes through private link

---

## Section 3: The Foundry Account — Network Injection

**Talking points:**

- The Foundry account is configured with `networkInjections` that tell the platform:
  - *"Deploy my agent workloads INTO this subnet"*
  - *"Don't use a Microsoft-managed network — use mine"*
- This is the `Microsoft.CognitiveServices/accounts` resource with `kind: AIServices`

**Show:**

```bash
# Show the Foundry account configuration
az cognitiveservices account show --name foundrypoc3zvj --resource-group rg-foundry-byo-vnet \
  --query "{name:name, endpoint:properties.endpoint, publicAccess:properties.publicNetworkAccess, bypass:properties.networkAcls.bypass}" \
  -o table
```

**Key config in Bicep:**
```bicep
properties: {
  networkInjections: [
    {
      scenario: 'agent'
      subnetArmId: '/subscriptions/.../subnets/agent-subnet'
      useMicrosoftManagedNetwork: false  // ← BYO VNet!
    }
  ]
  publicNetworkAccess: 'Enabled'  // For this POC (testing without VPN)
  networkAcls: { bypass: 'AzureServices' }
}
```

**Note:** In production, you would set `publicNetworkAccess: 'Disabled'` and access via VPN Gateway, ExpressRoute, or Azure Bastion.

---

## Section 4: Foundry IQ — AI Search Grounding (Private)

**Talking points:**

- The agent uses **AI Search** as a grounding tool (called "Foundry IQ")
- It searches a knowledge base of product documentation, policies, warranties
- **All queries stay within VNet 1** — traffic goes from `agent-subnet` → private endpoint → AI Search
- The search service has `publicNetworkAccess: disabled`

**Show:**

```bash
# Verify AI Search is private-only
az search service show --name foundrypoc3zvjsearch --resource-group rg-foundry-byo-vnet \
  --query "{name:name, publicAccess:publicNetworkAccess, sku:sku.name, status:status}" \
  -o table
```

**Knowledge base contents:**
- Product specifications (ThinkPad X1, MacBook Pro, iPhone 15 Pro...)
- Return policy (30-day window, restocking fees)
- Warranty information (1-3 year options)
- Shipping details (Standard, Express, Next-day)
- Enterprise purchasing program (volume discounts)
- Technical support tiers (Basic, Professional, Enterprise)

**The network story:**
> "When the agent needs to answer 'What's your return policy?', it queries AI Search through the private endpoint. The query never leaves VNet 1. The response never touches the public internet."

---

## Section 5: The Backend API — In a Separate VNet

**Talking points:**

- Real-world scenario: Your backend APIs live in their OWN network
- They shouldn't be publicly accessible
- But your Foundry agent needs to call them
- Solution: **APIM as a gateway between the networks**

**Show:**

```bash
# Show VNet 2
az network vnet show --name backend-vnet-poc --resource-group rg-foundry-byo-vnet \
  --query "{addressSpace:addressSpace.addressPrefixes[0], subnets:subnets[].{name:name, prefix:addressPrefix, delegation:delegations[0].serviceName}}" \
  -o table
```

**VNet 2 design:**
| Subnet | Purpose | Key property |
|--------|---------|-------------|
| apim-subnet (10.0.0.0/24) | APIM deployed here | External mode = public IP for inbound |
| func-subnet (10.0.1.0/24) | Azure Function here | Delegated to `Microsoft.Web/serverFarms` |

---

## Section 6: The Azure Function — Completely Private

**Talking points:**

- The Azure Function implements an Inventory/Order API
- It has **`publicNetworkAccess: Disabled`**
- If you try to call it directly → CONNECTION REFUSED
- It is VNet-integrated into `func-subnet`
- **Only APIM can reach it** (because APIM is in the same VNet)

**Show:**

```bash
# Show Function app is private
az functionapp show --name $(az functionapp list -g rg-foundry-byo-vnet --query "[0].name" -o tsv) \
  --resource-group rg-foundry-byo-vnet \
  --query "{name:name, publicAccess:publicNetworkAccess, vnet:virtualNetworkSubnetId}" \
  -o table
```

**API endpoints (only via APIM):**
| Method | Path | Description |
|--------|------|-------------|
| GET | /inventory/list | List all products (filter by category) |
| GET | /inventory/check?sku=LAPTOP-001 | Check stock for a product |
| POST | /inventory/order | Place an order |

**Demo point:**
> "Try calling the Function directly — it fails. Now call through APIM — it works. Same API, but the network controls who can reach it."

---

## Section 7: APIM — The Single Gateway

**Talking points:**

- Azure API Management is deployed in **External VNet mode**:
  - Has a public IP address (reachable from internet)
  - But lives inside VNet 2 (can route to private resources)
- This makes it the **bridge** between:
  - The Foundry Agent (in VNet 1) making tool calls
  - The private Azure Function (in VNet 2, no public access)
- Single endpoint for all your backend APIs
- Add rate limiting, authentication, versioning, monitoring

**Show:**

```bash
# Show APIM gateway URL
az apim show --name $(az apim list -g rg-foundry-byo-vnet --query "[0].name" -o tsv) \
  --resource-group rg-foundry-byo-vnet \
  --query "{name:name, gateway:gatewayUrl, vnetMode:virtualNetworkType, sku:sku.name}" \
  -o table
```

**Test it:**
```bash
# This goes: Internet → APIM (public IP) → Function (private, VNet internal)
curl https://<apim-gateway-url>/inventory/list
```

---

## Section 8: End-to-End Flow — What Happens When You Ask a Question

**Scenario:** User asks *"Check stock for LAPTOP-001 and tell me about its warranty"*

```
Step 1: User → Foundry Agent
        User sends message to the Foundry endpoint
        (via public access in this POC, or via VPN/PE in production)

Step 2: Agent → AI Search (Foundry IQ grounding)
        Agent queries the knowledge base for warranty information
        Traffic: agent-subnet → private endpoint → AI Search
        ✓ STAYS WITHIN VNet 1 — never touches internet

Step 3: Agent → APIM → Azure Function (tool call)
        Agent calls the OpenAPI tool to check real-time stock
        Traffic: Agent → APIM public gateway → internal route → Function
        ✓ Function is PRIVATE — only APIM can reach it

Step 4: Agent composes response
        Combines:
        - Knowledge base: warranty details (from AI Search)
        - Live data: stock level, warehouse (from Function via APIM)

Step 5: Response → User
        Agent returns a unified answer citing both sources
```

**Network security at every step:**
- AI Search data → never leaves VNet 1
- Function → never exposed to internet
- Agent threads → stored in Cosmos DB (private endpoint)
- File uploads → stored in Blob Storage (private endpoint)
- Telemetry → sent via Azure Monitor Private Link Scope

---

## Section 9: What's Deployed — Full Resource Inventory

### VNet 1: Foundry BYO Network

| Resource | Type | Purpose |
|----------|------|---------|
| foundry-poc-vnet | Virtual Network (192.168.0.0/16) | BYO VNet with 3 subnets |
| foundrypoc3zvj | Cognitive Services (AIServices, S0) | Foundry Account |
| byovnet-poc3zvj | Foundry Project | Agent workspace |
| foundrypoc3zvjsearch | AI Search (Standard) | Knowledge base / Foundry IQ |
| foundrypoc3zvjstorage | Storage Account | Agent file storage |
| foundrypoc3zvjcosmosdb | Cosmos DB (NoSQL) | Thread/message storage |
| acr3zvj | Container Registry (Premium) | Agent container images |
| appi-tracing-3zvj | Application Insights | Telemetry |
| law-tracing-3zvj | Log Analytics Workspace | Logs |
| ampls-tracing-3zvj | Monitor Private Link Scope | Private telemetry ingestion |
| 6x Private Endpoints | Private Endpoints | Zero public exposure |
| 7x Private DNS Zones | DNS | PE name resolution |

### VNet 2: Backend API Network

| Resource | Type | Purpose |
|----------|------|---------|
| backend-vnet-poc | Virtual Network (10.0.0.0/16) | Backend network |
| apim-foundry-poc-* | API Management (Developer, External) | Public API gateway |
| func-order-api-poc-* | Function App (Python 3.11) | Inventory API (PRIVATE) |
| plan-func-poc | App Service Plan (P1v3 Linux) | Function compute |
| stfuncpoc* | Storage Account | Function runtime |
| pip-apim-poc | Public IP | APIM inbound |
| nsg-apim-poc | NSG | APIM management ports |

---

## Section 10: Key Takeaways

### 1. BYO VNet = Full Control
You own the IP ranges, subnets, NSGs, and routing. Foundry agents are injected into YOUR subnet. No surprises.

### 2. Delegated Subnet is the Core Requirement
- Must be delegated to `Microsoft.App/environments`
- Recommended /24 for production (251 usable IPs)
- Set at account creation — **cannot be changed later**
- Plan for: concurrent sessions × agents × projects

### 3. Private Endpoints for All Data
AI Search, Cosmos DB, Storage — all behind PEs. No data traverses the public internet. Even telemetry goes through AMPLS.

### 4. APIM Bridges Networks Securely
- Single public endpoint for all backend APIs
- Backend Function has zero public exposure
- Add rate limiting, auth, versioning, monitoring at the gateway layer
- The agent registers APIM's public URL as an OpenAPI tool

### 5. Template 19 Makes It Reproducible
- Official Bicep template from `microsoft-foundry/foundry-samples`
- Deploys the full stack with one `az deployment group create`
- Includes: VNet, subnets, Foundry, AI Search, Cosmos, Storage, PEs, DNS zones, RBAC
- Supports BYO existing VNet/subnets for enterprise landing zones

---

## Appendix: Useful Commands

```bash
# Check all resources
az resource list --resource-group rg-foundry-byo-vnet --query "[].{name:name, type:type}" -o table

# Test APIM → Function connectivity
curl https://<apim-gateway>/inventory/list
curl https://<apim-gateway>/inventory/check?sku=LAPTOP-001

# Verify Function is unreachable directly
curl https://<function-hostname>/api/inventory/list  # Should fail!

# Check Foundry agent endpoint
az cognitiveservices account show --name foundrypoc3zvj -g rg-foundry-byo-vnet --query properties.endpoint -o tsv

# List private DNS zones
az network private-dns zone list --resource-group rg-foundry-byo-vnet --query "[].name" -o tsv

# Cleanup everything
az group delete --name rg-foundry-byo-vnet --yes --no-wait
```

---

## Appendix: Template Reference

| Template | Description |
|----------|-------------|
| [19-private-network-agent-tools](https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-bicep/19-private-network-agent-tools) | BYO VNet + tools behind VNet (MCP, OpenAPI, Functions, A2A) |
| [15-private-network-standard-agent-setup](https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-bicep/15-private-network-standard-agent-setup) | BYO VNet without tools behind VNet |
| [16-private-network-standard-agent-apim-setup](https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-bicep/16-private-network-standard-agent-apim-setup) | BYO VNet + APIM integration |
| [18-managed-virtual-network](https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-bicep/18-managed-virtual-network) | Managed VNet (Microsoft handles the network) |

---

*Demo built on subscription `ME-MngEnvMCAP048757-snair-1` in `swedencentral`.*
