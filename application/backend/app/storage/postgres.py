"""PostgreSQL implementation of the storage contract (ECS Fargate track).

Used when STORAGE_BACKEND=postgres. Schema is created and seeded on first use so
the deployment has no separate migration step to babysit. Order line items live
in a JSONB column, which keeps the demo schema small while still being a normal
relational design for the header rows.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import (
    JSON,
    DateTime,
    Integer,
    String,
    Text,
    create_engine,
    delete,
    func,
    select,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker

from app.config import settings
from app.storage.base import Repository

SEED_PRODUCTS = [
    {
        "name": "Aurora Desk Lamp",
        "description": "Warm dimmable LED lamp with a machined aluminium base.",
        "price_cents": 8900,
        "category": "lighting",
        "stock": 42,
    },
    {
        "name": "Orbit Wireless Headphones",
        "description": "Over-ear ANC headphones, 40 hour battery.",
        "price_cents": 24900,
        "category": "audio",
        "stock": 18,
    },
    {
        "name": "Slate Mechanical Keyboard",
        "description": "75 percent layout, hot-swap switches, PBT caps.",
        "price_cents": 13500,
        "category": "peripherals",
        "stock": 27,
    },
    {
        "name": "Nimbus Standing Mat",
        "description": "Anti-fatigue mat for standing desks.",
        "price_cents": 6900,
        "category": "furniture",
        "stock": 60,
    },
]


class Base(DeclarativeBase):
    pass


class ProductRow(Base):
    __tablename__ = "products"

    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str] = mapped_column(Text, default="")
    price_cents: Mapped[int] = mapped_column(Integer, nullable=False)
    currency: Mapped[str] = mapped_column(String(3), default="USD")
    category: Mapped[str] = mapped_column(String(60), default="general")
    stock: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "description": self.description or "",
            "price_cents": int(self.price_cents),
            "currency": self.currency,
            "category": self.category,
            "stock": int(self.stock),
            "created_at": self.created_at,
            "updated_at": self.updated_at,
        }


class OrderRow(Base):
    __tablename__ = "orders"

    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    customer_email: Mapped[str] = mapped_column(String(320), nullable=False)
    items: Mapped[list[dict[str, Any]]] = mapped_column(JSON, nullable=False)
    total_cents: Mapped[int] = mapped_column(Integer, nullable=False)
    currency: Mapped[str] = mapped_column(String(3), default="USD")
    status: Mapped[str] = mapped_column(String(20), default="confirmed")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "customer_email": self.customer_email,
            "items": self.items,
            "total_cents": int(self.total_cents),
            "currency": self.currency,
            "status": self.status,
            "created_at": self.created_at,
        }


class PostgresRepository(Repository):
    backend_name = "postgres"

    def __init__(self, database_url: str | None = None) -> None:
        url = database_url or settings.database_url
        if not url:
            raise RuntimeError("DATABASE_URL is required for the postgres backend")
        self._engine = create_engine(
            url,
            pool_pre_ping=True,
            pool_size=5,
            max_overflow=5,
            pool_recycle=1800,
        )
        self._session: sessionmaker[Session] = sessionmaker(bind=self._engine)
        self._bootstrap()

    # -------------------------------------------------------------- bootstrap
    def _bootstrap(self) -> None:
        Base.metadata.create_all(self._engine)
        with self._session() as session:
            existing = session.scalar(select(func.count()).select_from(ProductRow))
            if existing:
                return
            stamp = datetime.now(timezone.utc)
            session.add_all(
                [
                    ProductRow(
                        id=uuid.uuid4().hex,
                        created_at=stamp,
                        updated_at=stamp,
                        currency="USD",
                        **product,
                    )
                    for product in SEED_PRODUCTS
                ]
            )
            session.commit()

    def health(self) -> bool:
        try:
            with self._session() as session:
                session.execute(select(1))
            return True
        except Exception:
            return False

    # --------------------------------------------------------------- products
    def list_products(self, limit: int = 50) -> list[dict[str, Any]]:
        with self._session() as session:
            rows = session.scalars(
                select(ProductRow).order_by(ProductRow.created_at.desc()).limit(limit)
            ).all()
            return [row.to_dict() for row in rows]

    def get_product(self, product_id: str) -> dict[str, Any] | None:
        with self._session() as session:
            row = session.get(ProductRow, product_id)
            return row.to_dict() if row else None

    def create_product(self, data: dict[str, Any]) -> dict[str, Any]:
        stamp = datetime.now(timezone.utc)
        with self._session() as session:
            row = ProductRow(
                id=data.get("id") or uuid.uuid4().hex,
                currency=data.get("currency", "USD"),
                created_at=stamp,
                updated_at=stamp,
                **{k: v for k, v in data.items() if k not in {"id", "currency"}},
            )
            session.add(row)
            session.commit()
            session.refresh(row)
            return row.to_dict()

    def update_product(
        self, product_id: str, patch: dict[str, Any]
    ) -> dict[str, Any] | None:
        with self._session() as session:
            row = session.get(ProductRow, product_id)
            if row is None:
                return None
            for key, value in patch.items():
                if hasattr(row, key):
                    setattr(row, key, value)
            row.updated_at = datetime.now(timezone.utc)
            session.commit()
            session.refresh(row)
            return row.to_dict()

    def delete_product(self, product_id: str) -> bool:
        with self._session() as session:
            result = session.execute(
                delete(ProductRow).where(ProductRow.id == product_id)
            )
            session.commit()
            return bool(result.rowcount)

    # ----------------------------------------------------------------- orders
    def list_orders(self, limit: int = 50) -> list[dict[str, Any]]:
        with self._session() as session:
            rows = session.scalars(
                select(OrderRow).order_by(OrderRow.created_at.desc()).limit(limit)
            ).all()
            return [row.to_dict() for row in rows]

    def get_order(self, order_id: str) -> dict[str, Any] | None:
        with self._session() as session:
            row = session.get(OrderRow, order_id)
            return row.to_dict() if row else None

    def create_order(self, data: dict[str, Any]) -> dict[str, Any]:
        with self._session() as session:
            row = OrderRow(
                id=data.get("id") or uuid.uuid4().hex,
                customer_email=data["customer_email"],
                items=data["items"],
                total_cents=data["total_cents"],
                currency=data.get("currency", "USD"),
                status=data.get("status", "confirmed"),
                created_at=datetime.now(timezone.utc),
            )
            session.add(row)
            session.commit()
            session.refresh(row)
            return row.to_dict()
