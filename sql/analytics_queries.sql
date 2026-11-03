-- NYC Yellow Taxi analytics queries
-- Run after the notebook creates these SQLite tables:
--   fact_daily_zone, dim_zone, dim_date
-- Database created by the notebook: data/urban_mobility.db

-- 1. Check row and pickup totals in the fact table.
SELECT
    COUNT(*) AS date_zone_rows,
    SUM(pickups) AS accepted_pickups,
    SUM(metric_trips) AS screened_trips
FROM fact_daily_zone;

-- 2. Top 10 pickup zones by accepted pickup volume.
SELECT
    z.pickup_zone_id,
    z.pickup_zone,
    z.pickup_borough,
    SUM(f.pickups) AS accepted_pickups
FROM fact_daily_zone AS f
LEFT JOIN dim_zone AS z
    ON f.pickup_zone_id = z.pickup_zone_id
GROUP BY
    z.pickup_zone_id,
    z.pickup_zone,
    z.pickup_borough
ORDER BY accepted_pickups DESC
LIMIT 10;

-- 3. Average fare and trip duration for screened metric records.
-- SUM(metric) / SUM(metric_trips) gives a weighted average across dates/zones.
SELECT
    z.pickup_zone_id,
    z.pickup_zone,
    z.pickup_borough,
    SUM(f.pickups) AS accepted_pickups,
    SUM(f.metric_trips) AS screened_trips,
    ROUND(
        1.0 * SUM(f.fare_sum) / NULLIF(SUM(f.metric_trips), 0),
        2
    ) AS average_fare_usd,
    ROUND(
        1.0 * SUM(f.duration_sum) / NULLIF(SUM(f.metric_trips), 0),
        2
    ) AS average_duration_minutes
FROM fact_daily_zone AS f
LEFT JOIN dim_zone AS z
    ON f.pickup_zone_id = z.pickup_zone_id
GROUP BY
    z.pickup_zone_id,
    z.pickup_zone,
    z.pickup_borough
ORDER BY accepted_pickups DESC
LIMIT 10;

-- 4. Average daily pickups: weekdays versus weekends.
WITH daily_totals AS (
    SELECT
        d.date,
        d.is_weekend,
        COALESCE(SUM(f.pickups), 0) AS daily_pickups
    FROM dim_date AS d
    LEFT JOIN fact_daily_zone AS f
        ON d.date = f.date
    GROUP BY d.date, d.is_weekend
)
SELECT
    CASE WHEN is_weekend = 1 THEN 'Weekend' ELSE 'Weekday' END AS day_type,
    COUNT(*) AS calendar_days,
    SUM(daily_pickups) AS total_pickups,
    ROUND(AVG(daily_pickups), 2) AS average_daily_pickups
FROM daily_totals
GROUP BY is_weekend
ORDER BY is_weekend;

-- 5. Day-to-day pickup changes using LAG.
WITH daily_totals AS (
    SELECT
        d.date,
        COALESCE(SUM(f.pickups), 0) AS daily_pickups
    FROM dim_date AS d
    LEFT JOIN fact_daily_zone AS f
        ON d.date = f.date
    GROUP BY d.date
),
daily_with_previous AS (
    SELECT
        date,
        daily_pickups,
        LAG(daily_pickups, 1) OVER (ORDER BY date) AS previous_day_pickups
    FROM daily_totals
)
SELECT
    date,
    daily_pickups,
    previous_day_pickups,
    daily_pickups - previous_day_pickups AS pickup_change,
    ROUND(
        100.0 * (daily_pickups - previous_day_pickups)
        / NULLIF(previous_day_pickups, 0),
        2
    ) AS pickup_change_pct
FROM daily_with_previous
ORDER BY date;

-- 6. Seven-day moving average using a window frame.
WITH daily_totals AS (
    SELECT
        d.date,
        COALESCE(SUM(f.pickups), 0) AS daily_pickups
    FROM dim_date AS d
    LEFT JOIN fact_daily_zone AS f
        ON d.date = f.date
    GROUP BY d.date
),
rolling_summary AS (
    SELECT
        date,
        daily_pickups,
        COUNT(*) OVER (
            ORDER BY date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS days_in_window,
        AVG(daily_pickups) OVER (
            ORDER BY date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS rolling_average
    FROM daily_totals
)
SELECT
    date,
    daily_pickups,
    CASE WHEN days_in_window = 7 THEN rolling_average END AS moving_average_7d
FROM rolling_summary
ORDER BY date;

-- 7. Join-integrity check: all fact pickups should match a zone dimension row.
SELECT
    SUM(f.pickups) AS joined_pickups,
    SUM(
        CASE WHEN z.pickup_zone_id IS NULL THEN f.pickups ELSE 0 END
    ) AS unmatched_pickups
FROM fact_daily_zone AS f
LEFT JOIN dim_zone AS z
    ON f.pickup_zone_id = z.pickup_zone_id;
