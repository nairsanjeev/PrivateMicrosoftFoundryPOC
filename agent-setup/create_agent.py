"""
Foundry Agent Setup Script
Creates an agent with:
1. AI Search grounding (Foundry IQ knowledge base)
2. Azure Function tool call (Inventory API on private VNet)

Run this from a machine that can reach the Foundry endpoint.
Since we enabled public access, this can run from anywhere.

Prerequisites:
  pip install azure-ai-projects azure-identity azure-search-documents
"""
import os
import json
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    AzureAISearchTool,
    OpenApiTool,
    OpenApiAnonymousAuthDetails,
)

# ── Configuration ──────────────────────────────────────────────────────
# These will be populated after deployment
PROJECT_ENDPOINT = os.environ.get("PROJECT_ENDPOINT", "")
SEARCH_CONNECTION_NAME = os.environ.get("SEARCH_CONNECTION_NAME", "")
APIM_GATEWAY_URL = os.environ.get("APIM_GATEWAY_URL", "")
MODEL_DEPLOYMENT = os.environ.get("MODEL_DEPLOYMENT", "gpt-4.1")

AGENT_NAME = "inventory-assistant"
AGENT_INSTRUCTIONS = """You are a helpful inventory management assistant for a technology products company.

You have access to two tools:
1. **AI Search Knowledge Base** (Foundry IQ grounding) - Contains product documentation, policies, 
   return procedures, warranty information, and FAQ content. This data is accessed via a PRIVATE 
   endpoint within VNet 1 (the Foundry BYO Virtual Network). Use this to answer questions about 
   company policies, product specifications, and general information.

2. **Inventory API** (via APIM Gateway) - A real-time inventory system. The API Management gateway 
   is a PUBLIC endpoint that routes internally to a PRIVATE Azure Function in a separate VNet (VNet 2).
   The Function has publicNetworkAccess DISABLED — only APIM can reach it.
   Use this to:
   - List available products (optionally filter by category)
   - Check stock levels for specific products by SKU
   - Place orders for products

Architecture:
- Grounding queries → AI Search via private endpoint (VNet 1, pe-subnet)
- Tool calls → APIM public gateway → Azure Function (VNet 2, func-subnet, no public access)

When a user asks about products, first check the knowledge base for detailed specs and policies,
then use the Inventory API for real-time stock and pricing data.

Always mention the network path when relevant (e.g., "This data was retrieved via APIM gateway 
routing to the private backend API in VNet 2").

Be helpful, concise, and accurate. When placing orders, always confirm the details with the user first.
"""


def create_agent():
    credential = DefaultAzureCredential()
    client = AIProjectClient(endpoint=PROJECT_ENDPOINT, credential=credential)

    # ── Tool 1: AI Search (Foundry IQ grounding) ──────────────────────
    ai_search_tool = AzureAISearchTool(
        index_connection_id=SEARCH_CONNECTION_NAME,
        index_name="product-knowledge-base",
    )

    # ── Tool 2: OpenAPI Function tool (via APIM Gateway) ────────────────
    openapi_spec_path = os.path.join(os.path.dirname(__file__), "..", "azure-function", "openapi.json")
    with open(openapi_spec_path, "r") as f:
        openapi_spec = json.load(f)

    # Update the server URL with the APIM gateway URL
    if APIM_GATEWAY_URL:
        openapi_spec["servers"][0]["url"] = f"{APIM_GATEWAY_URL}/inventory"

    openapi_tool = OpenApiTool(
        name="inventory_api",
        description="Real-time product inventory API. Calls go through APIM public gateway which routes internally to a private Azure Function in VNet 2. The Function has no public access.",
        spec=openapi_spec,
        auth=OpenApiAnonymousAuthDetails(),
    )

    # ── Create the Agent ──────────────────────────────────────────────
    agent = client.agents.create_agent(
        model=MODEL_DEPLOYMENT,
        name=AGENT_NAME,
        instructions=AGENT_INSTRUCTIONS,
        tools=[ai_search_tool, openapi_tool],
    )

    print(f"✅ Agent created successfully!")
    print(f"   Agent ID: {agent.id}")
    print(f"   Agent Name: {agent.name}")
    print(f"   Model: {agent.model}")
    print(f"   Tools: {len(agent.tools)} configured")
    print(f"\nSet this environment variable for the React UI:")
    print(f"   AGENT_ID={agent.id}")

    return agent


def test_agent(agent_id: str = None):
    """Quick test to verify the agent works."""
    credential = DefaultAzureCredential()
    client = AIProjectClient(endpoint=PROJECT_ENDPOINT, credential=credential)

    if not agent_id:
        agents = client.agents.list_agents()
        agent = next((a for a in agents.data if a.name == AGENT_NAME), None)
        if not agent:
            print("❌ Agent not found. Run create_agent() first.")
            return
        agent_id = agent.id

    # Create thread and send a test message
    thread = client.agents.create_thread()
    client.agents.create_message(
        thread_id=thread.id,
        role="user",
        content="List all laptops in inventory and check their stock levels.",
    )

    run = client.agents.create_and_process_run(thread_id=thread.id, agent_id=agent_id)
    print(f"\nRun status: {run.status}")

    messages = client.agents.list_messages(thread_id=thread.id)
    for msg in reversed(messages.data):
        if msg.role == "assistant":
            for content in msg.content:
                if hasattr(content, "text"):
                    print(f"\n🤖 Assistant: {content.text.value}")


if __name__ == "__main__":
    import sys

    if len(sys.argv) > 1 and sys.argv[1] == "test":
        agent_id = sys.argv[2] if len(sys.argv) > 2 else None
        test_agent(agent_id)
    else:
        create_agent()
