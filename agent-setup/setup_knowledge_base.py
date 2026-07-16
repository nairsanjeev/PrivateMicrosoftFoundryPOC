"""
Upload sample knowledge base documents to AI Search.
This creates the index and populates it with product docs,
policies, and FAQ content for the Foundry IQ grounding.
"""
import os
import json
from azure.identity import DefaultAzureCredential
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.indexes.models import (
    SearchIndex,
    SimpleField,
    SearchableField,
    SearchFieldDataType,
    SemanticConfiguration,
    SemanticField,
    SemanticPrioritizedFields,
    SemanticSearch,
)

SEARCH_ENDPOINT = os.environ.get("SEARCH_ENDPOINT", "")
INDEX_NAME = "product-knowledge-base"

DOCUMENTS = [
    {
        "id": "1",
        "title": "Return Policy",
        "category": "Policies",
        "content": """Our return policy allows returns within 30 days of purchase for a full refund. 
        Products must be in original packaging and unused condition. Electronics with opened 
        software seals are subject to a 15% restocking fee. Enterprise bulk orders (10+ units) 
        have a 60-day return window. Contact support@techcorp.example for return authorization. 
        Refunds are processed within 5-7 business days after receiving the returned item.""",
    },
    {
        "id": "2",
        "title": "Warranty Information",
        "category": "Policies",
        "content": """All products come with a standard 1-year manufacturer warranty covering 
        defects in materials and workmanship. Extended warranties are available: 2-year ($49.99) 
        and 3-year ($79.99). Warranty claims must be filed through our portal at 
        warranty.techcorp.example. Accidental damage is not covered under standard warranty 
        but is included in our Premium Protection Plan ($129.99/year). Battery replacements 
        are covered for the first 18 months.""",
    },
    {
        "id": "3",
        "title": "ThinkPad X1 Carbon Specifications",
        "category": "Product Specs",
        "content": """ThinkPad X1 Carbon Gen 12 - SKU: LAPTOP-001
        Processor: Intel Core Ultra 7 155H, 16 cores
        Memory: 32GB LPDDR5x-6400
        Storage: 1TB PCIe Gen4 NVMe SSD
        Display: 14" 2.8K OLED, 120Hz, 400 nits
        Battery: 57Wh, up to 15 hours
        Weight: 2.48 lbs (1.12 kg)
        Ports: 2x Thunderbolt 4, 2x USB-A, HDMI 2.1, 3.5mm
        OS: Windows 11 Pro
        Ideal for business professionals requiring portability and performance.""",
    },
    {
        "id": "4",
        "title": "MacBook Pro 16 Specifications",
        "category": "Product Specs",
        "content": """MacBook Pro 16-inch M4 Pro - SKU: LAPTOP-002
        Chip: Apple M4 Pro, 14-core CPU, 20-core GPU
        Memory: 48GB unified memory
        Storage: 1TB SSD
        Display: 16.2" Liquid Retina XDR, 3456x2234, 120Hz ProMotion
        Battery: Up to 24 hours
        Weight: 4.7 lbs (2.14 kg)
        Ports: 3x Thunderbolt 5, HDMI, SD slot, MagSafe 3
        OS: macOS Sequoia
        Best for creative professionals: video editing, 3D rendering, ML development.""",
    },
    {
        "id": "5",
        "title": "Shipping Information",
        "category": "Policies",
        "content": """Standard shipping: 5-7 business days (free for orders over $50). 
        Express shipping: 2-3 business days ($14.99). 
        Next-day shipping: Available for orders placed before 2 PM EST ($29.99).
        Enterprise accounts get free express shipping on all orders.
        We ship to all 50 US states and select international destinations.
        Tracking information is sent via email within 24 hours of shipment.
        Bulk orders (25+ units) ship via freight and require 7-10 business days.""",
    },
    {
        "id": "6",
        "title": "Enterprise Purchasing Program",
        "category": "Programs",
        "content": """Our Enterprise Purchasing Program offers volume discounts:
        10-24 units: 5% discount
        25-49 units: 10% discount
        50-99 units: 15% discount
        100+ units: Custom pricing (contact enterprise@techcorp.example)
        
        Enterprise benefits include: dedicated account manager, priority support (4-hour 
        SLA), custom imaging services, asset tagging, and quarterly business reviews.
        Net-30 payment terms available for approved accounts.""",
    },
    {
        "id": "7",
        "title": "Technical Support Tiers",
        "category": "Support",
        "content": """Support Tier 1 (Basic - included): Email support, 24-hour response time, 
        knowledge base access, community forums.
        
        Support Tier 2 (Professional - $19.99/month): Phone + chat support, 4-hour response 
        time during business hours, remote diagnostics.
        
        Support Tier 3 (Enterprise - $49.99/month): 24/7 phone support, 1-hour response time, 
        on-site support available, dedicated engineer, proactive monitoring.
        
        All tiers include access to firmware updates and driver downloads.""",
    },
    {
        "id": "8",
        "title": "iPhone 15 Pro Specifications",
        "category": "Product Specs",
        "content": """iPhone 15 Pro - SKU: PHONE-001
        Chip: A17 Pro
        Display: 6.1" Super Retina XDR, 2556x1179, 120Hz ProMotion
        Storage: 256GB
        Camera: 48MP Main + 12MP Ultra Wide + 12MP Telephoto (3x optical zoom)
        Battery: Up to 23 hours video playback
        5G capable, USB-C, Titanium frame
        Colors: Natural, Blue, White, Black
        Water resistant: IP68 (6m for 30 min)
        Perfect for professionals needing a powerful, compact device.""",
    },
]


def setup_index():
    credential = DefaultAzureCredential()
    index_client = SearchIndexClient(endpoint=SEARCH_ENDPOINT, credential=credential)

    fields = [
        SimpleField(name="id", type=SearchFieldDataType.String, key=True),
        SearchableField(name="title", type=SearchFieldDataType.String),
        SimpleField(name="category", type=SearchFieldDataType.String, filterable=True),
        SearchableField(name="content", type=SearchFieldDataType.String),
    ]

    semantic_config = SemanticConfiguration(
        name="default",
        prioritized_fields=SemanticPrioritizedFields(
            title_field=SemanticField(field_name="title"),
            content_fields=[SemanticField(field_name="content")],
        ),
    )

    index = SearchIndex(
        name=INDEX_NAME,
        fields=fields,
        semantic_search=SemanticSearch(configurations=[semantic_config]),
    )

    index_client.create_or_update_index(index)
    print(f"✅ Index '{INDEX_NAME}' created/updated")

    # Upload documents
    search_client = SearchClient(
        endpoint=SEARCH_ENDPOINT, index_name=INDEX_NAME, credential=credential
    )
    result = search_client.upload_documents(documents=DOCUMENTS)
    print(f"✅ Uploaded {len(DOCUMENTS)} documents")
    for r in result:
        print(f"   {r.key}: {r.succeeded}")


if __name__ == "__main__":
    setup_index()
