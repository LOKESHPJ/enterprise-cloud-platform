from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query, status

from app.schemas import Order, OrderCreate, OrderPage
from app.storage import get_repository

router = APIRouter(prefix="/orders", tags=["orders"])


@router.get("", response_model=OrderPage)
def list_orders(limit: int = Query(default=50, ge=1, le=200)) -> OrderPage:
    items = get_repository().list_orders(limit=limit)
    return OrderPage(items=items, count=len(items))


@router.post("", response_model=Order, status_code=status.HTTP_201_CREATED)
def create_order(payload: OrderCreate) -> Order:
    """Price the order server side.

    Client supplied prices are never trusted: unit prices are read from the
    product catalogue at checkout time.
    """
    repo = get_repository()
    line_items: list[dict] = []
    total_cents = 0
    currency = "USD"

    for requested in payload.items:
        product = repo.get_product(requested.product_id)
        if product is None:
            raise HTTPException(
                status.HTTP_404_NOT_FOUND,
                f"product {requested.product_id} not found",
            )
        if int(product.get("stock", 0)) < requested.quantity:
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                f"insufficient stock for {product['name']}",
            )
        subtotal = int(product["price_cents"]) * requested.quantity
        currency = product.get("currency", currency)
        line_items.append(
            {
                "product_id": product["id"],
                "name": product["name"],
                "quantity": requested.quantity,
                "unit_price_cents": int(product["price_cents"]),
                "subtotal_cents": subtotal,
            }
        )
        total_cents += subtotal

    created = repo.create_order(
        {
            "customer_email": str(payload.customer_email),
            "items": line_items,
            "total_cents": total_cents,
            "currency": currency,
            "status": "confirmed",
        }
    )
    return Order.model_validate(created)


@router.get("/{order_id}", response_model=Order)
def get_order(order_id: str) -> Order:
    found = get_repository().get_order(order_id)
    if found is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "order not found")
    return Order.model_validate(found)
