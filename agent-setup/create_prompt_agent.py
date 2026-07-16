"""
Create a Prompt Agent in Microsoft Foundry with an OpenAPI tool call
to the Azure Function (in VNet 2, private, reachable via PE in VNet 1).

Run this script FROM THE JUMP BOX VM (vm-jumpbox) via Azure Bastion,
because the Foundry endpoint is private (only accessible from within VNet 1).

Prerequisites on the VM:
  pip install azure-ai-projects azure-identity
  az login

The Function URL resolves to a private IP (192.168.1.26) via private DNS
within VNet 1, proving the cross-VNet call works through network isolation.
"""
import os
import json
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import OpenApiTool, OpenApiAnonymousAuthDetails

# ── Config ────────────────────────────────────────────────────────────
PROJECT_ENDPOINT = os.environ.get("PROJECT_ENDPOINT", "")
FUNCTION_HOSTNAME = os.environ.get("FUNCTION_HOSTNAME", "")
MODEL = os.environ.get("MODEL_DEPLOYMENT", "gpt-4.1")

# ── OpenAPI spec for the Inventory API ────────────────────────────────
OPENAPI_SPEC = {
    "openapi": "3.0.1",
    "info": {
        "title": "Inventory API",
        "description": "Product inventory API in a private Azure Function (VNet 2). Only reachable via private endpoint from VNet 1.",
        "version": "1.0.0"
    },
    "servers": [
        {
            "url": f"https://{FUNCTION_HOSTNAME}/api"
        }
    ],
    "paths": {
        "/inventory/list": {
            "get": {
                "operationId": "listProducts",
                "summary": "List all products in inventory",
                "parameters": [
                    {
                        "name": "category",
                        "in": "query",
                        "required": False,
                        "schema": {"type": "string"}
                    }
                ],
                "responses": {
                    "200": {
                        "description": "Product list",
                        "content": {"application/json": {"schema": {"type": "object"}}}
                    }
                }
            }
        },
        "/inventory/check": {
            "get": {
                "operationId": "checkStock",
                "summary": "Check stock level for a product by SKU",
                "parameters": [
                    {
                        "name": "sku",
                        "in": "query",
                        "required": True,
                        "schema": {"type": "string"}
                    }
                ],
                "responses": {
                    "200": {
                        "description": "Stock info",
                        "content": {"application/json": {"schema": {"type": "object"}}}
                    }
                }
            }
        },
        "/inventory/order": {
            "post": {
                "operationId": "placeOrder",
                "summary": "Place an order for a product",
                "requestBody": {
                    "required": True,
                    "content": {
                        "application/json": {
                            "schema": {
                                "type": "object",
                                "required": ["sku"],
                                "properties": {
                                    "sku": {"type": "string"},
                                    "quantity": {"type": "integer", "default": 1}
                                }
                            }
                        }
                    }
                },
                "responses": {
                    "200": {
                        "description": "Order confirmation",
                        "content": {"application/json": {"schema": {"type": "object"}}}
                    }
                }
            }
        }
    }
}

# ── Agent instructions ────────────────────────────────────────────────
INSTRUCTIONS = """You are an inventory assistant. You have access to a product Inventory API 
that runs in a PRIVATE Azure Function on a separate Virtual Network (VNet 2).

The function has publicNetworkAccess: DISABLED. You can reach it because:
- A Private Endpoint for the Function exists in VNet 1 (pe-subnet, IP 192.168.1.26)
- Private DNS resolves the Function hostname to that private IP
- Your agent runs in agent-subnet (VNet 1, delegated to Microsoft.App/environments)

Use the tools to:
- List products (filter by category: Laptops, Phones, Tablets, Monitors, Accessories)
- Check stock for a product by SKU (e.g., LAPTOP-001, PHONE-001)
- Place orders

When you get results, mention that the data came from the private Function 
via cross-VNet private endpoint connectivity to demonstrate network isolation works.
"""


def main():
    print("=" * 60)
    print("  Creating Prompt Agent with OpenAPI Tool Call")
    print("  Function: private (no public access)")
    print("  Connectivity: via Private Endpoint in VNet 1")
    print("=" * 60)
    print()

    credential = DefaultAzureCredential()
    client = AIProjectClient(endpoint=PROJECT_ENDPOINT, credential=credential)

    # Create the OpenAPI tool
    openapi_tool = OpenApiTool(
        name="inventory_api",
        description="Private Inventory API running in Azure Function (VNet 2). Reachable via Private Endpoint.",
        spec=OPENAPI_SPEC,
        auth=OpenApiAnonymousAuthDetails(),
    )

    # Create the agent
    agent = client.agents.create_agent(
        model=MODEL,
        name="inventory-agent-private-vnet",
        instructions=INSTRUCTIONS,
        tools=openapi_tool.definitions,
    )

    print(f"✅ Agent created!")
    print(f"   ID:    {agent.id}")
    print(f"   Name:  {agent.name}")
    print(f"   Model: {agent.model}")
    print()

    # Test it with a message
    print("Testing agent with: 'List all laptops in inventory'")
    print("-" * 50)

    thread = client.agents.create_thread()
    client.agents.create_message(
        thread_id=thread.id,
        role="user",
        content="List all laptops in inventory and check stock for LAPTOP-001",
    )

    run = client.agents.create_and_process_run(
        thread_id=thread.id,
        assistant_id=agent.id,
    )

    print(f"Run status: {run.status}")

    if run.status == "failed":
        print(f"Error: {run.last_error}")
    else:
        messages = client.agents.list_messages(thread_id=thread.id)
        for msg in messages:
            if msg.role == "assistant":
                for content in msg.content:
                    if hasattr(content, "text"):
                        print(f"\n🤖 Agent response:\n{content.text.value}")
                break

    print()
    print("=" * 60)
    print(f"  Agent ID: {agent.id}")
    print(f"  Use this ID in the Azure AI Foundry portal to test further.")
    print("=" * 60)


if __name__ == "__main__":
    main()
