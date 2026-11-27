import type { Health, Order, OrderPage, Product, ProductPage } from "./types";

const BASE = (import.meta.env.VITE_API_BASE_URL ?? "").replace(/\/$/, "");

class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${BASE}${path}`, {
    headers: { "Content-Type": "application/json" },
    ...init,
  });

  if (!response.ok) {
    let detail = `${response.status} ${response.statusText}`;
    try {
      const body = (await response.json()) as { detail?: string };
      if (body.detail) detail = body.detail;
    } catch {
      /* non JSON error body */
    }
    throw new ApiError(detail, response.status);
  }

  if (response.status === 204) return undefined as T;
  return (await response.json()) as T;
}

export const api = {
  base: BASE,
  health: () => request<Health>("/api/health"),
  products: () => request<ProductPage>("/api/products?limit=100"),
  orders: () => request<OrderPage>("/api/orders?limit=50"),
  createOrder: (customer_email: string, items: { product_id: string; quantity: number }[]) =>
    request<Order>("/api/orders", {
      method: "POST",
      body: JSON.stringify({ customer_email, items }),
    }),
};

export { ApiError };
export type { Product };
