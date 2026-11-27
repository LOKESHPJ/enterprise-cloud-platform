import { useCallback, useEffect, useMemo, useState } from "react";
import { api, ApiError } from "./api";
import type { CartLine, Health, Order, Product } from "./types";

const money = (cents: number, currency = "USD") =>
  new Intl.NumberFormat("en-US", { style: "currency", currency }).format(cents / 100);

const shortDate = (value: string) =>
  new Date(value).toLocaleString(undefined, {
    month: "short",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });

type Tab = "catalogue" | "orders";

export default function App() {
  const [tab, setTab] = useState<Tab>("catalogue");
  const [products, setProducts] = useState<Product[]>([]);
  const [orders, setOrders] = useState<Order[]>([]);
  const [cart, setCart] = useState<CartLine[]>([]);
  const [email, setEmail] = useState("test@example.com");
  const [health, setHealth] = useState<Health | null>(null);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const loadCatalogue = useCallback(async () => {
    try {
      const [productPage, healthPayload] = await Promise.all([
        api.products(),
        api.health().catch(() => null),
      ]);
      setProducts(productPage.items);
      setHealth(healthPayload);
      setError(null);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Unable to reach the API");
    }
  }, []);

  const loadOrders = useCallback(async () => {
    try {
      const page = await api.orders();
      setOrders(page.items);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Unable to load orders");
    }
  }, []);

  useEffect(() => {
    (async () => {
      setLoading(true);
      await Promise.all([loadCatalogue(), loadOrders()]);
      setLoading(false);
    })();
  }, [loadCatalogue, loadOrders]);

  const totalCents = useMemo(
    () => cart.reduce((sum, line) => sum + line.product.price_cents * line.quantity, 0),
    [cart],
  );

  function addToCart(product: Product) {
    setNotice(null);
    setCart((current) => {
      const existing = current.find((line) => line.product.id === product.id);
      if (existing) {
        return current.map((line) =>
          line.product.id === product.id
            ? { ...line, quantity: Math.min(line.quantity + 1, product.stock) }
            : line,
        );
      }
      return [...current, { product, quantity: 1 }];
    });
  }

  function setQuantity(productId: string, quantity: number) {
    setCart((current) =>
      current
        .map((line) => (line.product.id === productId ? { ...line, quantity } : line))
        .filter((line) => line.quantity > 0),
    );
  }

  async function submitOrder() {
    if (!cart.length) return;
    setSubmitting(true);
    setError(null);
    setNotice(null);
    try {
      const order = await api.createOrder(
        email,
        cart.map((line) => ({ product_id: line.product.id, quantity: line.quantity })),
      );
      setCart([]);
      setNotice(`Order ${order.id.slice(0, 8)} confirmed for ${money(order.total_cents)}`);
      await loadOrders();
      setTab("orders");
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Order could not be placed");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="shell">
      <header className="topbar">
        <div className="brand">
          <span className="mark" aria-hidden="true" />
          <div>
            <h1>Enterprise Cloud Platform</h1>
            <p className="subtitle">Catalogue &amp; order service</p>
          </div>
        </div>

        <div className="status" title="Live response from /api/health">
          <span className={`dot ${health?.storage_healthy ? "ok" : "warn"}`} />
          <span>
            {health ? `${health.storage_backend} · ${health.environment}` : "connecting"}
          </span>
          <span className="version">v{health?.version ?? "—"}</span>
        </div>
      </header>

      <nav className="tabs" role="tablist">
        <button
          role="tab"
          aria-selected={tab === "catalogue"}
          className={tab === "catalogue" ? "active" : ""}
          onClick={() => setTab("catalogue")}
        >
          Catalogue <span className="count">{products.length}</span>
        </button>
        <button
          role="tab"
          aria-selected={tab === "orders"}
          className={tab === "orders" ? "active" : ""}
          onClick={() => {
            setTab("orders");
            void loadOrders();
          }}
        >
          Orders <span className="count">{orders.length}</span>
        </button>
      </nav>

      {error && (
        <div className="banner error" role="alert">
          {error}
        </div>
      )}
      {notice && <div className="banner success">{notice}</div>}

      {tab === "catalogue" && (
        <main className="layout">
          <section className="panel">
            <div className="panel-head">
              <h2>Products</h2>
              <span className="hint">Prices are read from the API at checkout</span>
            </div>

            {loading ? (
              <p className="muted">Loading catalogue…</p>
            ) : (
              <ul className="grid">
                {products.map((product) => (
                  <li key={product.id} className="card">
                    <div className="card-top">
                      <span className="pill">{product.category}</span>
                      <span className={product.stock > 0 ? "stock" : "stock out"}>
                        {product.stock > 0 ? `${product.stock} in stock` : "out of stock"}
                      </span>
                    </div>
                    <h3>{product.name}</h3>
                    <p className="desc">{product.description}</p>
                    <div className="card-bottom">
                      <strong>{money(product.price_cents, product.currency)}</strong>
                      <button
                        className="ghost"
                        disabled={product.stock < 1}
                        onClick={() => addToCart(product)}
                      >
                        Add
                      </button>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <aside className="panel cart">
            <div className="panel-head">
              <h2>Checkout</h2>
            </div>

            {cart.length === 0 ? (
              <p className="muted">Cart is empty. Add a product to price an order.</p>
            ) : (
              <ul className="cart-lines">
                {cart.map((line) => (
                  <li key={line.product.id}>
                    <div>
                      <span className="line-name">{line.product.name}</span>
                      <span className="line-price">
                        {money(line.product.price_cents, line.product.currency)} each
                      </span>
                    </div>
                    <input
                      type="number"
                      min={0}
                      max={line.product.stock}
                      value={line.quantity}
                      aria-label={`Quantity for ${line.product.name}`}
                      onChange={(event) =>
                        setQuantity(line.product.id, Number(event.target.value))
                      }
                    />
                  </li>
                ))}
              </ul>
            )}

            <label className="field">
              <span>Customer email</span>
              <input
                type="email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
              />
            </label>

            <div className="total">
              <span>Order total</span>
              <strong>{money(totalCents)}</strong>
            </div>

            <button
              className="primary"
              disabled={!cart.length || submitting}
              onClick={() => void submitOrder()}
            >
              {submitting ? "Placing order…" : "Place order"}
            </button>
          </aside>
        </main>
      )}

      {tab === "orders" && (
        <main className="panel">
          <div className="panel-head">
            <h2>Recent orders</h2>
            <button className="ghost" onClick={() => void loadOrders()}>
              Refresh
            </button>
          </div>

          {orders.length === 0 ? (
            <p className="muted">No orders yet.</p>
          ) : (
            <table className="table">
              <thead>
                <tr>
                  <th>Order</th>
                  <th>Customer</th>
                  <th>Items</th>
                  <th>Total</th>
                  <th>Status</th>
                  <th>Placed</th>
                </tr>
              </thead>
              <tbody>
                {orders.map((order) => (
                  <tr key={order.id}>
                    <td className="mono">{order.id.slice(0, 8)}</td>
                    <td>{order.customer_email}</td>
                    <td>{order.items.reduce((sum, item) => sum + item.quantity, 0)}</td>
                    <td>{money(order.total_cents, order.currency)}</td>
                    <td>
                      <span className="pill">{order.status}</span>
                    </td>
                    <td className="muted">{shortDate(order.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </main>
      )}

      <footer className="footer">
        <span>API: {api.base || "same origin"}</span>
        <a href={`${api.base}/api/docs`} target="_blank" rel="noreferrer">
          OpenAPI docs
        </a>
      </footer>
    </div>
  );
}
