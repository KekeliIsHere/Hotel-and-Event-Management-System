CREATE DATABASE hotel_db;
use hotel_db;

CREATE TABLE Customer(
    customer_id INT PRIMARY KEY,
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(150) UNIQUE NOT NULL,
    phone VARCHAR(20) NOT NULL,
    id_number VARCHAR(50) NOT NULL,
    nationality VARCHAR(50)
);

CREATE TABLE Staff(
    staff_id INT PRIMARY KEY,
    full_name VARCHAR(50) NOT NULL,
    job_title VARCHAR(150) NOT NULL,
    department VARCHAR(50) NOT NULL,
    phone VARCHAR(20)
);

CREATE TABLE Room_Type(
    room_type_id INT PRIMARY KEY,
    type_name VARCHAR(50) NOT NULL,
    base_rate DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    max_occupancy INT NOT NULL
);

CREATE TABLE Room(
    room_id INT PRIMARY KEY,
    room_number VARCHAR(10) NOT NULL,
    floor_no VARCHAR(10) NOT NULL,
    status ENUM('Available','Occupied','Maintenance') DEFAULT 'Available',
    room_type_id INT NOT NULL,
    FOREIGN KEY (room_type_id) REFERENCES Room_Type(room_type_id) ON DELETE CASCADE
);
    
CREATE TABLE Hall(
    hall_id INT PRIMARY KEY,
    hall_name VARCHAR(100) NOT NULL,
    capacity INT NOT NULL,
    hourly_rate DECIMAL(10,2) NOT NULL DEFAULT 0.00
);

CREATE TABLE Reservation (
    reservation_id INT PRIMARY KEY,
    customer_id INT NOT NULL,
    staff_id INT NOT NULL,
    check_in_date DATE NOT NULL,
    check_out_date DATE NOT NULL,
    num_guests INT NOT NULL DEFAULT 1,
    status ENUM('Confirmed','Checked_In','Completed','Cancelled') DEFAULT 'Confirmed',
    num_nights INT AS (DATEDIFF(check_out_date, check_in_date)) STORED,
    FOREIGN KEY (customer_id) REFERENCES Customer(customer_id) ON DELETE CASCADE,
    FOREIGN KEY (staff_id) REFERENCES Staff(staff_id),
    CONSTRAINT chk_reservation_dates CHECK (check_out_date > check_in_date)
);

CREATE TABLE Reservation_Room(
    reservation_id INT,
    room_id INT,
    rate_applied DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    FOREIGN KEY (reservation_id) REFERENCES Reservation(reservation_id),
    FOREIGN KEY (room_id) REFERENCES Room(room_id),
    PRIMARY KEY (reservation_id,room_id)
);

CREATE TABLE Event (
        event_id INT AUTO_INCREMENT PRIMARY KEY,
        customer_id INT NOT NULL,
        hall_id INT NOT NULL,
        event_name VARCHAR(150) NOT NULL,
        event_type VARCHAR(50),
        start_time DATETIME NOT NULL,
        end_time DATETIME NOT NULL,
        expected_guests INT NOT NULL DEFAULT 1,
        status ENUM('Pending_Deposit', 'Confirmed', 'Completed', 'Cancelled') DEFAULT 'Pending_Deposit',
        FOREIGN KEY (customer_id) REFERENCES Customer(customer_id) ON DELETE CASCADE,
        FOREIGN KEY (hall_id) REFERENCES Hall(hall_id),
        CONSTRAINT chk_event_times CHECK (end_time > start_time)
);

CREATE TABLE Staff_Event (
   staff_id INT NOT NULL,
   event_id INT NOT NULL,
   role_on_event VARCHAR(50) NOT NULL DEFAULT 'Coordinator',
   PRIMARY KEY (staff_id, event_id),
   FOREIGN KEY (staff_id) REFERENCES Staff(staff_id) ON DELETE CASCADE,
   FOREIGN KEY (event_id) REFERENCES Event(event_id) ON DELETE CASCADE
);

CREATE TABLE Menu_Item(
    item_id INT PRIMARY KEY,
    item_name VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL DEFAULT 0.00
);

CREATE TABLE Dining_Order(
    order_id INT PRIMARY KEY,
    staff_id INT NOT NULL,
    reservation_id INT NOT NULL,
    order_time DATETIME NOT NULL,
    order_status ENUM('Open','Billed','Paid') DEFAULT 'Open',
    FOREIGN KEY (staff_id) REFERENCES Staff(staff_id),
    FOREIGN KEY (reservation_id) REFERENCES Reservation(reservation_id)
);

CREATE TABLE Order_Item (
    order_id INT NOT NULL,
    item_id INT NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    price_charged DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (order_id, item_id),
    FOREIGN KEY (order_id) REFERENCES Dining_Order(order_id) ON DELETE CASCADE,
    FOREIGN KEY (item_id) REFERENCES Menu_Item(item_id)
);

CREATE TABLE Invoice (
    invoice_id INT PRIMARY KEY,
    customer_id INT NOT NULL,
    reservation_id INT,
    event_id INT,
    issue_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    total_amount DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    amount_paid DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    status ENUM('Unpaid', 'Partial', 'Paid') DEFAULT 'Unpaid',
    FOREIGN KEY (customer_id) REFERENCES Customer(customer_id) ON DELETE CASCADE,
    FOREIGN KEY (reservation_id) REFERENCES Reservation(reservation_id),
    FOREIGN KEY (event_id) REFERENCES Event(event_id)
);

CREATE TABLE Payment (
    payment_id INT PRIMARY KEY,
    invoice_id INT NOT NULL,
    payment_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    amount DECIMAL(10,2) NOT NULL,
    method VARCHAR(50) NOT NULL,
    FOREIGN KEY (invoice_id) REFERENCES Invoice(invoice_id) ON DELETE CASCADE
);

CREATE TABLE Customer_Feedback (
    feedback_id INT PRIMARY KEY,
    customer_id INT NOT NULL,
    reservation_id INT,
    rating INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comments TEXT,
    date_submitted DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES Customer(customer_id) ON DELETE CASCADE,
    FOREIGN KEY (reservation_id) REFERENCES Reservation(reservation_id)
);