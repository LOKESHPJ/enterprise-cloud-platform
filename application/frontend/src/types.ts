export interface Product {
  id: string;
  name: string;
  description: string;
  price_cents: number;
  currency: string;
  category: string;
  stock: number;
  created_at: string;
  updated_at: string;
}

export interface ProductPage {
  items: Product[];
  count: number;
}

export interface OrderItem {
  product_id: string;
  name: string;
  quantity: number;
  unit_price_cents: number;
  subtotal_cents: number;
}

export interface Order {
  id: string;
  customer_email: string;
  items: OrderItem[];
  total_cents: number;
  currency: string;
  status: string;
  created_at: string;
}

export interface OrderPage {
  items: Order[];
  count: number;
}

export interface Health {
  status: "ok" | "degraded";
  version: string;
  environment: string;
  storage_backend: string;
  storage_healthy: boolean;
  checked_at: string;
}

export interface CartLine {
  product: Product;
  quantity: number;
}
