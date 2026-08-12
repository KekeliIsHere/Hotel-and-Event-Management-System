-- Tests for Phase 6 and Phase 7.

USE hotel_db;

-- Test 1
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = 'hotel_db'
ORDER BY routine_type, routine_name;
-- Expected 5 rows: 2 functions and 3 procedures

-- Test 2
SELECT table_name
FROM information_schema.views
WHERE table_schema = 'hotel_db'
ORDER BY table_name;
-- Expected 5 views

-- Test 3
SELECT trigger_name, event_manipulation, action_timing, event_object_table
FROM information_schema.triggers
WHERE trigger_schema = 'hotel_db';
-- Expected 3 rows: one BEFORE INSERT and two AFTER

-- Test 4
SELECT COUNT(*) AS reservations FROM Reservation;
SELECT COUNT(*) AS payments FROM Payment;
-- Expected 25 and 16

-- Test 5
SELECT * FROM vw_guest_bill WHERE reservation_id = 1;
-- Expected room 360.00, dining 31.00, total 391.00

-- Test 6
SELECT reservation_id, full_name, dining_charge
FROM vw_guest_bill
WHERE dining_charge = 0
ORDER BY reservation_id;
-- Expected several rows, proving the LEFT JOIN keeps guests with no orders

-- Test 7
SELECT event_id, hall_name, booked_hours, hall_charge
FROM vw_event_bill WHERE event_id = 8;
-- Expected 3 hours at 60.00 giving 180.00

-- Test 8
SELECT
    i.invoice_id,
    i.total_amount,
    COALESCE(g.total_charge, 0) + COALESCE(v.hall_charge, 0) AS calculated
FROM Invoice i
LEFT JOIN vw_guest_bill g ON g.reservation_id = i.reservation_id
LEFT JOIN vw_event_bill v ON v.event_id = i.event_id
ORDER BY i.invoice_id;
-- Expected the two columns to match on every row

-- Test 9
SELECT room_id, room_number, recorded_status, live_status
FROM vw_room_availability
WHERE recorded_status <> live_status;
-- Expected about 7 rows before the triggers run, fewer after Test 18

-- Test 10
SELECT type_name, times_booked, room_revenue, avg_rating, feedback_count
FROM vw_room_type_performance
ORDER BY room_revenue DESC;
-- Expected Family Room at 0 bookings with a NULL rating

-- Test 11
SELECT invoice_id, full_name, balance_due, days_since_issue
FROM vw_outstanding_invoices
WHERE balance_due > 0
ORDER BY balance_due DESC;
-- Expected 9 invoices still owing

-- Test 12
SELECT v.invoice_id, i.status, v.live_status, i.amount_paid, v.amount_received
FROM vw_outstanding_invoices v
JOIN Invoice i USING (invoice_id)
WHERE i.status <> v.live_status;
-- Expected no rows

-- Test 13
SELECT fn_reservation_total(1) AS total_for_reservation_1;
-- Expected 391.00, matching Test 5

-- Test 14
SELECT fn_reservation_total(999) AS unknown_reservation;
-- Expected NULL, not 0.00

-- Test 15
SELECT fn_room_is_available(116, '2026-08-05', '2026-08-07', NULL) AS taken_room;
SELECT fn_room_is_available(101, '2026-08-20', '2026-08-23', NULL) AS free_room;
SELECT fn_room_is_available(104, '2026-08-20', '2026-08-23', NULL) AS maintenance_room;
-- Expected 0, 1, 0

-- Test 16
SELECT fn_room_is_available(116, '2026-08-08', '2026-08-10', NULL) AS same_day_turnover;
-- Expected 1, since reservation 16 leaves on 8 August

-- Test 17
CALL sp_record_payment(21, 400.00, 'Mobile Money', @payment_id);
SELECT invoice_id, total_amount, amount_paid, status
FROM Invoice WHERE invoice_id = 21;
-- Expected 400.00 paid and status Partial, written by the trigger

-- Test 18
UPDATE Reservation SET status = 'Completed' WHERE reservation_id = 15;
SELECT room_id, status FROM Room WHERE room_id = 113;
-- Expected room 113 to become Available

-- Test 19
INSERT INTO Reservation_Room (reservation_id, room_id, rate_applied)
VALUES (17, 116, 180.00);
-- Expected to FAIL, since reservations 16 and 17 clash on room 116

-- Test 20
CALL sp_create_reservation(5, 2, 101, '2026-09-20', '2026-09-23', 1, @new_res);
SELECT @new_res AS new_reservation_id;
SELECT * FROM Reservation_Room WHERE reservation_id = @new_res;
-- Expected reservation 26 with one room row at 120.00

-- Test 21
CALL sp_create_reservation(5, 2, 101, '2026-09-21', '2026-09-24', 1, @clash_res);
-- Expected to FAIL, overlapping the booking from Test 20

-- Test 22
CALL sp_create_reservation(5, 2, 101, '2026-10-01', '2026-10-03', 4, @too_many);
-- Expected to FAIL, room 101 holds one guest

-- Test 23
CALL sp_record_payment(23, 5000.00, 'Cash', @over_pay);
-- Expected to FAIL, invoice 23 is only 390.00

-- Test 24
UPDATE Reservation SET status = 'Checked_In' WHERE reservation_id = 18;
CALL sp_check_out(18, @invoice_no);
SELECT @invoice_no AS invoice_raised;
SELECT reservation_id, status FROM Reservation WHERE reservation_id = 18;
SELECT room_id, status FROM Room WHERE room_id = 106;
-- Expected a new invoice, status Completed, room 106 Available

-- Test 25
CALL sp_check_out(18, @second_try);
-- Expected to FAIL, only a Checked_In stay can be checked out

-- Test 26
SELECT
    a.reservation_id AS booking_a,
    b.reservation_id AS booking_b,
    a.room_id
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
-- Expected no rows, proving no clash exists anywhere in the data

-- Test 27
SHOW GRANTS FOR 'hotel_app_restaurant'@'localhost';
SHOW GRANTS FOR 'hotel_app_login'@'localhost';
-- Expected narrow rights on each account

-- Test 28
-- To be run in a separate session opened as hotel_app_restaurant
-- SELECT * FROM Dining_Order;
-- SELECT * FROM Invoice;
-- DELETE FROM Invoice WHERE invoice_id = 25;
-- CALL sp_record_payment(23, 100.00, 'Cash', @p);
-- Expected the first to succeed and the rest refused with error 1142

-- Test 29
SELECT user_id, username, role, staff_id, is_active,
       LEFT(password_hash, 7) AS hash_prefix
FROM App_User;
-- Expected 5 accounts with every hash starting $2b$ or $2a$
