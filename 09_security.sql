-- Phase 7: roles, privileges and access control

USE hotel_db;

CREATE ROLE IF NOT EXISTS hotel_admin;
CREATE ROLE IF NOT EXISTS hotel_manager;
CREATE ROLE IF NOT EXISTS hotel_receptionist;
CREATE ROLE IF NOT EXISTS hotel_restaurant;
CREATE ROLE IF NOT EXISTS hotel_accountant;

GRANT ALL PRIVILEGES ON hotel_db.* TO hotel_admin;

GRANT SELECT ON hotel_db.* TO hotel_manager;
GRANT EXECUTE ON hotel_db.* TO hotel_manager;
GRANT INSERT, UPDATE, DELETE ON hotel_db.Room TO hotel_manager;
GRANT INSERT, UPDATE, DELETE ON hotel_db.Room_Type TO hotel_manager;
GRANT INSERT, UPDATE, DELETE ON hotel_db.Hall TO hotel_manager;
GRANT INSERT, UPDATE, DELETE ON hotel_db.Menu_Item TO hotel_manager;

GRANT SELECT, INSERT, UPDATE ON hotel_db.Customer TO hotel_receptionist;
GRANT SELECT, INSERT, UPDATE ON hotel_db.Reservation TO hotel_receptionist;
GRANT SELECT, INSERT, DELETE ON hotel_db.Reservation_Room TO hotel_receptionist;
GRANT SELECT, INSERT, UPDATE ON hotel_db.Event TO hotel_receptionist;
GRANT SELECT, INSERT, DELETE ON hotel_db.Staff_Event TO hotel_receptionist;
GRANT SELECT ON hotel_db.Room TO hotel_receptionist;
GRANT SELECT ON hotel_db.Room_Type TO hotel_receptionist;
GRANT SELECT ON hotel_db.Hall TO hotel_receptionist;
GRANT SELECT ON hotel_db.Staff TO hotel_receptionist;
GRANT SELECT ON hotel_db.vw_room_availability TO hotel_receptionist;
GRANT SELECT ON hotel_db.vw_guest_bill TO hotel_receptionist;
GRANT EXECUTE ON PROCEDURE hotel_db.sp_create_reservation TO hotel_receptionist;
GRANT EXECUTE ON PROCEDURE hotel_db.sp_check_out TO hotel_receptionist;
GRANT EXECUTE ON FUNCTION hotel_db.fn_room_is_available TO hotel_receptionist;

GRANT SELECT, INSERT, UPDATE ON hotel_db.Dining_Order TO hotel_restaurant;
GRANT SELECT, INSERT, UPDATE, DELETE ON hotel_db.Order_Item TO hotel_restaurant;
GRANT SELECT ON hotel_db.Menu_Item TO hotel_restaurant;
GRANT SELECT ON hotel_db.Reservation TO hotel_restaurant;
GRANT SELECT ON hotel_db.Customer TO hotel_restaurant;

GRANT SELECT ON hotel_db.Invoice TO hotel_accountant;
GRANT SELECT ON hotel_db.Payment TO hotel_accountant;
GRANT SELECT ON hotel_db.Customer TO hotel_accountant;
GRANT SELECT ON hotel_db.vw_outstanding_invoices TO hotel_accountant;
GRANT SELECT ON hotel_db.vw_guest_bill TO hotel_accountant;
GRANT SELECT ON hotel_db.vw_event_bill TO hotel_accountant;
GRANT EXECUTE ON PROCEDURE hotel_db.sp_record_payment TO hotel_accountant;

/*
Five roles matching the ENUM on App_User.

Nobody gets INSERT on Payment directly. Money only moves through
sp_record_payment, so the balance checks cannot be skipped.

Receptionists get DELETE on Reservation_Room but not on Reservation, so a
room can be swapped without a booking disappearing.
*/

CREATE USER IF NOT EXISTS 'hotel_app_admin'@'localhost' IDENTIFIED BY 'ChangeMe_Admin1';
CREATE USER IF NOT EXISTS 'hotel_app_manager'@'localhost' IDENTIFIED BY 'ChangeMe_Mgr1';
CREATE USER IF NOT EXISTS 'hotel_app_reception'@'localhost' IDENTIFIED BY 'ChangeMe_Rec1';
CREATE USER IF NOT EXISTS 'hotel_app_restaurant'@'localhost' IDENTIFIED BY 'ChangeMe_Res1';
CREATE USER IF NOT EXISTS 'hotel_app_accounts'@'localhost' IDENTIFIED BY 'ChangeMe_Acc1';

GRANT hotel_admin TO 'hotel_app_admin'@'localhost';
GRANT hotel_manager TO 'hotel_app_manager'@'localhost';
GRANT hotel_receptionist TO 'hotel_app_reception'@'localhost';
GRANT hotel_restaurant TO 'hotel_app_restaurant'@'localhost';
GRANT hotel_accountant TO 'hotel_app_accounts'@'localhost';

SET DEFAULT ROLE hotel_admin FOR 'hotel_app_admin'@'localhost';
SET DEFAULT ROLE hotel_manager FOR 'hotel_app_manager'@'localhost';
SET DEFAULT ROLE hotel_receptionist FOR 'hotel_app_reception'@'localhost';
SET DEFAULT ROLE hotel_restaurant FOR 'hotel_app_restaurant'@'localhost';
SET DEFAULT ROLE hotel_accountant FOR 'hotel_app_accounts'@'localhost';

GRANT SELECT, UPDATE ON hotel_db.App_User TO 'hotel_app_reception'@'localhost';
GRANT SELECT, UPDATE ON hotel_db.App_User TO 'hotel_app_restaurant'@'localhost';
GRANT SELECT, UPDATE ON hotel_db.App_User TO 'hotel_app_accounts'@'localhost';
GRANT SELECT, UPDATE ON hotel_db.App_User TO 'hotel_app_manager'@'localhost';

FLUSH PRIVILEGES;

/*
One database account per role. The application opens its connection using
the account matching whoever logged in, so privileges follow the person.

A role by itself grants nothing until it is attached to a user, and
SET DEFAULT ROLE activates it automatically at connection time.

Every account needs SELECT on App_User to verify the login, and UPDATE to
stamp last_login. Only Admin can insert new accounts.

Passwords here are placeholders. We should Change them before the demonstration and
keep the real ones out of GitHub.
*/
/* Testing */
SHOW GRANTS FOR 'hotel_app_restaurant'@'localhost';

CREATE USER IF NOT EXISTS 'hotel_app_login'@'localhost' IDENTIFIED BY 'ChangeMe_Login1';
GRANT SELECT, UPDATE ON hotel_db.App_User TO 'hotel_app_login'@'localhost';

FLUSH PRIVILEGES;
