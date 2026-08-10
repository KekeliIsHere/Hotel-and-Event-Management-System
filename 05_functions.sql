-- Phase 6, Part 3: user defined functions

USE hotel_db;

DROP FUNCTION IF EXISTS fn_reservation_total;

DELIMITER $$

CREATE FUNCTION fn_reservation_total(p_reservation_id INT)
RETURNS DECIMAL(10,2)
READS SQL DATA
BEGIN
    DECLARE v_nights INT DEFAULT 0;
    DECLARE v_rooms DECIMAL(10,2) DEFAULT 0.00;
    DECLARE v_dining DECIMAL(10,2) DEFAULT 0.00;

    SELECT num_nights INTO v_nights
    FROM Reservation
    WHERE reservation_id = p_reservation_id;

    IF v_nights IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT COALESCE(SUM(rate_applied), 0.00) INTO v_rooms
    FROM Reservation_Room
    WHERE reservation_id = p_reservation_id;

    SELECT COALESCE(SUM(oi.price_charged), 0.00) INTO v_dining
    FROM Dining_Order d
    JOIN Order_Item oi ON oi.order_id = d.order_id
    WHERE d.reservation_id = p_reservation_id;

    RETURN (v_rooms * v_nights) + v_dining;
END $$

DELIMITER ;

/*
Returns the combined room and dining charge for one reservation.

Each total is fetched into its own variable instead of being joined together,
which avoids the row multiplication problem that view 1 solves differently.

A missing reservation returns NULL instead of 0.00, so the caller can tell
an unknown booking apart from a genuinely free stay.

COALESCE guards the dining total because most reservations have no orders,
and SUM over no rows returns NULL rather than zero.
*/

DROP FUNCTION IF EXISTS fn_room_is_available;

DELIMITER $$

CREATE FUNCTION fn_room_is_available(
    p_room_id INT,
    p_check_in DATE,
    p_check_out DATE,
    p_exclude_reservation INT
)
RETURNS BOOLEAN
READS SQL DATA
BEGIN
    DECLARE v_clashes INT DEFAULT 0;
    DECLARE v_status VARCHAR(20);

    SELECT status INTO v_status
    FROM Room
    WHERE room_id = p_room_id;

    IF v_status IS NULL OR v_status = 'Maintenance' THEN
        RETURN FALSE;
    END IF;

    SELECT COUNT(*) INTO v_clashes
    FROM Reservation_Room rr
    JOIN Reservation r ON r.reservation_id = rr.reservation_id
    WHERE rr.room_id = p_room_id
      AND r.status <> 'Cancelled'
      AND r.reservation_id <> COALESCE(p_exclude_reservation, 0)
      AND r.check_in_date < p_check_out
      AND r.check_out_date > p_check_in;

    RETURN v_clashes = 0;
END $$

DELIMITER ;

/*
Reports whether a room can be booked for a given date range.

Two ranges overlap when each one starts before the other ends. Using strict
less than lets a new guest arrive on the day the previous one departs.

Cancelled reservations are ignored because the room was released.

p_exclude_reservation lets an existing booking be edited without clashing
with itself, and COALESCE handles being passed NULL for a new booking.
*/

SELECT fn_reservation_total(1);
SELECT fn_room_is_available(118, '2026-08-20', '2026-08-23', NULL);
SELECT fn_room_is_available(101, '2026-08-20', '2026-08-23', NULL);
SELECT fn_room_is_available(104, '2026-08-20', '2026-08-23', NULL);
