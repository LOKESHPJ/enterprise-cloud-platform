from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query, status

from app.schemas import Product, ProductCreate, ProductPage, ProductUpdate
from app.storage import get_repository

router = APIRouter(prefix="/products", tags=["products"])


@router.get("", response_model=ProductPage)
def list_products(limit: int = Query(default=50, ge=1, le=200)) -> ProductPage:
    items = get_repository().list_products(limit=limit)
    return ProductPage(items=items, count=len(items))


@router.post("", response_model=Product, status_code=status.HTTP_201_CREATED)
def create_product(payload: ProductCreate) -> Product:
    created = get_repository().create_product(payload.model_dump())
    return Product.model_validate(created)


@router.get("/{product_id}", response_model=Product)
def get_product(product_id: str) -> Product:
    found = get_repository().get_product(product_id)
    if found is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "product not found")
    return Product.model_validate(found)


@router.patch("/{product_id}", response_model=Product)
def update_product(product_id: str, payload: ProductUpdate) -> Product:
    patch = payload.model_dump(exclude_unset=True, exclude_none=True)
    updated = get_repository().update_product(product_id, patch)
    if updated is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "product not found")
    return Product.model_validate(updated)


@router.delete("/{product_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_product(product_id: str) -> None:
    if not get_repository().delete_product(product_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "product not found")
