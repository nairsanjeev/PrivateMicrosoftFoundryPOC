"""
Create a Foundry Prompt Agent grounded with Foundry IQ + Private Function Tool Call.

Architecture (ALL traffic stays within the private network):
  ┌─────────────────── VNet 1 (192.168.0.0/16) ───────────────────┐
  │  agent-subnet          pe-subnet                                │
  │  ┌───────────────┐     ┌─────────────────────────────────────┐ │
  │  │ Foundry Agent │────▶│ PE: AI Search (Foundry IQ grounding)│ │
  │  │ (this agent)  │     │ PE: Azure Function (tool call)      │ │
  │  └───────────────┘     └──────────────────┬──────────────────┘ │
  └────────────────────────────────────────────┼───────────────────┘
                                               │ Private Endpoint
  ┌─────────────────── VNet 2 (10.0.0.0/16) ──┼───────────────────┐
  │                                            ▼                    │
  │  ┌──────────────────────────────────────────────────────────┐  │
  │  │ Azure Function (publicNetworkAccess: DISABLED)           │  │
  │  │ Inventory API — product data, stock levels, orders       │  │
  │  └──────────────────────────────────────────────────────────┘  │
  └────────────────────────────────────────────────────────────────┘

Demo Story: "Contoso IT Procurement Assistant"
  An enterprise procurement team needs an AI assistant that can:
  - Answer questions about product specs, policies, warranties (from knowledge base)
  - Check real-time inventory and stock levels (from live API)
  - Place orders with quantity and SKU (via live API)
  ALL without any data leaving the corporate network boundary.

Run this FROM THE JUMP BOX VM (vm-jumpbox) via Azure Bastion:
  The Foundry endpoint + Function are both private-only.

Prerequisites on the VM:
  pip install azure-ai-projects azure-identity
  az login
  
Environment variables:
  PROJECT_ENDPOINT     - Foundry project endpoint (private)
  SEARCH_CONNECTION_ID - AI Search connection resource ID (for Foundry IQ)
  FUNCTION_HOSTNAME    - Private Function hostname (resolves to 192.168.1.x via PE)
  MODEL_DEPLOYMENT     - Model name (default: gpt-4.1)
"""
import os
import json
import sys
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    AzureAISearchTool,
    OpenApiTool,
    OpenApiAnonymousAuthDetails,
)

# ── Configuration ─────────────────────────────────────────────────────
PROJECT_ENDPOINT = os.environ.get("PROJECT_ENDPOINT", "")
SEARCH_CONNECTION_ID = os.environ.get("SEARCH_CONNECTION_ID", "")
FUNCTION_HOSTNAME = os.environ.get("FUNCTION_HOSTNAME", "")
MODEL = os.environ.get("MODEL_DEPLOYMENT", "gpt-4.1")

AGENT_NAME = "contoso-procurement-agent"
INDEX_NAME = "product-knowledge-base"

# ── Agent Instructions ────────────────────────────────────────────────
INSTRUCTIONS = """\
You are the **Contoso IT Procurement Assistant** — an enterprise AI agent that helps 
the IT procurement team manage technology purchases securely within the corporate network.

## Your Capabilities

### 1. Knowledge Base (Foundry IQ — AI Search grounding)
You have access to Contoso's internal product documentation stored in Azure AI Search:
- **Product specifications** — detailed specs for laptops, phones, tablets, monitors
- **Company policies** — return policy (30-day window), shipping tiers, warranty options
- **Enterprise programs** — volume discounts, dedicated account managers, Net-30 terms
- **Support tiers** — Basic, Professional ($19.99/mo), Enterprise ($49.99/mo)

Use the knowledge base to answer questions about specs, policies, and programs.
Always cite the source document when answering from the knowledge base.

### 2. Real-Time Inventory API (Private Function — tool call via Private Endpoint)
You can query the live inventory system which runs in a separate, isolated Virtual Network.
The API is hosted on an Azure Function with **public access completely disabled** —
you reach it exclusively through a Private Endpoint within the corporate network.

Available operations:
- **List products** — browse inventory, optionally filter by category 
  (Laptops, Phones, Tablets, Monitors, Accessories)
- **Check stock** — verify real-time availability by SKU (e.g. LAPTOP-001)
- **Place order** — submit purchase orders with SKU and quantity

## Behavior Guidelines

1. When asked about products, FIRST check the knowledge base for detailed specifications 
   and recommendations, THEN use the Inventory API for real-time stock and pricing.

2. Before placing any order, always:
   - Confirm the product, quantity, and total cost with the user
   - Check stock availability first
   - Mention applicable enterprise discounts if ordering 10+ units

3. Emphasize security: all data flows stay within the private network. No information 
   traverses the public internet — the Function, AI Search, and this agent are all 
   connected via Private Endpoints within the corporate VNet infrastructure.

4. Be professional, concise, and helpful. Format responses clearly with product details, 
   pricing, and stock levels when relevant.
"""

# ── OpenAPI Spec (points to private Function hostname) ────────────────
def build_openapi_spec(function_hostname: str) -> dict:
    """Build OpenAPI spec pointing to the private Function endpoint."""
    return {
        "openapi": "3.0.1",
        "info": {
            "title": "Contoso Inventory API",
            "description": "Private inventory system. Runs in Azure Function with publicNetworkAccess DISABLED. Reachable only via Private Endpoint from within VNet 1.",
            "version": "1.0.0",
        },
        "servers": [{"url": f"https://{function_hostname}/api"}],
        "paths": {
            "/inventory/list": {
                "get": {
                    "operationId": "listProducts",
                    "summary": "List all products in inventory",
                    "description": "Returns products from the private inventory database. Optionally filter by category.",
                    "parameters": [
                        {
                            "name": "category",
                            "in": "query",
                            "required": False,
                            "description": "Product category filter",
                            "schema": {
                                "type": "string",
                                "enum": ["Laptops", "Phones", "Tablets", "Monitors", "Accessories"],
                            },
                        }
                    ],
                    "responses": {
                        "200": {
                            "description": "Product list from private API",
                            "content": {"application/json": {"schema": {"type": "object"}}},
                        }
                    },
                }
            },
            "/inventory/check": {
                "get": {
                    "operationId": "checkStock",
                    "summary": "Check real-time stock level for a product",
                    "description": "Returns current stock quantity, warehouse location, and availability for a specific SKU.",
                    "parameters": [
                        {
                            "name": "sku",
                            "in": "query",
                            "required": True,
                            "description": "Product SKU (e.g. LAPTOP-001, PHONE-001)",
                            "schema": {"type": "string"},
                        }
                    ],
                    "responses": {
                        "200": {
                            "description": "Stock information",
                            "content": {"application/json": {"schema": {"type": "object"}}},
                        }
                    },
                }
            },
            "/inventory/order": {
                "post": {
                    "operationId": "placeOrder",
                    "summary": "Place a purchase order",
                    "description": "Submits an order for the specified product and quantity. Returns order confirmation with total price.",
                    "requestBody": {
                        "required": True,
                        "content": {
                            "application/json": {
                                "schema": {
                                    "type": "object",
                                    "required": ["sku"],
                                    "properties": {
                                        "sku": {
                                            "type": "string",
                                            "description": "Product SKU to order",
                                        },
                                        "quantity": {
                                            "type": "integer",
                                            "default": 1,
                                            "description": "Number of units to order",
                                        },
                                    },
                                }
                            }
                        },
                    },
                    "responses": {
                        "200": {
                            "description": "Order confirmation",
                            "content": {"application/json": {"schema": {"type": "object"}}},
                        }
                    },
                }
            },
        },
    }


# ── Create the Agent ──────────────────────────────────────────────────
def create_agent():
    """Create the Contoso Procurement Agent with Foundry IQ + private Function tool."""
    if not PROJECT_ENDPOINT:
        print("❌ PROJECT_ENDPOINT not set. Export it before running.")
        sys.exit(1)
    if not FUNCTION_HOSTNAME:
        print("❌ FUNCTION_HOSTNAME not set. Export it before running.")
        sys.exit(1)

    print("=" * 65)
    print("  Contoso IT Procurement Agent — Private Network Demo")
    print("=" * 65)
    print()
    print("  Configuration:")
    print(f"    Foundry Endpoint:   {PROJECT_ENDPOINT}")
    print(f"    Function (private): {FUNCTION_HOSTNAME}")
    print(f"    Search Index:       {INDEX_NAME}")
    print(f"    Model:              {MODEL}")
    print()

    credential = DefaultAzureCredential()
    client = AIProjectClient(endpoint=PROJECT_ENDPOINT, credential=credential)

    # ── Tool 1: Foundry IQ grounding (AI Search via Private Endpoint) ──
    tools = []
    if SEARCH_CONNECTION_ID:
        ai_search_tool = AzureAISearchTool(
            index_connection_id=SEARCH_CONNECTION_ID,
            index_name=INDEX_NAME,
        )
        tools.append(ai_search_tool)
        print("  ✅ Foundry IQ (AI Search) tool configured")
        print(f"     → Grounded on '{INDEX_NAME}' via Private Endpoint in VNet 1")
    else:
        print("  ⚠️  SEARCH_CONNECTION_ID not set — skipping Foundry IQ grounding")

    # ── Tool 2: Inventory API (Private Function via PE) ────────────────
    openapi_spec = build_openapi_spec(FUNCTION_HOSTNAME)
    openapi_tool = OpenApiTool(
        name="contoso_inventory",
        description=(
            "Contoso's real-time inventory system. The API runs on an Azure Function "
            "in VNet 2 with public network access DISABLED. Reachable exclusively via "
            "Private Endpoint from within VNet 1 (pe-subnet). Use for listing products, "
            "checking stock, and placing orders."
        ),
        spec=openapi_spec,
        auth=OpenApiAnonymousAuthDetails(),
    )
    tools.append(openapi_tool)
    print("  ✅ Inventory API tool configured")
    print(f"     → Private Function: {FUNCTION_HOSTNAME}")
    print(f"     → Resolves to private IP via DNS (192.168.1.x)")
    print()

    # ── Create the agent ───────────────────────────────────────────────
    # Combine tool definitions
    tool_definitions = []
    for tool in tools:
        if hasattr(tool, "definitions"):
            tool_definitions.extend(tool.definitions)
        else:
            tool_definitions.append(tool)

    agent = client.agents.create_agent(
        model=MODEL,
        name=AGENT_NAME,
        instructions=INSTRUCTIONS,
        tools=tool_definitions,
    )

    print(f"  ✅ Agent created!")
    print(f"     ID:    {agent.id}")
    print(f"     Name:  {agent.name}")
    print(f"     Model: {agent.model}")
    print(f"     Tools: {len(agent.tools)} configured")
    print()

    return client, agent


# ── Interactive Demo ──────────────────────────────────────────────────
def run_demo(client, agent):
    """Run an interactive demo conversation showcasing both tools."""
    print("─" * 65)
    print("  DEMO: Testing agent with sample procurement queries")
    print("─" * 65)
    print()

    demo_queries = [
        # Query 1: Knowledge base grounding (Foundry IQ)
        "What is our return policy for enterprise bulk orders?",
        # Query 2: Real-time inventory check (private Function)
        "Show me all available laptops and their current stock levels.",
        # Query 3: Combined — spec from KB + stock from API
        "I need details on the ThinkPad X1 Carbon — specs, price, and whether it's in stock.",
        # Query 4: Place an order (Function tool call)
        "Place an order for 25 units of LAPTOP-001. What discount applies?",
    ]

    thread = client.agents.create_thread()

    for i, query in enumerate(demo_queries, 1):
        print(f"  [{i}/{len(demo_queries)}] User: {query}")
        print()

        client.agents.create_message(
            thread_id=thread.id,
            role="user",
            content=query,
        )

        run = client.agents.create_and_process_run(
            thread_id=thread.id,
            assistant_id=agent.id,
        )

        if run.status == "failed":
            print(f"  ❌ Run failed: {run.last_error}")
            print()
            continue

        # Get the assistant's response
        messages = client.agents.list_messages(thread_id=thread.id)
        for msg in messages.data:
            if msg.role == "assistant":
                for content in msg.content:
                    if hasattr(content, "text"):
                        response = content.text.value
                        # Print with indent
                        for line in response.split("\n"):
                            print(f"  🤖 {line}")
                break

        print()
        print("  " + "·" * 60)
        print()

    return thread.id


# ── Main ──────────────────────────────────────────────────────────────
def main():
    client, agent = create_agent()

    print()
    print("=" * 65)
    print("  NETWORK FLOW SUMMARY")
    print("=" * 65)
    print("""
  Every request stays within the private network:

  ┌─ User Query ─────────────────────────────────────────────────┐
  │                                                               │
  │  "What laptops are available and in stock?"                   │
  │                                                               │
  │  Step 1 (Foundry IQ):                                        │
  │    Agent ──PE──▶ AI Search (product-knowledge-base index)     │
  │    Returns: ThinkPad X1 specs, MacBook Pro specs              │
  │    Network: VNet 1 pe-subnet → AI Search private endpoint     │
  │                                                               │
  │  Step 2 (Tool Call):                                          │
  │    Agent ──PE──▶ Azure Function /inventory/list?category=Laptops │
  │    Returns: real-time stock, pricing, warehouse location      │
  │    Network: VNet 1 pe-subnet → VNet 2 Function (private)     │
  │                                                               │
  │  Step 3 (Response):                                           │
  │    Agent combines KB specs + live stock data                  │
  │    Zero bytes traverse the public internet                    │
  └───────────────────────────────────────────────────────────────┘
""")

    # Run demo if requested
    if "--demo" in sys.argv:
        run_demo(client, agent)

    # Print next steps
    print("─" * 65)
    print("  NEXT STEPS")
    print("─" * 65)
    print(f"""
  Agent ID: {agent.id}

  To test interactively:
    python create_grounded_agent.py --demo

  To use in the React UI:
    export AGENT_ID={agent.id}
    cd ../react-ui && npm start

  Sample questions to ask:
    • "What's our warranty coverage for the MacBook Pro?"
    • "Check stock for PHONE-001 and TABLET-001"
    • "I need 50 keyboards for the new hires. What's the bulk discount?"
    • "Compare the ThinkPad X1 and MacBook Pro 16 for our dev team"
    • "Place an order for 10 iPhone 15 Pros"
""")


if __name__ == "__main__":
    main()
