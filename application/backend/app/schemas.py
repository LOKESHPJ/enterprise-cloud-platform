"""API contracts.

Money is stored as integer minor units (cents) end to end. This removes
floating point rounding from the ordering path entirely.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class ProductBase(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    description: str = Field(default="", max_length=2000)
    price_cents: int = Field(ge=0, le=100_000_000)
    currency: str = Field(default="USD", min_length=3, max_length=3)
    category: str = Field(default="general", max_length=60)
    stock: int = Field(default=0, ge=0)


class ProductCreate(ProductBase):
    pass


class ProductUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=2000)
    price_cents: int | None = Field(default=None, ge=0, le=100_000_000)
    currency: str | None = Field(default=None, min_length=3, max_length=3)
    category: str | None = Field(default=None, max_length=60)
    stock: int | None = Field(default=None, ge=0)


class Product(ProductBase):
    model_config = ConfigDict(from_attributes=True)

    id: str
    created_at: datetime
    updated_at: datetime


class OrderItemIn(BaseModel):
    product_id: str = Field(min_length=1)
    quantity: int = Field(ge=1, le=1000)


class OrderCreate(BaseModel):
    customer_email: EmailStr
    items: list[OrderItemIn] = Field(min_length=1, max_length=50)


class OrderItem(BaseModel):
    product_id: str
    name: str
    quantity: int
    unit_price_cents: int
    subtotal_cents: int


class Order(BaseModel):
    id: str
    customer_email: str  # masked before it leaves the service, so not EmailStr
    items: list[OrderItem]
    total_cents: int
    currency: str = "USD"
    status: Literal["pending", "confirmed", "cancelled"] = "confirmed"
    created_at: datetime


class HealthResponse(BaseModel):
    status: Literal["ok", "degraded"]
    version: str
    environment: str
    storage_backend: str
    storage_healthy: bool
    checked_at: datetime


class ProductPage(BaseModel):
    items: list[Product]
    count: int


class OrderPage(BaseModel):
    items: list[Order]
    count: int
