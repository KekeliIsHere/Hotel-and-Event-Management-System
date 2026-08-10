-- Phase 6, Part 5: triggers

USE hotel_db;

DROP TRIGGER IF EXISTS trg_payment_after_insert;

DELIMITER $$

CREATE TRIGGER trg_payment_after_insert
AFTER INSERT ON Payment
FOR EACH ROW
BEGIN
    DECLARE v_received DECIMAL(10,2);
    DECLARE v_total DECIMAL(10,2);

    SELECT COALESCE(SUM(amount), 0.00) INTO v_received
    FROM Payment
    WHERE invoice_id = NEW.invoice_id;

    SELECT total_amount INTO v_total
    FROM Invoice
    WHERE invoice_id = NEW.invoice_id;

    UPDATE Invoice
    SET amount_paid = v_received,
        status = CASE
            WHEN v_received >= v_total THEN 'Paid'
            WHEN v_received > 0 THEN 'Partial'
            ELSE 'Unpaid'
        END
    WHERE invoice_id = NEW.invoice_id;
END $$

DELIMITER ;

/*
Keeps the invoice totals in step whenever a payment is recorded.

This trigger is the single owner of amount_paid and status. No procedure
writes those columns, which is why the figure cannot double count.

The received total is summed from all payments rather than added to the
existing value, so the column self corrects if it ever drifts.

Business rule implemented: an invoice is unpaid, partially paid or paid in
full depending on what has been received against it.
*/

DROP TRIGGER IF EXISTS trg_reservation_room_before_insert;

DELIMITER $$

CREATE TRIGGER trg_reservation_room_before_insert
BEFORE INSERT ON Reservation_Room
FOR EACH ROW
BEGIN
    DECLARE v_check_in DATE;
    DECLARE v_check_out DATE;

    SELECT check_in_date, check_out_date INTO v_check_in, v_check_out
    FROM Reservation
    WHERE reservation_id = NEW.reservation_id;

    IF NOT fn_room_is_available(NEW.room_id, v_check_in, v_check_out,
                                NEW.reservation_id) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Room already booked for those dates or under maintenance';
    END IF;
END $$

DELIMITER ;

/*
Blocks a room being assigned to overlapping reservations.

The procedure already checks availability, but the trigger enforces it at
the database layer so a direct INSERT cannot bypass the rule.

The dates come from the parent Reservation row, since Reservation_Room
itself holds no dates.

Business rule implemented: no reservation may overlap an existing confirmed
booking for the same room.
*/

DROP TRIGGER IF EXISTS trg_reservation_after_update;

DELIMITER $$

CREATE TRIGGER trg_reservation_after_update
AFTER UPDATE ON Reservation
FOR EACH ROW
BEGIN
    IF NEW.status <> OLD.status THEN
        IF NEW.status = 'Checked_In' THEN
            UPDATE Room
            SET status = 'Occupied'
            WHERE room_id IN (
                SELECT room_id FROM Reservation_Room
                WHERE reservation_id = NEW.reservation_id
            )
            AND status <> 'Maintenance';
        END IF;

        IF NEW.status IN ('Completed','Cancelled') THEN
            UPDATE Room
            SET status = 'Available'
            WHERE room_id IN (
                SELECT room_id FROM Reservation_Room
                WHERE reservation_id = NEW.reservation_id
            )
            AND status <> 'Maintenance';
        END IF;
    END IF;
END $$

DELIMITER ;

/*
Moves rooms between Occupied and Available as a reservation changes state.

This is what closes the stale status gap that view 3 exposed, where rooms
were flagged Occupied long after their guests had left.

Rooms under Maintenance are left alone, since a check out should not quietly
return a broken room to the available pool.

The status comparison at the top means an unrelated update, such as changing
the guest count, does not touch the rooms.

Business rule implemented: each room maintains a live status of available,
occupied or under maintenance.
*/

/* Testing the triggers */
CALL sp_record_payment(21, 400.00, 'Mobile Money', @p);
SELECT invoice_id, total_amount, amount_paid, status
FROM Invoice WHERE invoice_id = 21;

UPDATE Reservation SET status = 'Completed' WHERE reservation_id = 15;
SELECT room_id, status FROM Room WHERE room_id = 113;

INSERT INTO Reservation_Room (reservation_id, room_id, rate_applied)
VALUES (18, 118, 450.00);
