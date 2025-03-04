-- Query 1
CREATE INDEX idx_orders_customer_id ON orders (customer_id);
CREATE INDEX idx_products_id ON products (id);
CREATE INDEX idx_customers_email ON customers (email);

-- Query 2
-- Original query
SELECT * FROM orders
WHERE customer_id IN (SELECT id FROM customers WHERE email = 'example@example.com');

-- Optimized query
SELECT o.* FROM orders o
INNER JOIN customers c ON o.customer_id = c.id
WHERE c.email = 'example@example.com';

-- Query 3
CREATE TABLE order_items (
  id SERIAL PRIMARY KEY,
  order_id INTEGER NOT NULL REFERENCES orders (id),
  product_id INTEGER NOT NULL REFERENCES products (id),
  quantity INTEGER NOT NULL
);

CREATE TABLE product_categories (
  id SERIAL PRIMARY KEY,
  name VARCHAR(50) NOT NULL
);

ALTER TABLE products
ADD COLUMN category_id INTEGER REFERENCES product_categories (id);

