--1
CREATE TABLE employees (
    employee_id INT,
    first_name TEXT,
    last_name TEXT,
    age INTEGER CHECK (age BETWEEN 18 AND 65),
    salary NUMERIC CHECK (salary > 0)
);

CREATE TABLE products_catalog (
    product_id INT,
    product_name TEXT,
    regular_price NUMERIC,
    discount_price NUMERIC,
    CONSTRAINT valid_discount CHECK (
        regular_price > 0
        AND discount_price > 0
        AND discount_price < regular_price
    )
);

CREATE TABLE bookings (
    booking_id INT,
    check_in_date DATE,
    check_out_date DATE,
    num_guests INTEGER CHECK (num_guests BETWEEN 1 AND 10),
    CHECK (check_out_date > check_in_date)
);
--TASK 1.4
INSERT INTO employees VALUES (1, 'John', 'Smith', 30, 2000);
INSERT INTO employees VALUES (2, 'Sarah', 'Johnson', 45, 3500);
INSERT INTO employees VALUES (3, 'Michael', 'Brown', 16, 1800); 

INSERT INTO products_catalog VALUES (1, 'Phone', 1000, 800);
INSERT INTO products_catalog VALUES (2, 'Laptop', 700, 500);
INSERT INTO products_catalog VALUES (3, 'TV', 0, 200); 

INSERT INTO bookings VALUES (1, '2025-01-01', '2026-01-05', 2);
INSERT INTO bookings VALUES (2, '2025-02-16', '2026-04-05', 5);
INSERT INTO bookings VALUES (3, '2025-12-11', '2025-05-05', 0); 

--2
CREATE TABLE customers (
    customer_id INT NOT NULL,
    email TEXT NOT NULL,
    phone TEXT,
    registration_date DATE NOT NULL
);


CREATE TABLE inventory (
    item_id INT NOT NULL,
    item_name TEXT NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity >= 0),
    unit_price NUMERIC NOT NULL CHECK (unit_price > 0),
    last_updated TIMESTAMP NOT NULL
);


INSERT INTO customers VALUES (1, 'example@gmail.com', '777-123-4567', '2025-10-10');
INSERT INTO customers VALUES (NULL, 'example2@gmail.com', NULL, '2025-11-22');

INSERT INTO inventory VALUES (1, 'Laptop', 10, 1200, '2025-05-01 5:00:00');
INSERT INTO inventory VALUES (2, NULL, 0, 30, '2025-05-03 10:00:00');

-- 3
CREATE TABLE users (
    user_id INT,
    username TEXT UNIQUE,
    email TEXT UNIQUE,
    created_at TIMESTAMP
);


CREATE TABLE course_enrollments (
    enrollment_id INT,
    student_id INT,
    course_code TEXT,
    semester TEXT,
    UNIQUE (student_id, course_code, semester)
);


ALTER TABLE users
ADD CONSTRAINT unique_username UNIQUE (username);

ALTER TABLE users
ADD CONSTRAINT unique_email UNIQUE (email);

INSERT INTO users VALUES (1, 'miha', 'miha@gmail.com', '2025-06-01 00:00:00');
INSERT INTO users VALUES (2, 'katy', 'katy@gmail.com', '2025-06-02 01:00:00');
INSERT INTO users VALUES (3, 'mark', 'mark@gmail.com', '2025-06-03 02:00:00');
INSERT INTO users VALUES (4, 'john', 'john@gmail.com', '2025-06-03 03:00:00');

--4
CREATE TABLE departments (
    dept_id INT PRIMARY KEY,
    dept_name TEXT NOT NULL,
    location TEXT
);

CREATE TABLE student_courses (
    student_id INT,
    course_id INT,
    enrollment_date DATE,
    grade TEXT,
    PRIMARY KEY (student_id, course_id)
);

/*
1
- PRIMARY KEY = UNIQUE + NOT NULL (only one per table)
- UNIQUE allows NULLs, multiple constraints per table

2
- Single: natural unique ID (user_id, product_id)
- Composite: unique combination (student_id + course_id + semester)

3
- PK defines record identity, UNIQUE ensures data uniqueness
- Table needs one main identifier but many unique attributes
*/

--5
CREATE TABLE employees_dept (
    emp_id INTEGER PRIMARY KEY,
    emp_name TEXT NOT NULL,
    dept_id INTEGER REFERENCES departments(dept_id),
    hire_date DATE
);


CREATE TABLE authors (
    author_id INTEGER PRIMARY KEY,
    author_name TEXT NOT NULL,
    country TEXT
);

CREATE TABLE publishers (
    publisher_id INTEGER PRIMARY KEY,
    publisher_name TEXT NOT NULL,
    city TEXT
);

CREATE TABLE books (
    book_id INTEGER PRIMARY KEY,
    title TEXT NOT NULL,
    author_id INTEGER REFERENCES authors(author_id),
    publisher_id INTEGER REFERENCES publishers(publisher_id),
    publication_year INTEGER,
    isbn TEXT UNIQUE
);


CREATE TABLE categories (
    category_id INTEGER PRIMARY KEY,
    category_name TEXT NOT NULL
);

CREATE TABLE products_fk (
    product_id INTEGER PRIMARY KEY,
    product_name TEXT NOT NULL,
    category_id INTEGER REFERENCES categories(category_id) ON DELETE RESTRICT
);

CREATE TABLE orders (
    order_id INTEGER PRIMARY KEY,
    order_date DATE NOT NULL
);

CREATE TABLE order_items (
    item_id INTEGER PRIMARY KEY,
    order_id INTEGER REFERENCES orders(order_id) ON DELETE CASCADE,
    product_id INTEGER REFERENCES products_fk(product_id),
    quantity INTEGER CHECK (quantity > 0)
);

--5.4
INSERT INTO categories VALUES (1, 'car');
INSERT INTO categories VALUES (2, 'phone');

INSERT INTO products_fk VALUES (1, 'bmw', 1);
INSERT INTO products_fk VALUES (2, 'mercedes', 1);
INSERT INTO products_fk VALUES (3, 'samsung', 2);

INSERT INTO orders VALUES (1, '2025-01-01');
INSERT INTO orders VALUES (2, '2025-02-02');

INSERT INTO order_items VALUES (1, 1, 1, 1);
INSERT INTO order_items VALUES (2, 1, 2, 1);
INSERT INTO order_items VALUES (3, 2, 3, 2);


DELETE FROM categories WHERE category_id = 2; /*ОШИБКА: UPDATE или DELETE в таблице "categories" нарушает ограничение внешнего ключа "products_fk_category_id_fkey" таблицы "products_fk"
[2025-10-15 21:20:03] Подробности: На ключ (category_id)=(2) всё ещё есть ссылки в таблице "products_fk".*/


DELETE FROM orders WHERE order_id = 1; --DELETE FROM orders WHERE order_id = 1

--6
DROP TABLE IF EXISTS order_details CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS customers CASCADE;


CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    phone TEXT,
    registration_date DATE NOT NULL
);

CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    price NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    stock_quantity INTEGER NOT NULL CHECK (stock_quantity >= 0)
);

CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INTEGER REFERENCES customers(customer_id) ON DELETE CASCADE,
    order_date DATE NOT NULL,
    total_amount NUMERIC(10,2) NOT NULL CHECK (total_amount >= 0),
    status TEXT NOT NULL CHECK (status IN ('pending', 'processing', 'shipped', 'delivered', 'cancelled'))
);

CREATE TABLE order_details (
    order_detail_id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES orders(order_id) ON DELETE CASCADE,
    product_id INTEGER REFERENCES products(product_id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0)
);

-- 2

INSERT INTO customers (name, email, phone, registration_date) VALUES
('Aigerim Zhaksylyk', 'aigerim@example.com', '+77014567890', '2025-01-25'),
('Rustam Beket', 'rustam@example.com', '+77024561234', '2025-02-10'),
('Miras Alimov', 'miras@example.com', '+77035678901', '2025-03-15'),
('Dinara Kazybek', 'dinara@example.com', '+77046789012', '2025-04-28'),
('Askar Nurtay', 'askar@example.com', '+77057890123', '2025-05-18');

INSERT INTO products (name, description, price, stock_quantity) VALUES
('Smartphone', '6.5-inch AMOLED display', 310000.00, 20),
('Wireless Headphones', 'Noise-cancelling over-ear', 55000.00, 30),
('Smartwatch', 'Fitness tracking and notifications', 85000.00, 25),
('Tablet 10"', 'IPS screen, 64GB storage', 180000.00, 12),
('Charging Dock', 'Wireless fast charger', 15000.00, 40);

INSERT INTO orders (customer_id, order_date, total_amount, status) VALUES
(1, '2025-06-05', 315000.00, 'pending'),
(2, '2025-06-15', 85000.00, 'processing'),
(3, '2025-07-02', 195000.00, 'shipped'),
(4, '2025-07-22', 310000.00, 'delivered'),
(5, '2025-08-03', 15000.00, 'cancelled');

INSERT INTO order_details (order_id, product_id, quantity, unit_price) VALUES
(1, 1, 1, 310000.00),
(1, 5, 1, 15000.00),
(2, 3, 1, 85000.00),
(3, 4, 1, 180000.00),
(5, 5, 1, 15000.00);

-- 3

-- Ошибка: цена отрицательная
INSERT INTO products (name, description, price, stock_quantity)
VALUES ('Broken Product', 'Negative price', -200, 10);

-- Ошибка: количество = 0
INSERT INTO order_details (order_id, product_id, quantity, unit_price)
VALUES (1, 2, 0, 55000.00);

-- Ошибка: неверный статус
INSERT INTO orders (customer_id, order_date, total_amount, status)
VALUES (1, '2025-09-01', 1000, 'returned');

-- Ошибка: повторяющийся email
INSERT INTO customers (name, email, phone, registration_date)
VALUES ('Duplicate Email', 'aigerim@example.com', '+77014567890', '2025-09-10');

-- Ошибка: несуществующий customer_id
INSERT INTO orders (customer_id, order_date, total_amount, status)
VALUES (99, '2025-09-05', 3000, 'pending');

-- Проверка ON DELETE CASCADE
DELETE FROM customers WHERE customer_id = 1;

-- Ошибка: не указан name (NOT NULL)
INSERT INTO customers (email, phone, registration_date)
VALUES ('noname@example.com', '+77001234567', '2025-09-12');
