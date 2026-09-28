# Hotel Booking Analysis — SQL Server + Power BI

An end-to-end data analytics project: raw CSV → SQL Server (cleaning & analysis) → Power BI dashboard, answering business questions about **booking cancellations** and **revenue** for two hotels in Portugal.

## 1. Business Problem

A hotel group operating a **City Hotel** and a **Resort Hotel** wants to understand:

1. Which bookings are most likely to be cancelled, and why?
2. Where does revenue come from (market segment, country, hotel)?
3. How do pricing (ADR) and seasonality behave over time?

## 2. Dataset

- **Source:** *Hotel Booking Demand* (Antonio, Almeida & Nunes, 2019)
- **Size:** 119,390 rows × 32 columns (one row = one booking)
- **Period:** 2015–2017
- **Key fields:** `is_canceled`, `lead_time`, `deposit_type`, `market_segment`, `country`, `adr`, `stays_in_weekend_nights`, `stays_in_week_nights`, `customer_type`

> Revenue is not in the raw data. It is derived as `adr × (stays_in_weekend_nights + stays_in_week_nights)` and counted only for non-cancelled bookings.

## 3. Tech Stack

| Layer | Tool |
|---|---|
| Database | SQL Server |
| Query tool | SSMS |
| BI | Power BI Desktop (Power Query, DAX) |
| Version control | Git / GitHub |

## 4. Workflow

### Step 1 — Load data
Created `HotelBookingDB` and imported the CSV into `raw_bookings` with the SSMS Import Flat File wizard. Verified `COUNT(*) = 119,390`.

### Step 2 — Data cleaning (SQL)
- Removed **180** junk rows with 0 adults, 0 children and 0 babies → **119,210** rows in `clean_bookings`.
- Replaced missing values: `children` → 0, `agent` → 0, `company` → 0.
- Found that `company` stored missing values as the **text string `'NULL'`**, not real NULL, so a plain `IS NULL` check would have missed them.
- Checked data types (`is_canceled` is `bit`, so it is cast to `INT` before `SUM`/`AVG`).

### Step 3 — Analysis (SQL)
10 queries in [`sql/queries.sql`](sql/queries.sql) covering:

- `GROUP BY` / aggregate functions
- CTEs (including nested CTEs)
- Window functions: `ROW_NUMBER`, `RANK`, `AVG() OVER (PARTITION BY ...)`
- Subqueries
- `OFFSET / FETCH`

Four views feed Power BI: `vw_bookings_detail`, `vw_cancellation_factors`, `vw_revenue_by_segment`, `vw_revenue_by_country`.

### Step 4 — Dashboard (Power BI)
Three pages: **Overview**, **Cancellation Analysis**, **Revenue Analysis**.

- Connected to SQL Server; built a Date dimension table and relationships
- DAX measures organised in a dedicated `_Measures` table
- Slicers for Year and Hotel, synced across pages
- Page navigation buttons

## 5. Key Insights

- **Cancellation differs sharply by hotel:** City Hotel **41.79%** vs Resort Hotel **27.77%**.
- **Lead time matters:** cancelled bookings were made on average **144.9 days** ahead versus **80.1 days** for non-cancelled ones. The earlier the booking, the higher the risk.
- **Deposit type:** `Non Refund` bookings show a counter-intuitive cancellation pattern (a "Non Refund paradox") that deserves a closer look before drawing pricing conclusions.
- **Portugal (PRT)** leads both bookings (**48,483**) and revenue (~**€5.54M**).
- **Online TA** is the top revenue segment (~**€13.7M**).
- **ADR vs monthly average (Query 7):** comparing each booking's ADR to its month's average highlights pricing outliers and seasonal price swings.

## 6. Dashboard Preview

![Overview](images/overview.png)
![Cancellation Analysis](images/cancellation.png)
![Revenue Analysis](images/revenue.png)

## 7. Repository Structure

```
hotel-booking-sql-powerbi-project/
├── data/            # hotel_bookings.csv (raw data)
├── sql/
│   └── queries.sql  # cleaning, 10 analysis queries, 4 views
├── powerbi/
│   └── *.pbix       # Power BI dashboard
├── images/          # dashboard screenshots
└── README.md
```

## 8. How to Reproduce

1. Install SQL Server, SSMS and Power BI Desktop.
2. Create database `HotelBookingDB`.
3. Import `hotel_bookings.csv` into a table named `raw_bookings` (SSMS → Tasks → Import Flat File).
4. Open `sql/queries.sql` in SSMS and run it in order. `clean_bookings` is created with `SELECT INTO`; to re-run, `DROP TABLE IF EXISTS clean_bookings` first.
5. Open the `.pbix` file in `powerbi/` and point the data source to your SQL Server instance (Transform data → Data source settings).

## 9. Limitations

- Data covers only 2015–2017 for two hotels in Portugal, so results may not generalise.
- `adr = 0` rows (possible complimentary stays) and extreme ADR values are treated as outliers when computing revenue.
- Revenue is an estimate derived from ADR × nights.

## 10. Author

*Your name* — [LinkedIn](https://www.linkedin.com/) · [GitHub](https://github.com/)
