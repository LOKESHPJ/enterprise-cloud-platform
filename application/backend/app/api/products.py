"""Catalogue endpoints.

The catalogue is read-only over HTTP on purpose. It is reference data owned by
the platform, seeded by the function itself on first use. Removing the write and
delete routes means an anonymous visitor cannot deface the storefront or empty
the catalogue; there is no destructive verb exposed to the internet at all.
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query, status

from app.schemas import Product, ProductPage
from app.storage import get_repository

router = APIRouter(prefix="/products", tags=["products"])


@router.get("", response_model=ProductPage)
def list_products(limit: int = Query(default=50, ge=1, le=200)) -> ProductPage:
    items = get_repository().list_products(limit=limit)
    return ProductPage(items=items, count=len(items))


@router.get("/{product_id}", response_model=Product)
def get_product(product_id: str) -> Product:
    found = get_repository().get_product(product_id)
    if found is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "product not found")
    return Product.model_validate(found)
