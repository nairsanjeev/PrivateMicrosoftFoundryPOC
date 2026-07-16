"""
Inventory API - Azure Function deployed in BYO VNet (MCP subnet).
This function is called by the Foundry Agent as a tool to look up
product inventory, check stock levels, and process orders.
Traffic stays within the private VNet.
"""
import json
import logging
import azure.functions as func

# Simulated inventory database
INVENTORY = {
    "LAPTOP-001": {"name": "ThinkPad X1 Carbon", "category": "Laptops", "stock": 45, "price": 1299.99, "warehouse": "East"},
    "LAPTOP-002": {"name": "MacBook Pro 16", "category": "Laptops", "stock": 32, "price": 2499.99, "warehouse": "West"},
    "PHONE-001": {"name": "iPhone 15 Pro", "category": "Phones", "stock": 120, "price": 999.99, "warehouse": "East"},
    "PHONE-002": {"name": "Samsung Galaxy S24", "category": "Phones", "stock": 85, "price": 849.99, "warehouse": "Central"},
    "TABLET-001": {"name": "iPad Air M2", "category": "Tablets", "stock": 67, "price": 599.99, "warehouse": "East"},
    "MONITOR-001": {"name": "Dell UltraSharp 32", "category": "Monitors", "stock": 28, "price": 649.99, "warehouse": "West"},
    "KEYBOARD-001": {"name": "Logitech MX Keys", "category": "Accessories", "stock": 200, "price": 119.99, "warehouse": "Central"},
    "MOUSE-001": {"name": "Logitech MX Master 3S", "category": "Accessories", "stock": 175, "price": 99.99, "warehouse": "Central"},
}


def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Inventory API function processed a request via private VNet.")

    action = req.route_params.get("action", "")

    # GET /api/inventory/list - List all products
    if action == "list" or (not action and req.method == "GET"):
        category = req.params.get("category", "").lower()
        items = list(INVENTORY.values())
        if category:
            items = [i for i in items if i["category"].lower() == category]
        return func.HttpResponse(
            json.dumps({"products": items, "count": len(items), "network": "private-vnet"}),
            mimetype="application/json",
        )

    # GET /api/inventory/check?sku=XXX - Check stock for a product
    if action == "check":
        sku = req.params.get("sku", "").upper()
        if not sku:
            try:
                body = req.get_json()
                sku = body.get("sku", "").upper()
            except ValueError:
                pass
        if sku in INVENTORY:
            product = INVENTORY[sku]
            return func.HttpResponse(
                json.dumps({
                    "sku": sku,
                    "name": product["name"],
                    "in_stock": product["stock"] > 0,
                    "quantity": product["stock"],
                    "warehouse": product["warehouse"],
                    "network": "private-vnet",
                }),
                mimetype="application/json",
            )
        return func.HttpResponse(
            json.dumps({"error": f"Product {sku} not found", "network": "private-vnet"}),
            status_code=404,
            mimetype="application/json",
        )

    # POST /api/inventory/order - Place an order
    if action == "order" and req.method == "POST":
        try:
            body = req.get_json()
        except ValueError:
            return func.HttpResponse(
                json.dumps({"error": "Invalid JSON body"}),
                status_code=400,
                mimetype="application/json",
            )
        sku = body.get("sku", "").upper()
        quantity = body.get("quantity", 1)
        if sku not in INVENTORY:
            return func.HttpResponse(
                json.dumps({"error": f"Product {sku} not found"}),
                status_code=404,
                mimetype="application/json",
            )
        product = INVENTORY[sku]
        if product["stock"] < quantity:
            return func.HttpResponse(
                json.dumps({
                    "error": "Insufficient stock",
                    "available": product["stock"],
                    "requested": quantity,
                }),
                status_code=400,
                mimetype="application/json",
            )
        return func.HttpResponse(
            json.dumps({
                "order_id": f"ORD-{sku}-{quantity}",
                "sku": sku,
                "name": product["name"],
                "quantity": quantity,
                "total_price": product["price"] * quantity,
                "status": "confirmed",
                "warehouse": product["warehouse"],
                "network": "private-vnet",
            }),
            mimetype="application/json",
        )

    # GET /api/inventory/health - Health check
    if action == "health":
        return func.HttpResponse(
            json.dumps({"status": "healthy", "network": "private-vnet", "subnet": "mcp-subnet"}),
            mimetype="application/json",
        )

    return func.HttpResponse(
        json.dumps({
            "error": "Unknown action",
            "available_actions": ["list", "check", "order", "health"],
        }),
        status_code=400,
        mimetype="application/json",
    )
