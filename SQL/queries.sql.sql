-- STEP 1: DATA CLEANING
-- 1. Profile missing values
   SELECT
    SUM(CASE WHEN children IS NULL THEN 1 ELSE 0 END) AS children_null,
    SUM(CASE WHEN agent IS NULL THEN 1 ELSE 0 END) AS agent_null,
    SUM(CASE WHEN company = 'NULL' THEN 1 ELSE 0 END) AS company_null_text,
    SUM(CASE WHEN country IS NULL THEN 1 ELSE 0 END) AS country_null
FROM raw_bookings;
-- Result: children_null = 4, agent_null = 16340, company_null_text = 112593 (~94.3%), country_null = 0

-- 2. Profile adr (Average Daily Rate)
SELECT MIN(adr) AS min_adr, MAX(adr) AS max_adr, AVG(adr) AS avg_adr,
       SUM(CASE WHEN adr = 0 THEN 1 ELSE 0 END) AS adr_zero_count
FROM raw_bookings;
-- Result: min=0, max=5400, avg~101.83, adr=0 has 1959 rows (kept, this is legitimate, not an error)
-- adr=5400 is a single outlier -> handled with a WHERE filter when computing revenue, not removed from the table

-- 3. Detect "junk" bookings: no guests at all (adults=0 & children=0 & babies=0)
SELECT COUNT(*) AS junk_bookings
FROM raw_bookings
WHERE adults = 0 AND children = 0 AND babies = 0;
-- Result: 180 rows -> excluded from clean_bookings

-- 4. Create clean_bookings (physical table, junk bookings removed)
SELECT *
INTO clean_bookings
FROM raw_bookings
WHERE NOT (adults = 0 AND children = 0 AND babies = 0);

-- 5. Handle missing values on clean_bookings
UPDATE clean_bookings SET children = 0 WHERE children IS NULL;
UPDATE clean_bookings SET agent = 0 WHERE agent IS NULL;
UPDATE clean_bookings SET company = '0' WHERE company = 'NULL';

-- 6.Verify
SELECT COUNT(*) AS total_rows_clean FROM clean_bookings; -- Expected: 119210 (119390 - 180)

-- STEP 2: ANALYSIS QUERIES
-- GROUP 1: Basic GROUP BY
-- Query 1 — Cancellation rate by hotel type
SELECT 
    hotel,
    COUNT(*) AS total_bookings,
    SUM(CAST(is_canceled AS INT)) AS canceled_bookings,
    CAST(SUM(CAST(is_canceled AS INT)) AS FLOAT) / COUNT(*) * 100 AS cancellation_rate_pct
FROM clean_bookings
GROUP BY hotel;
-- Result: City Hotel 41.79%, Resort Hotel 27.77%

-- Query 2 — Cancellation rate by year / month
SELECT 
    arrival_date_year,
    arrival_date_month,
    COUNT(*) AS total_bookings,
    SUM(CAST(is_canceled AS INT)) AS canceled_bookings,
    CAST(SUM(CAST(is_canceled AS INT)) AS FLOAT) / COUNT(*) * 100 AS cancellation_rate_pct
FROM clean_bookings
GROUP BY arrival_date_year, arrival_date_month
ORDER BY arrival_date_year, 
    CASE arrival_date_month
        WHEN 'January' THEN 1 WHEN 'February' THEN 2 WHEN 'March' THEN 3
        WHEN 'April' THEN 4 WHEN 'May' THEN 5 WHEN 'June' THEN 6
        WHEN 'July' THEN 7 WHEN 'August' THEN 8 WHEN 'September' THEN 9
        WHEN 'October' THEN 10 WHEN 'November' THEN 11 WHEN 'December' THEN 12
    END;


--Query 3 — Cancellation rate by distribution_channel
SELECT 
    distribution_channel,
    COUNT(*) AS total_bookings,
    SUM(CAST(is_canceled AS INT)) AS canceled_bookings,
    CAST(SUM(CAST(is_canceled AS INT)) AS FLOAT) / COUNT(*) * 100 AS cancellation_rate_pct
FROM clean_bookings
GROUP BY distribution_channel
ORDER BY cancellation_rate_pct DESC;

-- GROUP 2: Cancelled vs not-cancelled comparison + Subquery
-- Query 4 — Compare booking behavior between cancelled and not-cancelled guests
SELECT 
    is_canceled,
    COUNT(*) AS total_bookings,
    AVG(CAST(lead_time AS FLOAT)) AS avg_lead_time,
    AVG(CAST(total_of_special_requests AS FLOAT)) AS avg_special_requests,
    AVG(CAST(booking_changes AS FLOAT)) AS avg_booking_changes
FROM clean_bookings
GROUP BY is_canceled;


-- Query 5 — Cancellation rate for above-average vs below-average lead_time (Subquery)
WITH lead_time_classified AS (
    SELECT 
        is_canceled,
        CASE 
            WHEN lead_time > (SELECT AVG(CAST(lead_time AS FLOAT)) FROM clean_bookings) 
            THEN 'Above Average Lead Time'
            ELSE 'Below Average Lead Time'
        END AS lead_time_group
    FROM clean_bookings
)
SELECT 
    lead_time_group,
    COUNT(*) AS total_bookings,
    SUM(CAST(is_canceled AS INT)) AS canceled_bookings,
    CAST(SUM(CAST(is_canceled AS INT)) AS FLOAT) / COUNT(*) * 100 AS cancellation_rate_pct
FROM lead_time_classified
GROUP BY lead_time_group;

-- GROUP 3: Window Functions
-- Query 6: Top countries by number of bookings
WITH country_counts AS (
    SELECT DISTINCT
        country,
        COUNT(*) OVER (PARTITION BY country) AS total_bookings
    FROM clean_bookings
)
SELECT 
    country,
    total_bookings,
    RANK() OVER (ORDER BY total_bookings DESC) AS booking_rank
FROM country_counts
ORDER BY booking_rank;

-- Query 7 — Compare each booking's ADR to its month's average ADR (AVG() OVER, Window Function)
SELECT 
    arrival_date_year,
    arrival_date_month,
    adr,
    AVG(adr) OVER (PARTITION BY arrival_date_year, arrival_date_month) AS avg_adr_that_month,
    adr - AVG(adr) OVER (PARTITION BY arrival_date_year, arrival_date_month) AS diff_from_month_avg
FROM clean_bookings
WHERE adr BETWEEN 1 AND 1000
ORDER BY arrival_date_year, arrival_date_month;

-- Query 8 — Top market_segment by booking count within each country (ROW_NUMBER, CTE)
WITH ranked_segments AS (
    SELECT
        country,
        market_segment,
        COUNT(*) AS total_bookings,
        ROW_NUMBER() OVER (PARTITION BY country ORDER BY COUNT(*) DESC) AS rn
    FROM clean_bookings
    GROUP BY country, market_segment
)
SELECT country, market_segment, total_bookings
FROM ranked_segments
WHERE rn = 1
ORDER BY total_bookings DESC;

-- GROUP 4: Revenue
-- Query 9 — Doanh thu theo market_segment 
SELECT 
    market_segment,
    COUNT(*) AS total_bookings,
    SUM(adr * (stays_in_weekend_nights + stays_in_week_nights)) AS total_revenue,
    AVG(adr) AS avg_adr
FROM clean_bookings
WHERE is_canceled = 0
    AND adr BETWEEN 1 AND 1000
GROUP BY market_segment
ORDER BY total_revenue DESC;

-- Query 10 — Revenue by country
WITH revenue_by_country AS (
    SELECT 
        country,
        SUM(adr * (stays_in_weekend_nights + stays_in_week_nights)) AS total_revenue,
        COUNT(*) AS total_bookings
    FROM clean_bookings
    WHERE is_canceled = 0
        AND adr BETWEEN 1 AND 1000
    GROUP BY country
)
SELECT 
    country,
    total_revenue,
    total_bookings,
    RANK() OVER (ORDER BY total_revenue DESC) AS revenue_rank
FROM revenue_by_country
ORDER BY revenue_rank
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;

-- STEP 3B: VIEWS FOR POWER BI
-- View 1: Main fact table with pre-computed columns
GO 
CREATE OR ALTER VIEW vw_bookings_detail AS
SELECT 
    hotel,
    is_canceled,
    lead_time,
    arrival_date_year,
    arrival_date_month,
    arrival_date_week_number,
    arrival_date_day_of_month,
    stays_in_weekend_nights,
    stays_in_week_nights,
    adults,
    children,
    babies,
    meal,
    country,
    market_segment,
    distribution_channel,
    is_repeated_guest,
    previous_cancellations,
    reserved_room_type,
    assigned_room_type,
    booking_changes,
    deposit_type,
    customer_type,
    adr,
    total_of_special_requests,
    reservation_status,
    reservation_status_date,
    (stays_in_weekend_nights + stays_in_week_nights) AS total_nights,
    CASE WHEN is_canceled = 0 AND adr BETWEEN 1 AND 1000 
         THEN adr * (stays_in_weekend_nights + stays_in_week_nights) 
         ELSE 0 
    END AS revenue
FROM clean_bookings;


-- VIEW 2 — vw_revenue_by_segment (based on Query 9)
GO
CREATE OR ALTER VIEW vw_revenue_by_segment AS
SELECT 
    market_segment,
    COUNT(*) AS total_bookings,
    SUM(adr * (stays_in_weekend_nights + stays_in_week_nights)) AS total_revenue,
    AVG(adr) AS avg_adr
FROM clean_bookings
WHERE is_canceled = 0
    AND adr BETWEEN 1 AND 1000
GROUP BY market_segment;

-- VIEW 3 — vw_revenue_by_country (based on  Query 10)
GO
CREATE OR ALTER VIEW vw_revenue_by_country AS
SELECT 
    country,
    COUNT(*) AS total_bookings,
    SUM(adr * (stays_in_weekend_nights + stays_in_week_nights)) AS total_revenue
FROM clean_bookings
WHERE is_canceled = 0
    AND adr BETWEEN 1 AND 1000
GROUP BY country;

-- VIEW 4 — vw_cancellation_factors (based on Query 4-5)
GO
CREATE OR ALTER VIEW vw_cancellation_factors AS
SELECT 
    is_canceled,
    lead_time,
    total_of_special_requests,
    booking_changes,
    previous_cancellations,
    is_repeated_guest,
    customer_type,
    deposit_type
FROM clean_bookings;

SELECT TABLE_NAME 
FROM INFORMATION_SCHEMA.VIEWS 
WHERE TABLE_NAME LIKE 'vw_%';




