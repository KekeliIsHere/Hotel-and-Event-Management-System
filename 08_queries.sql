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

-- Query 6
SELECT
    a.reservation_id AS booking_a,
    b.reservation_id AS booking_b,
    a.room_id,
    ra.check_in_date AS a_in,
    ra.check_out_date AS a_out,
    rb.check_in_date AS b_in,
    rb.check_out_date AS b_out
FROM Reservation_Room a
JOIN Reservation_Room b
    ON b.room_id = a.room_id
    AND b.reservation_id > a.reservation_id
JOIN Reservation ra ON ra.reservation_id = a.reservation_id
JOIN Reservation rb ON rb.reservation_id = b.reservation_id
WHERE ra.status <> 'Cancelled'
  AND rb.status <> 'Cancelled'
  AND ra.check_in_date < rb.check_out_date
  AND ra.check_out_date > rb.check_in_date;

/*
Self join on the same table to detect clashing bookings. The condition
b.reservation_id > a.reservation_id stops each pair appearing twice.

Should return no rows. An empty result is the proof the data is clean.
*/


-- Query 7
SELECT
    rt.type_name,
    COUNT(f.feedback_id) AS reviews,
    SUM(CASE WHEN f.rating = 5 THEN 1 ELSE 0 END) AS excellent,
    SUM(CASE WHEN f.rating = 4 THEN 1 ELSE 0 END) AS good,
    SUM(CASE WHEN f.rating <= 3 THEN 1 ELSE 0 END) AS needs_attention,
    ROUND(AVG(f.rating), 2) AS avg_rating
FROM Room_Type rt
LEFT JOIN Room rm ON rm.room_type_id = rt.room_type_id
LEFT JOIN Reservation_Room rr ON rr.room_id = rm.room_id
LEFT JOIN Customer_Feedback f ON f.reservation_id = rr.reservation_id
GROUP BY rt.room_type_id, rt.type_name
ORDER BY avg_rating DESC;

/*
Conditional aggregation. CASE inside SUM turns rows into columns, so one
pass produces the whole rating breakdown instead of three queries.
*/


-- Query 8
SELECT 'Rooms' AS revenue_stream, SUM(rr.rate_applied * r.num_nights) AS amount
FROM Reservation_Room rr
JOIN Reservation r ON r.reservation_id = rr.reservation_id
WHERE r.status <> 'Cancelled'
UNION ALL
SELECT 'Dining', SUM(price_charged)
FROM Order_Item
UNION ALL
SELECT 'Events', SUM(hall_charge)
FROM vw_event_bill
WHERE status <> 'Cancelled'
ORDER BY amount DESC;

/*
UNION ALL stacks three unrelated totals into one result set. ALL rather
than UNION because no duplicate removal is needed and it costs less.
*/


-- Query 9
SELECT
    c.customer_id,
    c.full_name,
    SUM(i.total_amount) AS total_spent,
    (SELECT ROUND(AVG(total_amount), 2) FROM Invoice) AS average_invoice,
    ROUND(SUM(i.total_amount) - (SELECT AVG(total_amount) FROM Invoice), 2) AS above_average_by
FROM Customer c
JOIN Invoice i ON i.customer_id = c.customer_id
GROUP BY c.customer_id, c.full_name
HAVING SUM(i.total_amount) > (SELECT AVG(total_amount) FROM Invoice)
ORDER BY total_spent DESC;

/*
Scalar subquery returning a single value, used in both the select list and
the HAVING clause to compare each customer against the overall average.
*/


-- Query 10
WITH RECURSIVE calendar AS (
    SELECT DATE('2026-08-01') AS stay_date
    UNION ALL
    SELECT stay_date + INTERVAL 1 DAY
    FROM calendar
    WHERE stay_date < '2026-08-31'
)
SELECT
    cal.stay_date,
    COUNT(rr.room_id) AS rooms_occupied,
    (SELECT COUNT(*) FROM Room) AS rooms_available,
    ROUND(COUNT(rr.room_id) * 100.0 / (SELECT COUNT(*) FROM Room), 1) AS occupancy_rate
FROM calendar cal
LEFT JOIN Reservation r
    ON r.check_in_date <= cal.stay_date
    AND r.check_out_date > cal.stay_date
    AND r.status <> 'Cancelled'
LEFT JOIN Reservation_Room rr
    ON rr.reservation_id = r.reservation_id
GROUP BY cal.stay_date
ORDER BY cal.stay_date;

/*
Recursive CTE builds every date in August, since no calendar table exists.
The anchor row is the first of the month and each pass adds a day.

Without the generated dates, days with no bookings would be missing instead of showing zero.
*/
