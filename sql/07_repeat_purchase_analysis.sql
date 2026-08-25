-- ============================================================
-- 07. REPEAT PURCHASE ANALYSIS
-- Digital Commerce Growth Analytics
-- ============================================================

-- ------------------------------------------------------------
-- 1. Customer Lifecycle Segmentation
-- Purpose:
-- Segment customers based on whether a second purchase occurs
-- within 7 days, within 30 days, or not within 30 days, and
-- compare 30-day order, revenue, and item value across segments.
-- ------------------------------------------------------------

WITH purchase_events AS (
  SELECT
    user_pseudo_id,
    event_timestamp,

    PARSE_DATE('%Y%m%d', event_date) AS event_date,

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
        BETWEEN DATE '2020-11-12'
            AND DATE '2021-01-25'
),

valid_purchase_events AS (
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
    user_pseudo_id,
    transaction_id,

    MIN(event_timestamp) AS order_timestamp,
    MIN(event_date) AS order_date,

    ANY_VALUE(purchase_revenue) AS order_revenue,
    ANY_VALUE(total_item_quantity) AS item_quantity

  FROM valid_purchase_events

  GROUP BY
    user_pseudo_id,
    transaction_id
),

ranked_orders AS (
  SELECT
    *,

    ROW_NUMBER() OVER (
      PARTITION BY user_pseudo_id
      ORDER BY order_timestamp, transaction_id
    ) AS purchase_number

  FROM clean_orders
),

first_purchase AS (
  SELECT
    user_pseudo_id,

    MIN(order_date) AS first_purchase_date,

    MIN(
      IF(purchase_number = 2, order_date, NULL)
    ) AS second_purchase_date

  FROM ranked_orders

  GROUP BY user_pseudo_id
),

eligible_customers AS (
  SELECT
    user_pseudo_id,
    first_purchase_date,
    second_purchase_date,

    DATE_DIFF(
      second_purchase_date,
      first_purchase_date,
      DAY
    ) AS days_to_second_purchase

  FROM first_purchase

  WHERE first_purchase_date
    BETWEEN DATE '2020-11-12'
        AND DATE '2020-12-26'
),

customer_value AS (
  SELECT
    c.user_pseudo_id,
    c.first_purchase_date,
    c.days_to_second_purchase,

    COUNT(o.transaction_id) AS orders_30d,

    ROUND(
      SUM(o.order_revenue),
      2
    ) AS revenue_30d,

    SUM(o.item_quantity) AS items_30d

  FROM eligible_customers AS c

  JOIN clean_orders AS o
    ON c.user_pseudo_id = o.user_pseudo_id
   AND o.order_date BETWEEN
       c.first_purchase_date
       AND DATE_ADD(c.first_purchase_date, INTERVAL 30 DAY)

  GROUP BY
    c.user_pseudo_id,
    c.first_purchase_date,
    c.days_to_second_purchase
),

segmented AS (
  SELECT
    *,

    CASE
      WHEN days_to_second_purchase BETWEEN 0 AND 7
        THEN 'Early Repeat Buyer'

      WHEN days_to_second_purchase BETWEEN 8 AND 30
        THEN 'Later Repeat Buyer'

      ELSE 'One-Time Buyer'
    END AS customer_segment

  FROM customer_value
)

SELECT
  customer_segment,

  COUNT(*) AS customers,

  ROUND(
    100 * SAFE_DIVIDE(
      COUNT(*),
      SUM(COUNT(*)) OVER ()
    ),
    2
  ) AS customer_share_pct,

  ROUND(
    AVG(orders_30d),
    2
  ) AS avg_orders_30d,

  ROUND(
    AVG(revenue_30d),
    2
  ) AS avg_revenue_30d,

  ROUND(
    AVG(items_30d),
    2
  ) AS avg_items_30d,

  ROUND(
    SAFE_DIVIDE(
      SUM(revenue_30d),
      SUM(orders_30d)
    ),
    2
  ) AS avg_order_value_30d,

  ROUND(
    SUM(revenue_30d),
    2
  ) AS total_segment_revenue_30d,

  ROUND(
    100 * SAFE_DIVIDE(
      SUM(revenue_30d),
      SUM(SUM(revenue_30d)) OVER ()
    ),
    2
  ) AS revenue_share_pct

FROM segmented

GROUP BY customer_segment

ORDER BY
  CASE customer_segment
    WHEN 'Early Repeat Buyer' THEN 1
    WHEN 'Later Repeat Buyer' THEN 2
    WHEN 'One-Time Buyer' THEN 3
  END;

-- ------------------------------------------------------------
-- 2. Repeat Purchase Within 30 Days
-- Purpose:
-- Measure 7-day, 14-day, and 30-day repeat-purchase rates and
-- compare customer value within the first 30 days after purchase.
-- ------------------------------------------------------------

WITH purchase_events AS (
  SELECT
    user_pseudo_id,
    event_timestamp,

    PARSE_DATE(
      '%Y%m%d',
      event_date
    ) AS event_date,

    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,

    ecommerce.transaction_id
      AS transaction_id,

    ecommerce.purchase_revenue
      AS purchase_revenue

  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name = 'purchase'

    AND PARSE_DATE('%Y%m%d', event_date)
      BETWEEN DATE '2020-11-12'
          AND DATE '2021-01-25'
),

valid_purchase_events AS (
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
    user_pseudo_id,
    ga_session_id,
    transaction_id,

    MIN(event_timestamp)
      AS order_timestamp,

    MIN(event_date)
      AS order_date,

    ANY_VALUE(purchase_revenue)
      AS order_revenue

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

first_purchases AS (
  SELECT
    user_pseudo_id,

    MIN(
      IF(
        purchase_number = 1,
        order_date,
        NULL
      )
    ) AS first_purchase_date,

    MIN(
      IF(
        purchase_number = 2,
        order_date,
        NULL
      )
    ) AS second_purchase_date

  FROM ranked_orders

  GROUP BY user_pseudo_id
),

eligible_customers AS (
  SELECT
    user_pseudo_id,
    first_purchase_date,
    second_purchase_date,

    CASE
      WHEN first_purchase_date
        BETWEEN DATE '2020-11-12'
            AND DATE '2020-11-30'
        THEN 'Nov 12-30'

      WHEN first_purchase_date
        BETWEEN DATE '2020-12-01'
            AND DATE '2020-12-26'
        THEN 'Dec 1-26'
    END AS first_purchase_period,

    DATE_DIFF(
      second_purchase_date,
      first_purchase_date,
      DAY
    ) AS days_to_second_purchase

  FROM first_purchases

  WHERE first_purchase_date
    BETWEEN DATE '2020-11-12'
        AND DATE '2020-12-26'
),

customer_30d_value AS (
  SELECT
    c.user_pseudo_id,
    c.first_purchase_period,
    c.first_purchase_date,
    c.second_purchase_date,
    c.days_to_second_purchase,

    COUNT(o.transaction_id)
      AS orders_within_30d,

    ROUND(
      SUM(o.order_revenue),
      2
    ) AS revenue_within_30d

  FROM eligible_customers AS c

  JOIN clean_orders AS o
    ON c.user_pseudo_id = o.user_pseudo_id

   AND o.order_date BETWEEN
       c.first_purchase_date
       AND DATE_ADD(
         c.first_purchase_date,
         INTERVAL 30 DAY
       )

  GROUP BY
    c.user_pseudo_id,
    c.first_purchase_period,
    c.first_purchase_date,
    c.second_purchase_date,
    c.days_to_second_purchase
)

SELECT
  first_purchase_period,

  COUNT(*) AS first_time_purchasers,

  COUNTIF(
    days_to_second_purchase
      BETWEEN 0 AND 7
  ) AS repeat_purchasers_7d,

  COUNTIF(
    days_to_second_purchase
      BETWEEN 0 AND 14
  ) AS repeat_purchasers_14d,

  COUNTIF(
    days_to_second_purchase
      BETWEEN 0 AND 30
  ) AS repeat_purchasers_30d,

  ROUND(
    100 * SAFE_DIVIDE(
      COUNTIF(
        days_to_second_purchase
          BETWEEN 0 AND 7
      ),
      COUNT(*)
    ),
    2
  ) AS repeat_purchase_rate_7d_pct,

  ROUND(
    100 * SAFE_DIVIDE(
      COUNTIF(
        days_to_second_purchase
          BETWEEN 0 AND 14
      ),
      COUNT(*)
    ),
    2
  ) AS repeat_purchase_rate_14d_pct,

  ROUND(
    100 * SAFE_DIVIDE(
      COUNTIF(
        days_to_second_purchase
          BETWEEN 0 AND 30
      ),
      COUNT(*)
    ),
    2
  ) AS repeat_purchase_rate_30d_pct,

  ROUND(
    AVG(
      IF(
        days_to_second_purchase
          BETWEEN 0 AND 30,
        days_to_second_purchase,
        NULL
      )
    ),
    2
  ) AS avg_days_to_second_purchase,

  ROUND(
    AVG(orders_within_30d),
    2
  ) AS avg_orders_per_customer_30d,

  ROUND(
    AVG(revenue_within_30d),
    2
  ) AS avg_revenue_per_customer_30d

FROM customer_30d_value

GROUP BY first_purchase_period

ORDER BY
  CASE first_purchase_period
    WHEN 'Nov 12-30' THEN 1
    WHEN 'Dec 1-26' THEN 2
  END;
