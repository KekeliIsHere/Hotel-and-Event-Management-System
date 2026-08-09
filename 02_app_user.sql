-- Phase 7: authentication and role based access control
-- Creates the login table used by the Python application

USE hotel_db;

CREATE TABLE App_User(
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role ENUM('Admin','Manager','Receptionist','Restaurant','Accountant') NOT NULL,
    staff_id INT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login DATETIME,
    -- a login belongs to a staff member, but admin accounts may have none
    FOREIGN KEY (staff_id) REFERENCES Staff(staff_id) ON DELETE SET NULL,
    CONSTRAINT chk_username_length CHECK (CHAR_LENGTH(username) >= 4)
);

-- one account per staff member, but only where a staff member is linked
CREATE UNIQUE INDEX idx_app_user_staff ON App_User(staff_id);

-- speeds up the login lookup, which runs on every sign in
CREATE INDEX idx_app_user_active ON App_User(username, is_active);
