-- Query 1
CREATE INDEX idx_customers_id ON customers (id);
CREATE INDEX idx_orders_customer_id ON orders (customer_id);
CREATE INDEX idx_products_id ON products (id);
CREATE INDEX idx_orders_order_date ON orders (order_date);

-- Query 2
-- Before
SELECT * FROM customers WHERE id IN (SELECT customer_id FROM orders);

-- After
SELECT c.* 
FROM customers c 
INNER JOIN orders o ON c.id = o.customer_id;

-- Query 3
CREATE TABLE order_items (
  id SERIAL PRIMARY KEY,
  order_id INTEGER NOT NULL,
  product_id INTEGER NOT NULL,
  quantity INTEGER NOT NULL,
  FOREIGN KEY (order_id) REFERENCES orders (id),
  FOREIGN KEY (product_id) REFERENCES products (id)
);

CREATE TABLE addresses (
  id SERIAL PRIMARY KEY,
  customer_id INTEGER NOT NULL,
  address TEXT NOT NULL,
  FOREIGN KEY (customer_id) REFERENCES customers (id)
);

