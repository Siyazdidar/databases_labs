CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    iin CHAR(12) UNIQUE NOT NULL,
    full_name TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    status TEXT CHECK (status IN ('active','blocked','frozen')),
    created_at TIMESTAMP ,
    daily_limit_kzt NUMERIC() 
);

CREATE TABLE accounts (
  account_id SERIAL PRIMARY KEY,
  customer_id INT REFERENCES customers(customer_id),
  account_number TEXT UNIQUE, 
  currency TEXT CHECK (currency IN ('KZT','USD','EUR','RUB')),
  balance NUMERIC,
  is_active BOOLEAN,
  opened_at TIMESTAMP,
  closed_at TIMESTAMP
);

CREATE TABLE exchange_rates (
  rate_id SERIAL PRIMARY KEY,
  from_currency TEXT,
  to_currency TEXT,
  rate NUMERIC,
  valid_from TIMESTAMP,
  valid_to TIMESTAMP
);

CREATE TABLE transactions (
  transaction_id SERIAL PRIMARY KEY,
  from_account_id INT REFERENCES accounts(account_id),
  to_account_id INT REFERENCES accounts(account_id),
  amount NUMERIC,
  currency TEXT,
  exchange_rate NUMERIC,
  amount_kzt NUMERIC,
  type TEXT CHECK (type IN ('transfer','deposit','withdrawal')),
  status TEXT CHECK (status IN ('pending','completed','failed','reversed')),
  created_at TIMESTAMP,
  completed_at TIMESTAMP,
  description TEXT
);

CREATE TABLE audit_log (
  log_id SERIAL PRIMARY KEY,
  table_name TEXT,
  record_id INT,
  action TEXT,        
  old_values JSONB,
  new_values JSONB,
  changed_by TEXT,
  changed_at TIMESTAMP,
  ip_address TEXT
);

--1
CREATE OR REPLACE FUNCTION process_transfer(
    p_from_account_number TEXT,
    p_to_account_number TEXT,
    p_amount NUMERIC,
    p_currency TEXT,
    p_description TEXT
) RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_now TIMESTAMP := now();
    v_from accounts%ROWTYPE;
    v_to accounts%ROWTYPE;
    v_cust customers%ROWTYPE;
    v_rate NUMERIC;
    v_amount_kzt NUMERIC;
    v_daily NUMERIC;
    v_tx INT;
BEGIN
    IF p_amount <= 0 THEN
        RETURN jsonb_build_object('success',false,'code','INVALID_AMOUNT');
    END IF;

    SELECT * INTO v_from FROM accounts WHERE account_number = p_from_account_number FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success',false,'code','FROM_NOT_FOUND');
    END IF;

    SELECT * INTO v_to FROM accounts WHERE account_number = p_to_account_number FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success',false,'code','TO_NOT_FOUND');
    END IF;

    SELECT * INTO v_cust FROM customers WHERE customer_id = v_from.customer_id;
    IF v_cust.status <> 'active' THEN
        RETURN jsonb_build_object('success',false,'code','CUSTOMER_BLOCKED');
    END IF;

    IF p_currency = 'KZT' THEN
        v_rate := 1;
    ELSE
        SELECT rate INTO v_rate FROM exchange_rates
        WHERE from_currency = p_currency AND to_currency = 'KZT'
        ORDER BY valid_from DESC LIMIT 1;
        IF v_rate IS NULL THEN
            RETURN jsonb_build_object('success',false,'code','NO_RATE');
        END IF;
    END IF;

    v_amount_kzt := p_amount * v_rate;

    SELECT COALESCE(SUM(amount_kzt),0)
    INTO v_daily
    FROM transactions t
    JOIN accounts a ON a.account_id = t.from_account_id
    WHERE a.customer_id = v_cust.customer_id
      AND t.created_at::date = now()::date
      AND t.status = 'completed';

    IF v_daily + v_amount_kzt > v_cust.daily_limit_kzt THEN
        RETURN jsonb_build_object('success',false,'code','DAILY_LIMIT');
    END IF;

    IF v_from.balance < p_amount THEN
        RETURN jsonb_build_object('success',false,'code','NO_FUNDS');
    END IF;

    INSERT INTO transactions(from_account_id,to_account_id,amount,currency,exchange_rate,amount_kzt,type,status,created_at,description)
    VALUES (v_from.account_id,v_to.account_id,p_amount,p_currency,v_rate,v_amount_kzt,'transfer','pending',v_now,p_description)
    RETURNING transaction_id INTO v_tx;

    SAVEPOINT sp1;

    BEGIN
        UPDATE accounts SET balance = balance - p_amount WHERE account_id = v_from.account_id;
        UPDATE accounts SET balance = balance + p_amount WHERE account_id = v_to.account_id;

        UPDATE transactions SET status='completed', completed_at=now() WHERE transaction_id = v_tx;

        INSERT INTO audit_log(table_name,record_id,action,new_values,changed_at)
        VALUES('transactions',v_tx,'INSERT',jsonb_build_object('tx',v_tx),now());

        RETURN jsonb_build_object('success',true,'transaction_id',v_tx);
    EXCEPTION WHEN others THEN
        ROLLBACK TO SAVEPOINT sp1;
        UPDATE transactions SET status='failed', completed_at=now() WHERE transaction_id = v_tx;
        RETURN jsonb_build_object('success',false,'code','BALANCE_ERROR');
    END;
END;
$$;

--2
--view 1
CREATE OR REPLACE VIEW customer_balance_summary AS
SELECT
    c.customer_id,
    c.full_name,
    a.account_id,
    a.currency,
    a.balance,
    (a.balance * COALESCE(
        (SELECT rate FROM exchange_rates er
         WHERE er.from_currency = a.currency AND er.to_currency='KZT'
         ORDER BY valid_from DESC LIMIT 1),1)) AS balance_kzt,
    SUM(a.balance * COALESCE(
        (SELECT rate FROM exchange_rates er
         WHERE er.from_currency=a.currency AND er.to_currency='KZT'
         ORDER BY valid_from DESC LIMIT 1),1))
    OVER(PARTITION BY c.customer_id) AS total_kzt,
    RANK() OVER (ORDER BY SUM(a.balance * COALESCE(
        (SELECT rate FROM exchange_rates er
         WHERE er.from_currency=a.currency AND er.to_currency='KZT'
         ORDER BY valid_from DESC LIMIT 1),1))
        OVER(PARTITION BY c.customer_id) DESC) AS rank_balance
FROM customers c
LEFT JOIN accounts a ON c.customer_id = a.customer_id;
--view 2
CREATE OR REPLACE VIEW daily_transaction_report AS
SELECT
    created_at::date AS day,
    type,
    COUNT(*) AS tx_count,
    SUM(amount_kzt) AS total_kzt,
    AVG(amount_kzt) AS avg_kzt,
    SUM(SUM(amount_kzt)) OVER(PARTITION BY type ORDER BY created_at::date) AS running,
    LAG(SUM(amount_kzt)) OVER(PARTITION BY type ORDER BY created_at::date) AS prev,
    CASE
        WHEN LAG(SUM(amount_kzt)) OVER(PARTITION BY type ORDER BY created_at::date) IS NULL THEN NULL
        ELSE ROUND(
            (SUM(amount_kzt) - LAG(SUM(amount_kzt)) OVER(PARTITION BY type ORDER BY created_at::date))
            /
            NULLIF(LAG(SUM(amount_kzt)) OVER(PARTITION BY type ORDER BY created_at::date),0) * 100,
        2)
    END AS pct
FROM transactions
GROUP BY created_at::date, type;

--view 3
CREATE OR REPLACE VIEW suspicious_activity_view
WITH (security_barrier = true) AS
SELECT
    t.transaction_id,
    t.from_account_id,
    t.amount_kzt,
    (t.amount_kzt > 5000000) AS large_tx,
    EXISTS (
        SELECT 1
        FROM transactions t2
        WHERE t2.from_account_id = t.from_account_id
        GROUP BY date_trunc('hour',t2.created_at)
        HAVING COUNT(*) > 10
    ) AS many_in_hour,
    EXISTS (
        SELECT 1 FROM transactions t3
        WHERE t3.from_account_id = t.from_account_id
        AND t3.transaction_id <> t.transaction_id
        AND ABS(EXTRACT(EPOCH FROM (t3.created_at - t.created_at))) < 60
    ) AS rapid_seq
FROM transactions t;

--3
CREATE INDEX idx_customers_iin ON customers(iin);
CREATE INDEX idx_customers_lower_email ON customers(LOWER(email));
CREATE INDEX idx_accounts_active ON accounts(account_number) WHERE is_active = true;
CREATE INDEX idx_transactions_from_created ON transactions(from_account_id, created_at);
CREATE INDEX idx_auditlog_new gin ON audit_log USING GIN(new_values);
CREATE INDEX idx_auditlog_old gin ON audit_log USING GIN(old_values);
CREATE INDEX idx_customers_phone_hash ON customers USING HASH(phone);
CREATE INDEX idx_accounts_cover ON accounts(account_number,currency) INCLUDE(balance);

--4
CREATE OR REPLACE FUNCTION process_salary_batch(
    p_company_account_number TEXT,
    p_payments JSONB
) RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_company accounts%ROWTYPE;
    v_pay RECORD;
    v_total NUMERIC := 0;
    v_success INT := 0;
    v_fail INT := 0;
    v_res JSONB := '[]';
BEGIN
    SELECT * INTO v_company FROM accounts WHERE account_number = p_company_account_number FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success',false,'code','COMPANY_NOT_FOUND');
    END IF;

    FOR v_pay IN SELECT * FROM jsonb_to_recordset(p_payments) AS (iin text, amount numeric, description text)
    LOOP
        IF v_pay.amount <= 0 THEN
            v_fail := v_fail + 1;
            CONTINUE;
        END IF;
        v_total := v_total + v_pay.amount;
    END LOOP;

    IF v_company.balance < v_total THEN
        RETURN jsonb_build_object('success',false,'code','NO_FUNDS');
    END IF;

    FOR v_pay IN SELECT * FROM jsonb_to_recordset(p_payments) AS (iin text, amount numeric, description text)
    LOOP
        SAVEPOINT sp;

        BEGIN
            UPDATE accounts SET balance = balance - v_pay.amount WHERE account_id = v_company.account_id;

            UPDATE accounts SET balance = balance + v_pay.amount
            WHERE customer_id = (SELECT customer_id FROM customers WHERE iin = v_pay.iin LIMIT 1);

            v_success := v_success + 1;

            INSERT INTO transactions(from_account_id,to_account_id,amount,currency,type,status,created_at,completed_at,description)
            SELECT v_company.account_id,
                   a.account_id,
                   v_pay.amount,
                   v_company.currency,
                   'transfer',
                   'completed',
                   now(),now(),
                   v_pay.description
            FROM accounts a
            JOIN customers c ON c.customer_id=a.customer_id
            WHERE c.iin=v_pay.iin LIMIT 1;

        EXCEPTION WHEN OTHERS THEN
            ROLLBACK TO SAVEPOINT sp;
            v_fail := v_fail + 1;
        END;
    END LOOP;

    RETURN jsonb_build_object(
        'success',true,
        'successful',v_success,
        'failed',v_fail
    );
END;
$$;