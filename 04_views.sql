-- Phase 6, Part 2: views
-- View 1 of 5

DROP VIEW IF EXISTS vw_guest_bill;

CREATE VIEW vw_guest_bill AS
SELECT
    r.reservation_id,
    r.customer_id,
    c.full_name,
    r.check_in_date,
    r.check_out_date,
    r.num_nights,
    r.status,
    rooms.nightly_rate * r.num_nights AS room_charge,
    COALESCE(dining.dining_charge, 0.00) AS dining_charge,
    (rooms.nightly_rate * r.num_nights)
        + COALESCE(dining.dining_charge, 0.00) AS total_charge
FROM Reservation r
JOIN Customer c
    ON c.customer_id = r.customer_id
JOIN (
    SELECT reservation_id, SUM(rate_applied) AS nightly_rate
    FROM Reservation_Room
    GROUP BY reservation_id
) rooms ON rooms.reservation_id = r.reservation_id
LEFT JOIN (
    SELECT d.reservation_id, SUM(oi.price_charged) AS dining_charge
    FROM Dining_Order d
    JOIN Order_Item oi ON oi.order_id = d.order_id
    GROUP BY d.reservation_id
) dining ON dining.reservation_id = r.reservation_id;

/*
Combines room charges and restaurant charges into one row per reservation.

Each side is aggregated in its own derived table before joining. Joining the
tables directly would multiply rows and inflate both totals.

The rooms join is inner because a reservation always has at least one room.
The dining join is LEFT because many guests never order food, and COALESCE
turns the resulting NULL into 0.00 so the total still calculates.

rate_applied is per night so it multiplies by num_nights. price_charged is
already the line total, so quantity is not applied again.
*/
SELECT * FROM vw_guest_bill WHERE reservation_id = 1;

-- View 2 of 5

DROP VIEW IF EXISTS vw_event_bill;

CREATE VIEW vw_event_bill AS
SELECT
    e.event_id,
    e.customer_id,
    c.full_name,
    e.event_name,
    e.event_type,
    h.hall_name,
    h.capacity,
    e.expected_guests,
    e.start_time,
    e.end_time,
    TIMESTAMPDIFF(HOUR, e.start_time, e.end_time) AS booked_hours,
    h.hourly_rate,
    h.hourly_rate * TIMESTAMPDIFF(HOUR, e.start_time, e.end_time) AS hall_charge,
    e.status
FROM Event e
JOIN Customer c
    ON c.customer_id = e.customer_id
JOIN Hall h
    ON h.hall_id = e.hall_id;

/*
Prices each event by multiplying the hall's hourly rate by the booked duration.

TIMESTAMPDIFF returns whole hours between the two timestamps, which works here
because every event in the data starts and ends on the hour.

Both joins are inner because an event cannot exist without a customer and a
hall, and the schema enforces that with NOT NULL foreign keys.

capacity and expected_guests are carried through so the same view can answer
hall utilisation questions later without a second join.
*/
SELECT event_id, hall_name, booked_hours, hall_charge
FROM vw_event_bill WHERE event_id = 8;

SELECT
    i.invoice_id,
    i.total_amount,
    COALESCE(g.total_charge, 0) + COALESCE(v.hall_charge, 0) AS calculated
FROM Invoice i
LEFT JOIN vw_guest_bill g ON g.reservation_id = i.reservation_id
LEFT JOIN vw_event_bill v ON v.event_id = i.event_id
ORDER BY i.invoice_id;

-- View 3 of 5

DROP VIEW IF EXISTS vw_room_availability;

CREATE VIEW vw_room_availability AS
SELECT
    rm.room_id,
    rm.room_number,
    rm.floor_no,
    rt.type_name,
    rt.base_rate,
    rt.max_occupancy,
    rm.status AS recorded_status,
    res.reservation_id AS current_reservation_id,
    c.full_name AS current_guest,
    res.check_out_date AS occupied_until,
    CASE
        WHEN rm.status = 'Maintenance' THEN 'Maintenance'
        WHEN res.reservation_id IS NOT NULL THEN 'Occupied'
        ELSE 'Available'
    END AS live_status
FROM Room rm
JOIN Room_Type rt
    ON rt.room_type_id = rm.room_type_id
LEFT JOIN Reservation_Room rr
    ON rr.room_id = rm.room_id
LEFT JOIN Reservation res
    ON res.reservation_id = rr.reservation_id
    AND res.status IN ('Confirmed','Checked_In')
    AND res.check_in_date <= CURDATE()
    AND res.check_out_date > CURDATE()
LEFT JOIN Customer c
    ON c.customer_id = res.customer_id;

/*
Shows every room with its category, rate and whether it is free today.

The date conditions sit in the ON clause rather than a WHERE clause. In a
WHERE clause they would discard the unmatched rows and hide free rooms.

check_out_date uses > rather than >= so a room frees up on the morning the
guest departs, matching how a hotel actually turns rooms over.

live_status is calculated from live reservations, while recorded_status is
the flag stored on the Room row. Keeping both lets the two be compared.
*/

SELECT room_id, room_number, recorded_status, live_status
FROM vw_room_availability
WHERE recorded_status <> live_status;

-- View 4 of 5

DROP VIEW IF EXISTS vw_room_type_performance;

CREATE VIEW vw_room_type_performance AS
SELECT
    rt.room_type_id,
    rt.type_name,
    rt.base_rate,
    rt.max_occupancy,
    stock.rooms_owned,
    COALESCE(bookings.times_booked, 0) AS times_booked,
    COALESCE(bookings.nights_sold, 0) AS nights_sold,
    COALESCE(bookings.room_revenue, 0.00) AS room_revenue,
    ROUND(ratings.avg_rating, 2) AS avg_rating,
    COALESCE(ratings.feedback_count, 0) AS feedback_count
FROM Room_Type rt
JOIN (
    SELECT room_type_id, COUNT(*) AS rooms_owned
    FROM Room
    GROUP BY room_type_id
) stock ON stock.room_type_id = rt.room_type_id
LEFT JOIN (
    SELECT
        rm.room_type_id,
        COUNT(*) AS times_booked,
        SUM(r.num_nights) AS nights_sold,
        SUM(rr.rate_applied * r.num_nights) AS room_revenue
    FROM Reservation_Room rr
    JOIN Room rm ON rm.room_id = rr.room_id
    JOIN Reservation r ON r.reservation_id = rr.reservation_id
    WHERE r.status <> 'Cancelled'
    GROUP BY rm.room_type_id
) bookings ON bookings.room_type_id = rt.room_type_id
LEFT JOIN (
    SELECT
        rm.room_type_id,
        AVG(f.rating) AS avg_rating,
        COUNT(*) AS feedback_count
    FROM Customer_Feedback f
    JOIN Reservation_Room rr ON rr.reservation_id = f.reservation_id
    JOIN Room rm ON rm.room_id = rr.room_id
    GROUP BY rm.room_type_id
) ratings ON ratings.room_type_id = rt.room_type_id;

/*
Reports how each room category performs on volume, revenue and satisfaction.

Bookings and ratings are aggregated separately then joined on room_type_id.
A single chain of joins would count each rating once per booked room.

Cancelled reservations are excluded from revenue since no money was earned,
but they remain in the Reservation table for the audit trail.

Both aggregates are LEFT joined so a category with no bookings or no feedback
still appears with zeros rather than vanishing from the report.

avg_rating is deliberately left NULL when no feedback exists, because zero
would read as a bad score rather than an absence of data.
*/
SELECT type_name, times_booked, room_revenue, avg_rating, feedback_count
FROM vw_room_type_performance
ORDER BY room_revenue DESC;

-- View 5 of 5

DROP VIEW IF EXISTS vw_outstanding_invoices;

CREATE VIEW vw_outstanding_invoices AS
SELECT
    i.invoice_id,
    i.customer_id,
    c.full_name,
    c.email,
    c.phone,
    i.issue_date,
    i.total_amount,
    COALESCE(paid.amount_received, 0.00) AS amount_received,
    i.total_amount - COALESCE(paid.amount_received, 0.00) AS balance_due,
    paid.payments_made,
    paid.last_payment_date,
    DATEDIFF(CURDATE(), DATE(i.issue_date)) AS days_since_issue,
    CASE
        WHEN COALESCE(paid.amount_received, 0.00) >= i.total_amount THEN 'Paid'
        WHEN COALESCE(paid.amount_received, 0.00) > 0 THEN 'Partial'
        ELSE 'Unpaid'
    END AS live_status
FROM Invoice i
JOIN Customer c
    ON c.customer_id = i.customer_id
LEFT JOIN (
    SELECT
        invoice_id,
        SUM(amount) AS amount_received,
        COUNT(*) AS payments_made,
        MAX(payment_date) AS last_payment_date
    FROM Payment
    GROUP BY invoice_id
) paid ON paid.invoice_id = i.invoice_id;

/*
Lists every invoice with what has actually been received against it.

The balance is calculated from the Payment rows rather than read from the
amount_paid column, so the view stays correct even if that column drifts.

live_status is derived the same way and can be compared against the stored
status column to detect invoices whose flag was never updated.

The LEFT join keeps invoices with no payments at all, which are precisely
the rows an accountant needs to chase.

Customer email and phone are carried through so a reminder can be sent
without a second query.
*/
SELECT invoice_id, full_name, balance_due, days_since_issue
FROM vw_outstanding_invoices
WHERE balance_due > 0
ORDER BY balance_due DESC;

SELECT invoice_id, status, live_status, amount_paid, amount_received
FROM vw_outstanding_invoices v
JOIN Invoice i USING (invoice_id)
WHERE i.status <> v.live_status;


