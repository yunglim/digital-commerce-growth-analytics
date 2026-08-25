-- ============================================================
-- 08. MACHINE LEARNING DATASET
-- Digital Commerce Growth Analytics
-- ============================================================

-- ------------------------------------------------------------
-- 1. Repeat Purchase Modeling Dataset
-- Purpose:
-- Build a customer-level modeling dataset using only information
-- available on or before the first purchase and create a 30-day
-- repeat-purchase target for supervised classification.
-- ------------------------------------------------------------

WITH base_events AS (
  SELECT
    user_pseudo_id,

    TIMESTAMP_MICROS(event_timestamp)
      AS event_timestamp,

    PARSE_DATE(
      '%Y%m%d',
      event_date
    ) AS event_date,

    event_name,

    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,

    device.category
      AS device_category,

    COALESCE(
      traffic_source.source,
      '(unknown)'
    ) AS first_source,

    COALESCE(
      traffic_source.medium,
      '(unknown)'
    ) AS first_medium,

    ecommerce.transaction_id
      AS transaction_id,

    ecommerce.purchase_revenue
      AS purchase_revenue,

    ecommerce.total_item_quantity
      AS total_item_quantity

  FROM
    `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE PARSE_DATE(
    '%Y%m%d',
    event_date
  )
  BETWEEN DATE '2020-11-01'
      AND DATE '2021-01-25'
),

valid_purchase_events AS (
  SELECT *

  FROM base_events

  WHERE event_name = 'purchase'

    AND user_pseudo_id IS NOT NULL
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

    MIN(event_timestamp)
      AS order_timestamp,

    MIN(event_date)
      AS order_date,

    ANY_VALUE(purchase_revenue)
      AS order_revenue,

    ANY_VALUE(total_item_quantity)
      AS order_items,

    ARRAY_AGG(
      device_category
      IGNORE NULLS
      ORDER BY event_timestamp
      LIMIT 1
    )[SAFE_OFFSET(0)]
      AS device_category,

    ARRAY_AGG(
      first_source
      IGNORE NULLS
      ORDER BY event_timestamp
      LIMIT 1
    )[SAFE_OFFSET(0)]
      AS first_source,

    ARRAY_AGG(
      first_medium
      IGNORE NULLS
      ORDER BY event_timestamp
      LIMIT 1
    )[SAFE_OFFSET(0)]
      AS first_medium

  FROM valid_purchase_events

  GROUP BY
    user_pseudo_id,
    ga_session_id,
    transaction_id
),

ranked_orders AS (
  SELECT
    *,

    ROW_NUMBER() OVER (
      PARTITION BY user_pseudo_id

      ORDER BY
        order_timestamp,
        transaction_id
    ) AS purchase_number

  FROM clean_orders
),

first_orders AS (
  SELECT
    user_pseudo_id,

    order_timestamp
      AS first_order_timestamp,

    order_date
      AS first_order_date,

    order_revenue
      AS first_order_revenue,

    order_items
      AS first_order_items,

    device_category,
    first_source,
    first_medium

  FROM ranked_orders

  WHERE purchase_number = 1

    -- Must have a complete 30-day outcome window
    AND order_date
      BETWEEN DATE '2020-11-12'
          AND DATE '2020-12-26'
),

customer_labels AS (
  SELECT
    f.*,

    COUNTIF(
      o.order_timestamp > f.first_order_timestamp

      AND o.order_timestamp <= TIMESTAMP_ADD(
        f.first_order_timestamp,
        INTERVAL 30 DAY
      )
    ) AS repeat_orders_30d

  FROM first_orders AS f

  LEFT JOIN clean_orders AS o
    ON f.user_pseudo_id = o.user_pseudo_id

  GROUP BY
    f.user_pseudo_id,
    f.first_order_timestamp,
    f.first_order_date,
    f.first_order_revenue,
    f.first_order_items,
    f.device_category,
    f.first_source,
    f.first_medium
),

pre_purchase_behavior AS (
  SELECT
    c.user_pseudo_id,

    COUNT(
      DISTINCT IF(
        e.ga_session_id IS NOT NULL,
        CAST(e.ga_session_id AS STRING),
        NULL
      )
    ) AS sessions_before_first_purchase,

    COUNTIF(
      e.event_name = 'view_item'
    ) AS product_views_before_purchase,

    COUNTIF(
      e.event_name = 'add_to_cart'
    ) AS add_to_cart_before_purchase,

    COUNTIF(
      e.event_name = 'begin_checkout'
    ) AS checkout_events_before_purchase,

    COUNTIF(
      e.event_name = 'view_search_results'
    ) AS search_events_before_purchase,

    MIN(
      IF(
        e.event_name = 'first_visit',
        e.event_timestamp,
        NULL
      )
    ) AS first_visit_timestamp

  FROM customer_labels AS c

  LEFT JOIN base_events AS e
    ON c.user_pseudo_id = e.user_pseudo_id

   -- Absolutely no information after first purchase
   AND e.event_timestamp
       <= c.first_order_timestamp

  GROUP BY c.user_pseudo_id
)

SELECT
  c.user_pseudo_id,

  c.first_order_date,

  EXTRACT(
    DAYOFWEEK
    FROM c.first_order_timestamp
  ) AS purchase_day_of_week,

  EXTRACT(
    HOUR
    FROM c.first_order_timestamp
  ) AS purchase_hour_utc,

  c.device_category,
  c.first_source,
  c.first_medium,

  ROUND(
    c.first_order_revenue,
    2
  ) AS first_order_revenue,

  c.first_order_items,

  p.sessions_before_first_purchase,
  p.product_views_before_purchase,
  p.add_to_cart_before_purchase,
  p.checkout_events_before_purchase,
  p.search_events_before_purchase,

  CASE
    WHEN p.first_visit_timestamp IS NULL
      THEN NULL

    ELSE TIMESTAMP_DIFF(
      c.first_order_timestamp,
      p.first_visit_timestamp,
      DAY
    )
  END AS days_first_visit_to_purchase,

  CASE
    WHEN c.repeat_orders_30d >= 1
      THEN 1
    ELSE 0
  END AS repeat_purchase_30d

FROM customer_labels AS c

LEFT JOIN pre_purchase_behavior AS p
  USING (user_pseudo_id)

ORDER BY c.first_order_date;

-- ------------------------------------------------------------
-- 2. Modeling Dataset Validation
-- Purpose:
-- Validate the final customer-level modeling table by checking
-- row uniqueness, target-class balance, and missing values across
-- key predictive features.
-- ------------------------------------------------------------

SELECT
  COUNT(*) AS row_count,
  COUNT(DISTINCT user_pseudo_id) AS unique_users,

  COUNTIF(repeat_purchase_30d = 1) AS repeat_buyers,
  COUNTIF(repeat_purchase_30d = 0) AS one_time_buyers,

  ROUND(
    100 * SAFE_DIVIDE(
      COUNTIF(repeat_purchase_30d = 1),
      COUNT(*)
    ),
    2
  ) AS positive_class_pct,

  COUNTIF(first_order_revenue IS NULL) AS null_revenue,
  COUNTIF(first_order_items IS NULL) AS null_items,
  COUNTIF(device_category IS NULL) AS null_device,
  COUNTIF(first_source IS NULL) AS null_source,
  COUNTIF(first_medium IS NULL) AS null_medium,
  COUNTIF(sessions_before_first_purchase IS NULL) AS null_sessions,
  COUNTIF(days_first_visit_to_purchase IS NULL) AS null_days_to_purchase

FROM `dc-growth-analytics-260811.analytics.ml_repeat_purchase_dataset`;
