"""Storage abstraction.

The application layer only ever talks to this interface, which is what lets the
identical codebase run against DynamoDB on Lambda and PostgreSQL on ECS.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any


class Repository(ABC):
    """Persistence contract shared by every backend implementation."""

    backend_name: str = "unknown"

    @abstractmethod
    def health(self) -> bool:
        """Return True when the backing store answers a trivial round trip."""

    @abstractmethod
    def list_products(self, limit: int = 50) -> list[dict[str, Any]]: ...

    @abstractmethod
    def get_product(self, product_id: str) -> dict[str, Any] | None: ...

    @abstractmethod
    def create_product(self, data: dict[str, Any]) -> dict[str, Any]: ...

    @abstractmethod
    def update_product(
        self, product_id: str, patch: dict[str, Any]
    ) -> dict[str, Any] | None: ...

    @abstractmethod
    def delete_product(self, product_id: str) -> bool: ...

    @abstractmethod
    def list_orders(self, limit: int = 50) -> list[dict[str, Any]]: ...

    @abstractmethod
    def get_order(self, order_id: str) -> dict[str, Any] | None: ...

    @abstractmethod
    def create_order(self, data: dict[str, Any]) -> dict[str, Any]: ...
