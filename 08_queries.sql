-- Phase 6, Part 6: Advanced queries

USE hotel_db;

-- Query 1
SELECT
    c.customer_id,
    c.full_name,
    c.nationality,
    COUNT(DISTINCT i.invoice_id) AS invoices_raised,
    SUM(i.total_amount) AS lifetime_value,
    ROUND(AVG(i.total_amount), 2) AS average_invoice
FROM Customer c
JOIN Invoice i ON i.customer_id = c.customer_id
GROUP BY c.customer_id, c.full_name, c.nationality
HAVING SUM(i.total_amount) > 2000
ORDER BY lifetime_value DESC;

/*
Aggregation filtered with HAVING. WHERE cannot be used because SUM
does not exist until after the rows are grouped.
*/


-- Query 2
SELECT
    hall_name,
    COUNT(*) AS events_hosted,
    SUM(booked_hours) AS total_hours,
    SUM(hall_charge) AS hall_revenue,
    RANK() OVER (ORDER BY SUM(hall_charge) DESC) AS revenue_rank
FROM vw_event_bill
GROUP BY hall_name
ORDER BY revenue_rank;

/*
Window function over grouped rows. RANK gives the position as a column,
which ORDER BY alone cannot do.
*/


-- Query 3
SELECT
    c.customer_id,
    c.full_name,
    COUNT(r.reservation_id) AS stays,
    SUM(r.num_nights) AS total_nights
FROM Customer c
JOIN Reservation r ON r.customer_id = c.customer_id
WHERE NOT EXISTS (
    SELECT 1
    FROM Dining_Order d
    WHERE d.reservation_id = r.reservation_id
)
GROUP BY c.customer_id, c.full_name
ORDER BY total_nights DESC;

/*
Correlated subquery. The inner query references r from the outer one,
so it runs per reservation and stops at the first match.
*/


-- Query 4
WITH monthly AS (
    SELECT
        DATE_FORMAT(issue_date, '%Y-%m') AS billing_month,
        SUM(total_amount) AS revenue,
        COUNT(*) AS invoices
    FROM Invoice
    GROUP BY DATE_FORMAT(issue_date, '%Y-%m')
)
SELECT
    billing_month,
    invoices,
    revenue,
    SUM(revenue) OVER (ORDER BY billing_month) AS running_total,
    ROUND(revenue - LAG(revenue) OVER (ORDER BY billing_month), 2) AS change_on_month
FROM monthly
ORDER BY billing_month;

/*
CTE groups by month, then window functions run over that result.
LAG reads the previous row without needing a self join.
*/


-- Query 5
SELECT
    rm.room_id,
    rm.room_number,
    rt.type_name,
    rt.base_rate,
    rm.status
FROM Room rm
JOIN Room_Type rt ON rt.room_type_id = rm.room_type_id
WHERE rm.room_id NOT IN (
    SELECT rr.room_id
    FROM Reservation_Room rr
    JOIN Reservation r ON r.reservation_id = rr.reservation_id
    WHERE r.status <> 'Cancelled'
)
ORDER BY rt.base_rate DESC;

/*
Subquery used as an exclusion list. NOT IN is safe here only because
room_id is NOT NULL; a nullable column would return no rows.
*/
