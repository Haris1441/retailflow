WITH lines(line_id, order_id, qty, unit_price) AS (
    VALUES (1, 100, 2, 2000), (2, 100, 1, 1500)
),
payments(order_id, status, amount) AS (
    VALUES (100, 'FAILED', 5500), (100, 'SUCCESS', 5500)
),
returns(order_id, line_id, returned_qty, credit) AS (
    VALUES (100, 1, 1, 2000)
),
sales_by_order AS (
    SELECT order_id, SUM(qty * unit_price) AS recognized
    FROM lines
    GROUP BY order_id
),
cash_by_order AS (
    SELECT order_id, SUM(amount) AS collected
    FROM payments
    WHERE status = 'SUCCESS'
    GROUP BY order_id
),
returns_by_order AS (
    SELECT order_id, SUM(credit) AS merchandise_credit
    FROM returns
    GROUP BY order_id
)
SELECT sales.order_id, recognized, collected, merchandise_credit,
       recognized - merchandise_credit AS net_revenue
FROM sales_by_order AS sales
LEFT JOIN cash_by_order AS cash USING (order_id)
LEFT JOIN returns_by_order AS credits USING (order_id);
