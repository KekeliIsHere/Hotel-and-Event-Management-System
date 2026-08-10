-- Phase 6, Part 4: stored procedures

USE hotel_db;

DROP PROCEDURE IF EXISTS sp_create_reservation;

DELIMITER $$

CREATE PROCEDURE sp_create_reservation(
    IN p_customer_id INT,
    IN p_staff_id INT,
    IN p_room_id INT,
    IN p_check_in DATE,
    IN p_check_out DATE,
    IN p_num_guests INT,
    OUT p_reservation_id INT
)
BEGIN
    DECLARE v_rate DECIMAL(10,2);
    DECLARE v_max_occupancy INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF NOT fn_room_is_available(p_room_id, p_check_in, p_check_out, NULL) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Room is not available for those dates';
    END IF;

    SELECT rt.base_rate, rt.max_occupancy INTO v_rate, v_max_occupancy
    FROM Room rm
    JOIN Room_Type rt ON rt.room_type_id = rm.room_type_id
    WHERE rm.room_id = p_room_id;

    IF p_num_guests > v_max_occupancy THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Guest count exceeds the room capacity';
    END IF;

    SELECT COALESCE(MAX(reservation_id), 0) + 1 INTO p_reservation_id
    FROM Reservation;

    INSERT INTO Reservation
        (reservation_id, customer_id, staff_id, check_in_date,
         check_out_date, num_guests, status)
    VALUES
        (p_reservation_id, p_customer_id, p_staff_id, p_check_in,
         p_check_out, p_num_guests, 'Confirmed');

    INSERT INTO Reservation_Room (reservation_id, room_id, rate_applied)
    VALUES (p_reservation_id, p_room_id, v_rate);

    COMMIT;
END $$

DELIMITER ;

/*
Books a room after checking availability and capacity in one transaction.

Two rows are written across two tables, so a failure between them would
leave a reservation with no room. The transaction prevents that.

The EXIT HANDLER rolls back on any error and re-raises it, so the caller
sees the real message rather than a silent partial write.

SIGNAL with SQLSTATE 45000 is the standard way to raise a custom error.
Python receives it as an ordinary database exception.

The rate is copied from the room type at booking time rather than read
later, so a future price change cannot rewrite an existing booking.
*/
DROP PROCEDURE IF EXISTS sp_check_out;

DELIMITER $$

CREATE PROCEDURE sp_check_out(
    IN p_reservation_id INT,
    OUT p_invoice_id INT
)
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_customer_id INT;
    DECLARE v_total DECIMAL(10,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT status, customer_id INTO v_status, v_customer_id
    FROM Reservation
    WHERE reservation_id = p_reservation_id;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Reservation not found';
    END IF;

    IF v_status <> 'Checked_In' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Only a checked in reservation can be checked out';
    END IF;

    SET v_total = fn_reservation_total(p_reservation_id);

    SELECT COALESCE(MAX(invoice_id), 0) + 1 INTO p_invoice_id
    FROM Invoice;

    INSERT INTO Invoice
        (invoice_id, customer_id, reservation_id, event_id,
         issue_date, total_amount, amount_paid, status)
    VALUES
        (p_invoice_id, v_customer_id, p_reservation_id, NULL,
         NOW(), v_total, 0.00, 'Unpaid');

    UPDATE Reservation
    SET status = 'Completed'
    WHERE reservation_id = p_reservation_id;

    UPDATE Room
    SET status = 'Available'
    WHERE room_id IN (
        SELECT room_id FROM Reservation_Room
        WHERE reservation_id = p_reservation_id
    );

    UPDATE Dining_Order
    SET order_status = 'Billed'
    WHERE reservation_id = p_reservation_id
      AND order_status = 'Open';

    COMMIT;
END $$

DELIMITER ;

/*
Closes a stay: raises the invoice, frees the rooms and bills open orders.

Four tables change together, so all of it runs inside one transaction.
A half completed checkout would free a room while still showing it occupied.

The status check refuses to check out a booking that was never checked in,
which stops the same reservation being closed twice.

The total comes from fn_reservation_total instead of being recalculated
here, so the billing logic exists in exactly one place.

This procedure is what closes the stale Room.status gap that view 3 exposed.
*/

DROP PROCEDURE IF EXISTS sp_record_payment;

DELIMITER $$

CREATE PROCEDURE sp_record_payment(
    IN p_invoice_id INT,
    IN p_amount DECIMAL(10,2),
    IN p_method VARCHAR(50),
    OUT p_payment_id INT
)
BEGIN
    DECLARE v_total DECIMAL(10,2);
    DECLARE v_received DECIMAL(10,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT total_amount INTO v_total
    FROM Invoice
    WHERE invoice_id = p_invoice_id;

    IF v_total IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invoice not found';
    END IF;

    IF p_amount <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Payment amount must be greater than zero';
    END IF;

    SELECT COALESCE(SUM(amount), 0.00) INTO v_received
    FROM Payment
    WHERE invoice_id = p_invoice_id;

    IF v_received + p_amount > v_total THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Payment exceeds the outstanding balance';
    END IF;

    SELECT COALESCE(MAX(payment_id), 0) + 1 INTO p_payment_id
    FROM Payment;

    INSERT INTO Payment (payment_id, invoice_id, payment_date, amount, method)
    VALUES (p_payment_id, p_invoice_id, NOW(), p_amount, p_method);

    COMMIT;
END $$

DELIMITER ;

/*
Records a payment after validating it against the outstanding balance.

The balance is read from the Payment rows rather than the amount_paid
column, so an overpayment is caught even if that column has drifted.

Partial payments are allowed, which is why the check compares the running
total against the invoice instead of  requiring the full amount.

This procedure deliberately does not touch amount_paid or status. Trigger
one owns those columns, and having both write them would double the figure.
*/
