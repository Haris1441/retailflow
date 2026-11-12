"""Independent deterministic source records."""

from datetime import datetime, timedelta, timezone

KEYS = {
    "orders": "order_id", "customers": "customer_id", "payments": "payment_id",
    "events": "event_id", "inventory": "inventory_id",
}

BASE = datetime(2025, 1, 1, tzinfo=timezone.utc)
PRODUCT_CROSSWALK = {"API-PRODUCT-1": 1, "API-PRODUCT-2": 2}
STORE_CROSSWALK = {"API-WEB-US": 2}


def timestamp(day: int) -> str:
    return (BASE + timedelta(days=day)).isoformat()


def build_fixtures() -> dict[str, list[dict]]:
    rows = {name: [] for name in ("orders", "customers", "payments", "events", "inventory")}
    for n in range(1, 9):
        customer_id = f"API-CUSTOMER-{n:03}"
        order_id = f"API-ORDER-{n:03}"
        payment_id = f"API-PAYMENT-{n:03}"
        created = timestamp(n)
        updated = timestamp(14 if n == 1 else n)
        product_id = f"API-PRODUCT-{1 + n % 2}"
        payment = {
            "payment_id": payment_id, "order_id": order_id,
            "payment_status": "SUCCESS", "payment_amount": "26.00",
            "payment_currency": "USD", "payment_method": "CARD",
            "payment_timestamp": created, "updated_at": updated,
        }
        rows["customers"].append({
            "customer_id": customer_id, "email": f"api{n}@example.invalid",
            "created_at": created, "updated_at": updated,
        })
        rows["orders"].append({
            "order_id": order_id, "customer_id": customer_id,
            "customer": {"customer_id": customer_id},
            "store_id": "API-WEB-US", "order_channel": "WEB",
            "order_date": created, "created_at": created, "updated_at": updated,
            "fulfilled_at": timestamp(n + 1), "order_status": "COMPLETED",
            "currency": "USD", "order_total": "26.00",
            "discount_amount": "0.00", "shipping_amount": "4.00", "tax_amount": "2.00",
            "items": [
                {
                    "order_item_id": f"{order_id}-1", "product_id": product_id,
                    "quantity": 1, "unit_price": "15.00", "discount_amount": "2.00",
                    "tax_amount": "1.00", "line_total": "14.00",
                    "discounts": [{"discount_id": "WELCOME", "amount": "2.00"}],
                },
                {
                    "order_item_id": f"{order_id}-2", "product_id": product_id,
                    "quantity": 1, "unit_price": "7.00", "discount_amount": "0.00",
                    "tax_amount": "1.00", "line_total": "8.00", "discounts": [],
                },
            ],
            "shipping": {"shipment_id": f"{order_id}-S1", "method": "STANDARD", "amount": "4.00"},
            "payments": [{"payment_id": payment_id, "method": "CARD"}],
        })
        rows["payments"].append(payment)
        rows["events"].append({
            "event_id": f"API-EVENT-{n:03}", "customer_id": customer_id,
            "event_timestamp": created, "event_type": "purchase_completed",
            "updated_at": updated,
            "event_payload": {
                "device": {"type": "mobile"},
                "session": {"session_id": f"API-SESSION-{n:03}"},
                "campaign": {"channel": "organic"},
                "products": [{"product_id": product_id}],
            },
        })
        rows["inventory"].append({
            "inventory_id": f"API-STOCK-{n:03}", "store_id": "API-WEB-US",
            "product_id": product_id, "snapshot_date": created[:10],
            "quantity_on_hand": 20 + n, "reserved_quantity": n,
            "reorder_level": 10, "updated_at": updated,
        })
    return rows
