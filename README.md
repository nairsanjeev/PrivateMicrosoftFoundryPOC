# Microsoft Foundry — BYO VNet POC with APIM Gateway

## Architecture

This POC demonstrates Microsoft Foundry Agent Service deployed with **Bring-Your-Own Virtual Network** (delegated subnet), connected to a backend API in a **separate VNet** via **Azure API Management**.

```
┌───────────────────────────────────────────────────────────────────────────┐
│  VNet 1 — Foundry BYO (192.168.0.0/16) — swedencentral                    │
│                                                                             │
│  ┌──────────────────┐         ┌───────────────────────────────────┐       │
│  │ agent-subnet /24 │         │ pe-subnet /24                     │       │
│  │ Delegated to     │         │ ┌─────────┐ ┌───────┐ ┌────────┐ │       │
│  │ Microsoft.App/   │ ──────▶ │ │AI Search│ │Storage│ │CosmosDB│ │       │
│  │ environments     │ private │ │(Foundry │ │(Files)│ │(Thread │ │       │
│  │                  │  PE     │ │ IQ KB)  │ │       │ │ State) │ │       │
│  │ Foundry Agent    │         │ └─────────┘ └───────┘ └────────┘ │       │
│  │ Service (gpt-4.1)│         └───────────────────────────────────┘       │
│  └────────┬─────────┘                                                     │
└───────────┼───────────────────────────────────────────────────────────────┘
            │
            │ OpenAPI tool call (APIM public endpoint)
            ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  VNet 2 — Backend API (10.0.0.0/16) — swedencentral                       │
│                                                                             │
│  ┌─────────────────────────────┐    ┌────────────────────────────────┐    │
│  │ apim-subnet /24             │    │ func-subnet /24                │    │
│  │                             │    │                                │    │
│  │ Azure API Management        │    │ Azure Function (Order API)     │    │
│  │ (External VNet mode)        │───▶│ publicNetworkAccess: DISABLED  │    │
│  │                             │    │ Only reachable via APIM        │    │
│  │ 🌍 Public IP (gateway)     │ VNet│                                │    │
│  │ Single endpoint for tools   │ int │ Inventory: list, check, order │    │
│  └─────────────────────────────┘    └────────────────────────────────┘    │
└───────────────────────────────────────────────────────────────────────────┘
```

## Key Concepts Demonstrated

| Concept | Implementation |
|---------|---------------|
| **BYO VNet with delegated subnet** | `agent-subnet` delegated to `Microsoft.App/environments` |
| **Foundry IQ grounding** | AI Search with product knowledge base (private endpoint) |
| **Tool calling via APIM** | Agent calls APIM public gateway → routes to private Function |
| **Network isolation** | Function has NO public access; only reachable internally |
| **Separate VNets** | Foundry in VNet 1, Backend API in VNet 2 |
| **APIM as gateway** | Single public endpoint exposing all backend APIs |

## Components

| Resource | Purpose | Network |
|----------|---------|---------|
| Foundry Account + Project | AI Agent hosting | VNet 1, agent-subnet (delegated) |
| AI Search | Knowledge base / Foundry IQ | VNet 1, pe-subnet (private EP) |
| Cosmos DB | Agent thread/state storage | VNet 1, pe-subnet (private EP) |
| Blob Storage | File storage | VNet 1, pe-subnet (private EP) |
| Azure API Management | Public API gateway | VNet 2, apim-subnet (external mode) |
| Azure Function | Order/Inventory API | VNet 2, func-subnet (private only) |

## Deployment

### Prerequisites
- Azure CLI installed
- Python 3.10+
- Node.js 18+ (for React UI)
- Owner/Contributor + User Access Admin on the subscription

### Step 1: Deploy Foundry Infrastructure (already done)
```bash
# Template 19 - Private network with tools behind VNet
az deployment group create \
  --resource-group rg-foundry-byo-vnet \
  --template-file foundry-samples/infrastructure/infrastructure-setup-bicep/19-private-network-agent-tools/main.bicep \
  --parameters poc.bicepparam \
  --name foundry-byo-vnet-deploy
```

### Step 2: Deploy Backend (VNet 2 + APIM + Function)
```bash
az deployment group create \
  --resource-group rg-foundry-byo-vnet \
  --template-file infra/deploy-backend.bicep \
  --parameters location=swedencentral suffix=poc \
  --name backend-deploy-2
```

### Step 3: Post-Deployment Configuration
```powershell
# Run after APIM finishes provisioning (~35 min)
.\configure-poc.ps1
```

### Step 4: Run the React UI
```bash
cd react-ui
npm install
npm start
# Opens http://localhost:3000
# Start the backend: python server.py (port 3001)
```

## Testing

1. Open the React UI at http://localhost:3000
2. Enter the Foundry Project Endpoint and Agent ID
3. Try queries like:
   - "What laptops do you have?" (triggers AI Search grounding)
   - "Check stock for LAPTOP-001" (triggers APIM → Function call)
   - "What's your return policy?" (AI Search grounding)
   - "Place an order for 2 iPhones" (APIM → Function call)

## Cleanup
```bash
az group delete --name rg-foundry-byo-vnet --yes --no-wait
```

## File Structure
```
C:\PrivateMicrosoftFoundryPOC\
├── infra/
│   └── deploy-backend.bicep          # VNet 2 + APIM + Function infra
├── foundry-samples/                   # Cloned template 19
├── azure-function/
│   ├── InventoryApi/__init__.py       # Function code (Order API)
│   ├── host.json
│   └── openapi.json                   # API spec (APIM imports this)
├── agent-setup/
│   ├── create_agent.py                # Creates Foundry Agent with tools
│   └── setup_knowledge_base.py        # Indexes docs into AI Search
├── react-ui/                          # React chat UI with network diagram
│   └── src/
│       ├── App.js
│       └── components/
│           ├── ChatPanel.js
│           ├── NetworkDiagram.js       # Live architecture visualization
│           ├── ToolCallLog.js
│           └── ConfigPanel.js
├── server.py                          # Flask backend proxying to Foundry
├── configure-poc.ps1                  # Post-deployment configuration
├── requirements.txt
└── README.md
```
