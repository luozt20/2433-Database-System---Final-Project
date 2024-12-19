-- Database System Configuration
ALTER SYSTEM SET db_block_size = 8192;  -- 8KB block size
ALTER SYSTEM SET db_cache_size = 4G;
ALTER SYSTEM SET shared_pool_size = 1G;
ALTER SYSTEM SET memory_target = 8G;
ALTER SYSTEM SET memory_max_target = 16G;

-- Redo Log Configuration
ALTER SYSTEM SET log_buffer = 32M;
ALTER DATABASE ADD LOGFILE GROUP 1 ('log1a.rdo', 'log1b.rdo') SIZE 500M;
ALTER DATABASE ADD LOGFILE GROUP 2 ('log2a.rdo', 'log2b.rdo') SIZE 500M;

-- Create Tablespaces with Storage Parameters
CREATE TABLESPACE user_data
    DATAFILE 'user_01.dbf'
    SIZE 100M
    AUTOEXTEND ON NEXT 50M MAXSIZE 1000M
    EXTENT MANAGEMENT LOCAL
    SEGMENT SPACE MANAGEMENT AUTO
    BLOCKSIZE 8K
    DEFAULT STORAGE (
        INITIAL 256K
        NEXT 256K
        MINEXTENTS 1
        MAXEXTENTS UNLIMITED
        PCTINCREASE 0
        BUFFER_POOL KEEP
    );

CREATE TABLESPACE restaurant_data
    DATAFILE 'restaurant_01.dbf'
    SIZE 200M
    AUTOEXTEND ON NEXT 50M MAXSIZE 2000M
    EXTENT MANAGEMENT LOCAL
    SEGMENT SPACE MANAGEMENT AUTO
    BLOCKSIZE 8K
    DEFAULT STORAGE (
        INITIAL 512K
        NEXT 512K
        MINEXTENTS 1
        MAXEXTENTS UNLIMITED
        PCTINCREASE 0
        BUFFER_POOL KEEP
    );

CREATE TABLESPACE order_data
    DATAFILE 'order_01.dbf'
    SIZE 500M
    AUTOEXTEND ON NEXT 100M MAXSIZE 5000M
    EXTENT MANAGEMENT LOCAL
    SEGMENT SPACE MANAGEMENT AUTO
    BLOCKSIZE 8K
    DEFAULT STORAGE (
        INITIAL 1M
        NEXT 1M
        MINEXTENTS 1
        MAXEXTENTS UNLIMITED
        PCTINCREASE 0
        BUFFER_POOL DEFAULT
    );

-- Create Temporary and UNDO Tablespaces
CREATE TEMPORARY TABLESPACE temp_data
    TEMPFILE 'temp01.dbf'
    SIZE 500M
    AUTOEXTEND ON NEXT 100M MAXSIZE 2000M
    EXTENT MANAGEMENT LOCAL;

CREATE UNDO TABLESPACE undo_data
    DATAFILE 'undo01.dbf'
    SIZE 200M
    AUTOEXTEND ON NEXT 50M MAXSIZE 1000M;

-- Table Creation with Physical Storage Specifications

-- IndividualUser Table
CREATE TABLE IndividualUser (
    UserID INTEGER PRIMARY KEY USING INDEX TABLESPACE user_data,
    Name VARCHAR(100) NOT NULL,
    Email VARCHAR(100) UNIQUE NOT NULL,
    Password VARCHAR(100) NOT NULL,
    Phone VARCHAR(15),
    UserType TEXT CHECK(UserType IN ('Customer', 'Delivery Person')) NOT NULL,
    CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
TABLESPACE user_data
STORAGE (
    INITIAL 64M
    NEXT 64M
    MINEXTENTS 1
    MAXEXTENTS UNLIMITED
    PCTINCREASE 0
    PCTFREE 10
    PCTUSED 40
    BUFFER_POOL KEEP
    COMPRESS FOR OLTP
);

-- Address Table
CREATE TABLE Address (
    AddressID INTEGER PRIMARY KEY USING INDEX TABLESPACE user_data,
    UserID INTEGER,
    Street VARCHAR(100),
    City VARCHAR(50),
    State VARCHAR(50),
    ZipCode VARCHAR(10),
    Latitude DECIMAL(10, 8),
    Longitude DECIMAL(11, 8),
    FOREIGN KEY (UserID) REFERENCES IndividualUser(UserID)
)
TABLESPACE user_data
STORAGE (
    INITIAL 32M
    NEXT 32M
    MINEXTENTS 1
    MAXEXTENTS UNLIMITED
    PCTINCREASE 0
    PCTFREE 10
    PCTUSED 40
);

-- Restaurant Table
CREATE TABLE Restaurant (
    RestaurantID INTEGER PRIMARY KEY USING INDEX TABLESPACE restaurant_data,
    Name VARCHAR(100) NOT NULL,
    Description TEXT,
    ContactNumber VARCHAR(15),
    Email VARCHAR(100) UNIQUE,
    LocationID INTEGER,
    Rating DECIMAL(2,1),
    CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (LocationID) REFERENCES Address(AddressID)
)
TABLESPACE restaurant_data
STORAGE (
    INITIAL 64M
    NEXT 64M
    MINEXTENTS 1
    MAXEXTENTS UNLIMITED
    PCTINCREASE 0
    PCTFREE 15
    PCTUSED 40
    BUFFER_POOL KEEP
)
PARTITION BY LIST (State) (
    PARTITION north_region VALUES IN ('NY', 'NJ', 'CT'),
    PARTITION south_region VALUES IN ('FL', 'GA', 'AL'),
    PARTITION west_region VALUES IN ('CA', 'OR', 'WA'),
    PARTITION other_regions VALUES IN (DEFAULT)
);

-- Menu Table
CREATE TABLE Menu (
    MenuID INTEGER PRIMARY KEY USING INDEX TABLESPACE restaurant_data,
    RestaurantID INTEGER,
    Name VARCHAR(100) NOT NULL,
    Description TEXT,
    FOREIGN KEY (RestaurantID) REFERENCES Restaurant(RestaurantID)
)
TABLESPACE restaurant_data
STORAGE (
    INITIAL 32M
    NEXT 32M
    MINEXTENTS 1
    MAXEXTENTS UNLIMITED
    PCTINCREASE 0
    PCTFREE 20
    PCTUSED 40
);

-- MenuItem Table
CREATE TABLE MenuItem (
    MenuItemID INTEGER PRIMARY KEY USING INDEX TABLESPACE restaurant_data,
    MenuID INTEGER,
    Name VARCHAR(100) NOT NULL,
    Description TEXT,
    Price DECIMAL(10,2),
    AvailabilityStatus TEXT,
    CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (MenuID) REFERENCES Menu(MenuID)
)
PARTITION BY LIST (AvailabilityStatus) (
    PARTITION available VALUES ('Available'),
    PARTITION unavailable VALUES ('Unavailable'),
    PARTITION seasonal VALUES ('Seasonal')
)
TABLESPACE restaurant_data
STORAGE (
    INITIAL 64M
    NEXT 64M
    MINEXTENTS 1
    MAXEXTENTS UNLIMITED
    PCTINCREASE 0
    PCTFREE 20
    PCTUSED 40
    BUFFER_POOL KEEP
);

-- Order Table
CREATE TABLE "Order" (
    OrderID INTEGER PRIMARY KEY USING INDEX TABLESPACE order_data,
    UserID INTEGER,
    RestaurantID INTEGER,
    OrderStatus TEXT CHECK(OrderStatus IN ('Placed', 'In-Transit', 'Delivered', 'Canceled')) NOT NULL,
    OrderDate TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    DeliveryDate TIMESTAMP,
    TotalAmount DECIMAL(10,2),
    PaymentStatus TEXT CHECK(PaymentStatus IN ('Paid', 'Pending')) NOT NULL,
    RatingID INTEGER,
    FOREIGN KEY (UserID) REFERENCES IndividualUser(UserID),
    FOREIGN KEY (RestaurantID) REFERENCES Restaurant(RestaurantID),
    FOREIGN KEY (RatingID) REFERENCES Rating(RatingID)
)
PARTITION BY RANGE (EXTRACT(YEAR FROM OrderDate)) (
    PARTITION orders_2023 VALUES LESS THAN (2024),
    PARTITION orders_2024 VALUES LESS THAN (2025),
    PARTITION orders_future VALUES LESS THAN (MAXVALUE)
)
TABLESPACE order_data
STORAGE (
    INITIAL 128M
    NEXT 128M
    MINEXTENTS 1
    MAXEXTENTS UNLIMITED
    PCTINCREASE 0
    PCTFREE 10
    PCTUSED 40
    BUFFER_POOL KEEP
    COMPRESS FOR OLTP
);

-- OrderItem Table
CREATE TABLE OrderItem (
    OrderItemID INTEGER PRIMARY KEY USING INDEX TABLESPACE order_data,
    OrderID INTEGER,
    MenuItemID INTEGER,
    Quantity INTEGER,
    ItemPrice DECIMAL(10,2),
    TotalPrice DECIMAL(10,2),
    FOREIGN KEY (OrderID) REFERENCES "Order"(OrderID),
    FOREIGN KEY (MenuItemID) REFERENCES MenuItem(MenuItemID)
)
TABLESPACE order_data
STORAGE (
    INITIAL 64M
    NEXT 64M
    MINEXTENTS 1
    MAXEXTENTS UNLIMITED
    PCTINCREASE 0
    PCTFREE 10
    PCTUSED 40
);

-- Delivery Table
CREATE TABLE Delivery (
    DeliveryID INTEGER PRIMARY KEY USING INDEX TABLESPACE order_data,
    OrderID INTEGER,
    DeliveryPersonID INTEGER,
    EstimatedDeliveryTime TIMESTAMP,
    ActualDeliveryTime TIMESTAMP,
    DeliveryStatus TEXT CHECK(DeliveryStatus IN ('Pending', 'Out for Delivery', 'Delivered')),
    FOREIGN KEY (OrderID) REFERENCES "Order"(OrderID),
    FOREIGN KEY (DeliveryPersonID) REFERENCES IndividualUser(UserID)
)
TABLESPACE order_data
STORAGE (
    INITIAL 64M
    NEXT 64M
    MINEXTENTS 1
    MAXEXTENTS UNLIMITED
    PCTINCREASE 0
    PCTFREE 15
    PCTUSED 40
);

-- Payment Table
CREATE TABLE Payment (
    PaymentID INTEGER PRIMARY KEY USING INDEX TABLESPACE order_data,
    OrderID INTEGER,
    OriginalAmount DECIMAL(10,2),
    PromotionID INTEGER,
    FinalAmount DECIMAL(10,2),
    PaymentDate TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PaymentMethod TEXT CHECK(PaymentMethod IN ('Credit Card', 'PayPal')),
    PaymentStatus TEXT CHECK(PaymentStatus IN ('Paid', 'Pending')) NOT NULL,
    FOREIGN KEY (OrderID) REFERENCES "Order"(OrderID),
    FOREIGN KEY (PromotionID) REFERENCES Promotion(PromotionID)
)
TABLESPACE order_data
STORAGE (
    INITIAL 64M
    NEXT 64M
    MINEXTENTS 1
    MAXEXTENTS UNLIMITED
    PCTINCREASE 0
    PCTFREE 10
    PCTUSED 40
);

-- Rating Table
CREATE TABLE Rating (
    RatingID INTEGER PRIMARY KEY USING INDEX TABLESPACE restaurant_data,
    UserID INTEGER,
    RestaurantID INTEGER,
    OrderID INTEGER,
    RatingScore INTEGER CHECK(RatingScore BETWEEN 1 AND 5),
    Comment TEXT,
    CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (UserID) REFERENCES IndividualUser(UserID),
    FOREIGN KEY (RestaurantID) REFERENCES Restaurant(RestaurantID),
    FOREIGN KEY (OrderID) REFERENCES "Order"(OrderID)
)
TABLESPACE restaurant_data
STORAGE (
    INITIAL 32M
    NEXT 32M
    MINEXTENTS 1
    MAXEXTENTS UNLIMITED
    PCTINCREASE 0
    PCTFREE 20
    PCTUSED 40
);

-- Promotion Table
CREATE TABLE Promotion (
    PromotionID INTEGER PRIMARY KEY USING INDEX TABLESPACE restaurant_data,
    RestaurantID INTEGER,
    Title VARCHAR(100),
    Description TEXT,
    DiscountPercentage DECIMAL(5,2),
    StartDate TIMESTAMP,
    EndDate TIMESTAMP,
    FOREIGN KEY (RestaurantID) REFERENCES Restaurant(RestaurantID)
)
TABLESPACE restaurant_data
STORAGE (
    INITIAL 32M
    NEXT 32M
    MINEXTENTS 1
    MAXEXTENTS UNLIMITED
    PCTINCREASE 0
    PCTFREE 15
    PCTUSED 40
);

-- Create Indexes
CREATE INDEX idx_user_email ON IndividualUser(Email) TABLESPACE user_data;
CREATE INDEX idx_user_usertype ON IndividualUser(UserType) TABLESPACE user_data;
CREATE INDEX idx_address_state_city ON Address(State, City) TABLESPACE user_data;
CREATE INDEX idx_restaurant_rating ON Restaurant(Rating) TABLESPACE restaurant_data;
CREATE INDEX idx_restaurant_createdat ON Restaurant(CreatedAt) TABLESPACE restaurant_data;
CREATE INDEX idx_menuitem_availability ON MenuItem(AvailabilityStatus) TABLESPACE restaurant_data;
CREATE INDEX idx_order_status ON "Order"(OrderStatus) TABLESPACE order_data;
CREATE INDEX idx_order_payment_status ON "Order"(PaymentStatus) TABLESPACE order_data;
CREATE INDEX idx_payment_method ON Payment(PaymentMethod) TABLESPACE order_data;
CREATE INDEX idx_payment_status ON Payment(PaymentStatus) TABLESPACE order_data;
CREATE INDEX idx_rating_score ON Rating(RatingScore) TABLESPACE restaurant_data;

-- Create Materialized View
CREATE MATERIALIZED VIEW FrequentlyOrderedItems
TABLESPACE restaurant_data
BUILD IMMEDIATE
REFRESH ON COMMIT AS
SELECT MenuItemID, COUNT(MenuItemID) AS OrderCount
FROM OrderItem
GROUP BY MenuItemID
ORDER BY OrderCount DESC;

-- Statistics Management
ANALYZE TABLE IndividualUser COMPUTE STATISTICS;
ANALYZE TABLE Restaurant COMPUTE STATISTICS;
ANALYZE TABLE "Order" COMPUTE STATISTICS;
ANALYZE TABLE MenuItem COMPUTE STATISTICS;

-- Backup Configuration
ALTER SYSTEM SET db_recovery_file_dest_size = 10G;
ALTER SYSTEM SET db_recovery_file_dest = '/backup';
ALTER DATABASE ARCHIVELOG;

-- Maintenance Window Creation
BEGIN
    DBMS_SCHEDULER.CREATE_WINDOW (
        window_name => 'MAINTENANCE_WINDOW',
        resource_plan => 'DEFAULT_MAINTENANCE_PLAN',
        start_date => SYSTIMESTAMP,
        repeat_interval => 'freq=daily;byhour=1;byminute=0;bysecond=0',
        duration => numtodsinterval(2, 'hour'),
        window_priority => 'LOW',
        comments => 'Daily maintenance window'
    );
END;
/