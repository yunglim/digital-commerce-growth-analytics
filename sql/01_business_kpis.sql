-- ============================================================
-- 01. BUSINESS KPIs
-- Digital Commerce Growth Analytics
-- ============================================================

-- ------------------------------------------------------------
-- 1. Initial Session Funnel
-- Purpose:
-- Establish the baseline session-level e-commerce funnel and
-- calculate core conversion rates from product view to purchase.
-- ------------------------------------------------------------

WITH session_events AS (
  SELECT
    user_pseudo_id,

    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,

    event_name

  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name IN (
    'session_start',
    'view_item',
    'add_to_cart',
    'begin_checkout',
    'add_payment_info',
    'purchase'
  )
),

session_funnel AS (
  SELECT
    user_pseudo_id,
    ga_session_id,

    MAX(IF(event_name = 'session_start', 1, 0)) AS started_session,
    MAX(IF(event_name = 'view_item', 1, 0)) AS viewed_item,
    MAX(IF(event_name = 'add_to_cart', 1, 0)) AS added_to_cart,
    MAX(IF(event_name = 'begin_checkout', 1, 0)) AS began_checkout,
    MAX(IF(event_name = 'add_payment_info', 1, 0)) AS added_payment_info,
    MAX(IF(event_name = 'purchase', 1, 0)) AS purchased

  FROM session_events

  WHERE user_pseudo_id IS NOT NULL
    AND ga_session_id IS NOT NULL

  GROUP BY
    user_pseudo_id,
    ga_session_id
)

SELECT
  COUNT(*) AS total_sessions,

  COUNTIF(viewed_item = 1) AS product_view_sessions,
  COUNTIF(added_to_cart = 1) AS cart_sessions,
  COUNTIF(began_checkout = 1) AS checkout_sessions,
  COUNTIF(added_payment_info = 1) AS payment_sessions,
  COUNTIF(purchased = 1) AS purchase_sessions,

  ROUND(
    100 * SAFE_DIVIDE(
      COUNTIF(viewed_item = 1),
      COUNT(*)
    ),
    2
  ) AS session_to_view_pct,

  ROUND(
    100 * SAFE_DIVIDE(
      COUNTIF(began_checkout = 1),
      COUNTIF(viewed_item = 1)
    ),
    2
  ) AS view_to_checkout_pct,

  ROUND(
    100 * SAFE_DIVIDE(
      COUNTIF(purchased = 1),
      COUNTIF(began_checkout = 1)
    ),
    2
  ) AS checkout_to_purchase_pct,

  ROUND(
    100 * SAFE_DIVIDE(
      COUNTIF(purchased = 1),
      COUNT(*)
    ),
    2
  ) AS overall_session_conversion_pct

FROM session_funnel;

-- ------------------------------------------------------------
-- 2. Session Funnel Base
-- Purpose:
-- Build a reusable session-level funnel table with one row per
-- user-session and binary indicators for major funnel actions.
-- ------------------------------------------------------------

WITH session_events AS (
  SELECT
    user_pseudo_id,

    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,

    event_name,
    event_timestamp

  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name IN (
    'session_start',
    'view_item',
    'add_to_cart',
    'begin_checkout',
    'add_shipping_info',
    'add_payment_info',
    'purchase'
  )
),

session_funnel AS (
  SELECT
    user_pseudo_id,
    ga_session_id,

    CONCAT(
      user_pseudo_id,
      '-',
      CAST(ga_session_id AS STRING)
    ) AS session_key,

    MIN(event_timestamp) AS first_event_timestamp,
    MAX(event_timestamp) AS last_event_timestamp,

    MAX(IF(event_name = 'view_item', 1, 0)) AS viewed_item,
    MAX(IF(event_name = 'add_to_cart', 1, 0)) AS added_to_cart,
    MAX(IF(event_name = 'begin_checkout', 1, 0)) AS began_checkout,
    MAX(IF(event_name = 'add_shipping_info', 1, 0)) AS added_shipping_info,
    MAX(IF(event_name = 'add_payment_info', 1, 0)) AS added_payment_info,
    MAX(IF(event_name = 'purchase', 1, 0)) AS purchased

  FROM session_events

  WHERE user_pseudo_id IS NOT NULL
    AND ga_session_id IS NOT NULL

  GROUP BY
    user_pseudo_id,
    ga_session_id
)

SELECT *
FROM session_funnel
LIMIT 100;

-- ------------------------------------------------------------
-- 3. Validated Session Funnel
-- Purpose:
-- Restrict funnel calculations to sessions with a recorded
-- session_start event and calculate validated conversion rates
-- across the main commerce funnel.
-- ------------------------------------------------------------

WITH session_events AS (
  SELECT
    user_pseudo_id,

    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,

    event_name

  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name IN (
    'session_start',
    'view_item',
    'add_to_cart',
    'begin_checkout',
    'add_payment_info',
    'purchase'
  )
),

session_funnel AS (
  SELECT
    user_pseudo_id,
    ga_session_id,

    MAX(IF(event_name = 'session_start', 1, 0))
      AS started_session,

    MAX(IF(event_name = 'view_item', 1, 0))
      AS viewed_item,

    MAX(IF(event_name = 'add_to_cart', 1, 0))
      AS added_to_cart,

    MAX(IF(event_name = 'begin_checkout', 1, 0))
      AS began_checkout,

    MAX(IF(event_name = 'add_payment_info', 1, 0))
      AS added_payment_info,

    MAX(IF(event_name = 'purchase', 1, 0))
      AS purchased

  FROM session_events

  WHERE user_pseudo_id IS NOT NULL
    AND ga_session_id IS NOT NULL

  GROUP BY
    user_pseudo_id,
    ga_session_id
)

SELECT

  -- Session audit
  COUNT(*) AS all_session_keys,

  COUNTIF(started_session = 1)
    AS valid_started_sessions,

  COUNTIF(started_session = 0)
    AS session_keys_without_start,

  -- Main funnel reach
  COUNTIF(
    started_session = 1
    AND viewed_item = 1
  ) AS view_sessions,

  COUNTIF(
    started_session = 1
    AND viewed_item = 1
    AND began_checkout = 1
  ) AS view_to_checkout_sessions,

  COUNTIF(
    started_session = 1
    AND began_checkout = 1
    AND purchased = 1
  ) AS checkout_to_purchase_sessions,

  COUNTIF(
    started_session = 1
    AND purchased = 1
  ) AS purchase_sessions,

  -- Conversion rates
  ROUND(
    100 * SAFE_DIVIDE(
      COUNTIF(
        started_session = 1
        AND viewed_item = 1
      ),
      COUNTIF(started_session = 1)
    ),
    2
  ) AS session_to_view_pct,

  ROUND(
    100 * SAFE_DIVIDE(
      COUNTIF(
        started_session = 1
        AND viewed_item = 1
        AND began_checkout = 1
      ),
      COUNTIF(
        started_session = 1
        AND viewed_item = 1
      )
    ),
    2
  ) AS view_to_checkout_pct,

  ROUND(
    100 * SAFE_DIVIDE(
      COUNTIF(
        started_session = 1
        AND began_checkout = 1
        AND purchased = 1
      ),
      COUNTIF(
        started_session = 1
        AND began_checkout = 1
      )
    ),
    2
  ) AS checkout_to_purchase_pct,

  ROUND(
    100 * SAFE_DIVIDE(
      COUNTIF(
        started_session = 1
        AND purchased = 1
      ),
      COUNTIF(started_session = 1)
    ),
    2
  ) AS overall_session_conversion_pct

FROM session_funnel;

-- ------------------------------------------------------------
-- 4. Clean Order KPIs
-- Purpose:
-- Build a validated order-level dataset using reliable transaction
-- IDs and calculate core revenue and purchaser performance metrics.
-- ------------------------------------------------------------

WITH purchases AS (
  SELECT
    user_pseudo_id,

    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,

    ecommerce.transaction_id AS transaction_id,
    ecommerce.purchase_revenue AS purchase_revenue,
    ecommerce.total_item_quantity AS total_item_quantity,
    event_timestamp

  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name = 'purchase'
),

valid_purchases AS (
  SELECT *
  FROM purchases

  WHERE user_pseudo_id IS NOT NULL
    AND ga_session_id IS NOT NULL
    AND transaction_id IS NOT NULL
    AND transaction_id != ''
    AND transaction_id != '(not set)'
),

clean_orders AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    transaction_id,

    MIN(event_timestamp) AS order_timestamp,

    ANY_VALUE(purchase_revenue) AS order_revenue,
    ANY_VALUE(total_item_quantity) AS item_quantity

  FROM valid_purchases

  GROUP BY
    user_pseudo_id,
    ga_session_id,
    transaction_id
)

SELECT
  COUNT(*) AS orders,

  COUNT(DISTINCT user_pseudo_id)
    AS purchasers,

  COUNT(
    DISTINCT CONCAT(
      user_pseudo_id,
      '-',
      CAST(ga_session_id AS STRING)
    )
  ) AS purchasing_sessions,

  ROUND(
    SUM(order_revenue),
    2
  ) AS revenue,

  ROUND(
    AVG(order_revenue),
    2
  ) AS average_order_value,

  SUM(item_quantity)
    AS items_sold,

  ROUND(
    AVG(item_quantity),
    2
  ) AS average_items_per_order,

  ROUND(
    SAFE_DIVIDE(
      SUM(order_revenue),
      COUNT(DISTINCT user_pseudo_id)
    ),
    2
  ) AS revenue_per_purchaser

FROM clean_orders;

-- ------------------------------------------------------------
-- 5. Daily Funnel and Order Performance
-- Purpose:
-- Combine validated daily funnel metrics with clean order-level
-- revenue metrics to compare traffic, conversion, and transaction
-- performance over time.
-- ------------------------------------------------------------

WITH session_events AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    user_pseudo_id,

    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,

    event_name

  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name IN (
    'session_start',
    'view_item',
    'begin_checkout',
    'purchase'
  )
),

session_daily AS (
  SELECT
    event_date,
    user_pseudo_id,
    ga_session_id,

    MAX(IF(event_name = 'session_start', 1, 0))
      AS started_session,

    MAX(IF(event_name = 'view_item', 1, 0))
      AS viewed_item,

    MAX(IF(event_name = 'begin_checkout', 1, 0))
      AS began_checkout,

    MAX(IF(event_name = 'purchase', 1, 0))
      AS purchased

  FROM session_events

  WHERE user_pseudo_id IS NOT NULL
    AND ga_session_id IS NOT NULL

  GROUP BY
    event_date,
    user_pseudo_id,
    ga_session_id
),

daily_funnel AS (
  SELECT
    event_date,

    COUNTIF(started_session = 1)
      AS sessions,

    COUNTIF(
      started_session = 1
      AND viewed_item = 1
    ) AS product_view_sessions,

    COUNTIF(
      started_session = 1
      AND began_checkout = 1
    ) AS checkout_sessions,

    COUNTIF(
      started_session = 1
      AND purchased = 1
    ) AS purchase_sessions

  FROM session_daily

  GROUP BY event_date
),

purchases AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS order_date,
    user_pseudo_id,

    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,

    ecommerce.transaction_id AS transaction_id,
    ecommerce.purchase_revenue AS purchase_revenue,
    ecommerce.total_item_quantity AS total_item_quantity

  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name = 'purchase'
),

valid_purchases AS (
  SELECT *
  FROM purchases

  WHERE user_pseudo_id IS NOT NULL
    AND ga_session_id IS NOT NULL
    AND transaction_id IS NOT NULL
    AND transaction_id != ''
    AND transaction_id != '(not set)'
),

clean_orders AS (
  SELECT
    order_date,
    user_pseudo_id,
    ga_session_id,
    transaction_id,

    ANY_VALUE(purchase_revenue) AS order_revenue,
    ANY_VALUE(total_item_quantity) AS item_quantity

  FROM valid_purchases

  GROUP BY
    order_date,
    user_pseudo_id,
    ga_session_id,
    transaction_id
),

daily_orders AS (
  SELECT
    order_date,

    COUNT(*) AS orders,
    ROUND(SUM(order_revenue), 2) AS revenue,
    ROUND(AVG(order_revenue), 2) AS average_order_value,
    SUM(item_quantity) AS items_sold

  FROM clean_orders

  GROUP BY order_date
)

SELECT
  f.event_date,

  f.sessions,
  f.product_view_sessions,
  f.checkout_sessions,
  f.purchase_sessions,

  COALESCE(o.orders, 0) AS clean_orders,
  COALESCE(o.revenue, 0) AS clean_revenue,
  o.average_order_value,
  COALESCE(o.items_sold, 0) AS items_sold,

  ROUND(
    100 * SAFE_DIVIDE(
      f.product_view_sessions,
      f.sessions
    ),
    2
  ) AS product_view_rate_pct,

  ROUND(
    100 * SAFE_DIVIDE(
      f.purchase_sessions,
      f.sessions
    ),
    2
  ) AS session_conversion_pct,

  ROUND(
    100 * SAFE_DIVIDE(
      f.purchase_sessions,
      f.checkout_sessions
    ),
    2
  ) AS checkout_to_purchase_pct

FROM daily_funnel AS f

LEFT JOIN daily_orders AS o
  ON f.event_date = o.order_date

ORDER BY f.event_date;

-- ------------------------------------------------------------
-- 6. Daily Order Performance
-- Purpose:
-- Aggregate validated clean orders by date to track daily
-- order volume, purchasers, revenue, AOV, and item quantity.
-- ------------------------------------------------------------

WITH purchases AS (
  SELECT
    user_pseudo_id,

    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,

    ecommerce.transaction_id AS transaction_id,
    ecommerce.purchase_revenue AS purchase_revenue,
    ecommerce.total_item_quantity AS total_item_quantity,
    event_timestamp

  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name = 'purchase'
),

valid_purchases AS (
  SELECT *
  FROM purchases

  WHERE user_pseudo_id IS NOT NULL
    AND ga_session_id IS NOT NULL
    AND transaction_id IS NOT NULL
    AND transaction_id != ''
    AND transaction_id != '(not set)'
),

clean_orders AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    transaction_id,

    MIN(event_timestamp) AS order_timestamp,
    ANY_VALUE(purchase_revenue) AS order_revenue,
    ANY_VALUE(total_item_quantity) AS item_quantity

  FROM valid_purchases

  GROUP BY
    user_pseudo_id,
    ga_session_id,
    transaction_id
)

SELECT
  DATE(TIMESTAMP_MICROS(order_timestamp)) AS order_date,

  COUNT(*) AS orders,

  COUNT(DISTINCT user_pseudo_id) AS purchasers,

  ROUND(SUM(order_revenue), 2) AS revenue,

  ROUND(AVG(order_revenue), 2) AS average_order_value,

  SUM(item_quantity) AS items_sold,

  ROUND(AVG(item_quantity), 2) AS average_items_per_order

FROM clean_orders

GROUP BY order_date
ORDER BY order_date;

-- ------------------------------------------------------------
-- 7. Monthly Order Performance
-- Purpose:
-- Aggregate validated orders by month and compare revenue,
-- order volume, purchaser counts, daily averages, and transaction
-- ID coverage across the observed periods.
-- ------------------------------------------------------------

WITH purchase_events AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    user_pseudo_id,

    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,

    ecommerce.transaction_id AS transaction_id,
    ecommerce.purchase_revenue AS purchase_revenue,
    ecommerce.total_item_quantity AS total_item_quantity

  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name = 'purchase'
    AND PARSE_DATE('%Y%m%d', event_date) >= DATE '2020-11-12'
),

purchase_quality AS (
  SELECT
    DATE_TRUNC(event_date, MONTH) AS month,

    COUNT(*) AS purchase_events,

    COUNTIF(
      transaction_id IS NOT NULL
      AND transaction_id != ''
      AND transaction_id != '(not set)'
    ) AS valid_transaction_events

  FROM purchase_events

  GROUP BY month
),

valid_purchases AS (
  SELECT *
  FROM purchase_events

  WHERE user_pseudo_id IS NOT NULL
    AND ga_session_id IS NOT NULL
    AND transaction_id IS NOT NULL
    AND transaction_id != ''
    AND transaction_id != '(not set)'
),

clean_orders AS (
  SELECT
    event_date,
    user_pseudo_id,
    ga_session_id,
    transaction_id,

    ANY_VALUE(purchase_revenue) AS order_revenue,
    ANY_VALUE(total_item_quantity) AS item_quantity

  FROM valid_purchases

  GROUP BY
    event_date,
    user_pseudo_id,
    ga_session_id,
    transaction_id
),

monthly_orders AS (
  SELECT
    DATE_TRUNC(event_date, MONTH) AS month,

    COUNT(DISTINCT event_date) AS observed_days,
    COUNT(*) AS orders,
    COUNT(DISTINCT user_pseudo_id) AS purchasers,

    ROUND(SUM(order_revenue), 2) AS revenue,
    ROUND(AVG(order_revenue), 2) AS average_order_value,

    SUM(item_quantity) AS items_sold

  FROM clean_orders

  GROUP BY month
)

SELECT
  m.month,
  m.observed_days,
  m.orders,
  m.purchasers,
  m.revenue,
  m.average_order_value,
  m.items_sold,

  ROUND(
    SAFE_DIVIDE(m.revenue, m.observed_days),
    2
  ) AS avg_daily_revenue,

  ROUND(
    SAFE_DIVIDE(m.orders, m.observed_days),
    2
  ) AS avg_daily_orders,

  ROUND(
    100 * SAFE_DIVIDE(
      q.valid_transaction_events,
      q.purchase_events
    ),
    2
  ) AS valid_transaction_pct

FROM monthly_orders AS m

LEFT JOIN purchase_quality AS q
  ON m.month = q.month

ORDER BY m.month;

-- ------------------------------------------------------------
-- 8. Period Performance Summary
-- Purpose:
-- Compare funnel activity and validated order performance across
-- three consistent analysis periods to evaluate changes in
-- traffic, conversion, revenue, and purchasing behavior.
-- ------------------------------------------------------------

WITH session_events AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    user_pseudo_id,

    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,

    event_name

  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name IN (
    'session_start',
    'view_item',
    'begin_checkout',
    'purchase'
  )
),

session_level AS (
  SELECT
    event_date,
    user_pseudo_id,
    ga_session_id,

    MAX(IF(event_name = 'session_start', 1, 0))
      AS started_session,

    MAX(IF(event_name = 'view_item', 1, 0))
      AS viewed_item,

    MAX(IF(event_name = 'begin_checkout', 1, 0))
      AS began_checkout,

    MAX(IF(event_name = 'purchase', 1, 0))
      AS purchased

  FROM session_events

  WHERE user_pseudo_id IS NOT NULL
    AND ga_session_id IS NOT NULL

  GROUP BY
    event_date,
    user_pseudo_id,
    ga_session_id
),

session_periods AS (
  SELECT
    CASE
      WHEN event_date BETWEEN DATE '2020-11-12' AND DATE '2020-11-30'
        THEN 'Nov 12-30'
      WHEN event_date BETWEEN DATE '2020-12-01' AND DATE '2020-12-31'
        THEN 'December'
      WHEN event_date BETWEEN DATE '2021-01-01' AND DATE '2021-01-25'
        THEN 'Jan 1-25'
    END AS period,

    event_date,
    started_session,
    viewed_item,
    began_checkout,
    purchased

  FROM session_level

  WHERE event_date BETWEEN DATE '2020-11-12' AND DATE '2021-01-25'
),

session_summary AS (
  SELECT
    period,

    COUNT(DISTINCT event_date) AS days,

    COUNTIF(started_session = 1)
      AS sessions,

    COUNTIF(
      started_session = 1
      AND viewed_item = 1
    ) AS product_view_sessions,

    COUNTIF(
      started_session = 1
      AND began_checkout = 1
    ) AS checkout_sessions,

    COUNTIF(
      started_session = 1
      AND purchased = 1
    ) AS purchase_sessions

  FROM session_periods

  GROUP BY period
),

purchase_events AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    user_pseudo_id,

    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,

    ecommerce.transaction_id AS transaction_id,
    ecommerce.purchase_revenue AS purchase_revenue,
    ecommerce.total_item_quantity AS total_item_quantity

  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name = 'purchase'
    AND PARSE_DATE('%Y%m%d', event_date)
        BETWEEN DATE '2020-11-12' AND DATE '2021-01-25'
),

valid_purchases AS (
  SELECT *
  FROM purchase_events

  WHERE user_pseudo_id IS NOT NULL
    AND ga_session_id IS NOT NULL
    AND transaction_id IS NOT NULL
    AND transaction_id != ''
    AND transaction_id != '(not set)'
),

clean_orders AS (
  SELECT
    event_date,
    user_pseudo_id,
    ga_session_id,
    transaction_id,

    ANY_VALUE(purchase_revenue) AS order_revenue,
    ANY_VALUE(total_item_quantity) AS item_quantity

  FROM valid_purchases

  GROUP BY
    event_date,
    user_pseudo_id,
    ga_session_id,
    transaction_id
),

order_periods AS (
  SELECT
    CASE
      WHEN event_date BETWEEN DATE '2020-11-12' AND DATE '2020-11-30'
        THEN 'Nov 12-30'
      WHEN event_date BETWEEN DATE '2020-12-01' AND DATE '2020-12-31'
        THEN 'December'
      WHEN event_date BETWEEN DATE '2021-01-01' AND DATE '2021-01-25'
        THEN 'Jan 1-25'
    END AS period,

    *

  FROM clean_orders
),

order_summary AS (
  SELECT
    period,

    COUNT(*) AS clean_orders,
    COUNT(DISTINCT user_pseudo_id) AS purchasers,

    ROUND(SUM(order_revenue), 2)
      AS clean_revenue,

    ROUND(AVG(order_revenue), 2)
      AS average_order_value,

    SUM(item_quantity)
      AS items_sold

  FROM order_periods

  GROUP BY period
)

SELECT
  s.period,
  s.days,

  s.sessions,
  s.product_view_sessions,
  s.checkout_sessions,
  s.purchase_sessions,

  o.clean_orders,
  o.purchasers,
  o.clean_revenue,
  o.average_order_value,
  o.items_sold,

  ROUND(
    SAFE_DIVIDE(s.sessions, s.days),
    2
  ) AS avg_daily_sessions,

  ROUND(
    SAFE_DIVIDE(o.clean_orders, s.days),
    2
  ) AS avg_daily_orders,

  ROUND(
    SAFE_DIVIDE(o.clean_revenue, s.days),
    2
  ) AS avg_daily_revenue,

  ROUND(
    100 * SAFE_DIVIDE(
      s.purchase_sessions,
      s.sessions
    ),
    2
  ) AS session_conversion_pct,

  ROUND(
    100 * SAFE_DIVIDE(
      s.product_view_sessions,
      s.sessions
    ),
    2
  ) AS product_view_rate_pct,

  ROUND(
    100 * SAFE_DIVIDE(
      s.purchase_sessions,
      s.checkout_sessions
    ),
    2
  ) AS checkout_to_purchase_pct

FROM session_summary AS s

LEFT JOIN order_summary AS o
  ON s.period = o.period

ORDER BY
  CASE s.period
    WHEN 'Nov 12-30' THEN 1
    WHEN 'December' THEN 2
    WHEN 'Jan 1-25' THEN 3
  END;
