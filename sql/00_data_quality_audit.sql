-- ============================================================
-- 00. DATA QUALITY AUDIT
-- Digital Commerce Growth Analytics
-- ============================================================

-- ------------------------------------------------------------
-- 1. Event Inventory
-- Purpose:
-- Review the available GA4 event types, total event volume,
-- and distinct users before building downstream analyses.
-- ------------------------------------------------------------

SELECT
  event_name,
  COUNT(*) AS event_count,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
GROUP BY event_name
ORDER BY event_count DESC;

-- ------------------------------------------------------------
-- 2. Session ID Coverage
-- Purpose:
-- Check whether key funnel events contain a valid GA4 session ID
-- and estimate distinct sessions at each funnel stage.
-- ------------------------------------------------------------

WITH funnel_events AS (
  SELECT
    event_name,
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id
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
)

SELECT
  event_name,
  COUNT(*) AS event_count,
  COUNTIF(ga_session_id IS NULL) AS missing_session_id,
  COUNT(
    DISTINCT CONCAT(
      user_pseudo_id,
      '-',
      CAST(ga_session_id AS STRING)
    )
  ) AS sessions
FROM funnel_events
GROUP BY event_name
ORDER BY
  CASE event_name
    WHEN 'session_start' THEN 1
    WHEN 'view_item' THEN 2
    WHEN 'add_to_cart' THEN 3
    WHEN 'begin_checkout' THEN 4
    WHEN 'add_shipping_info' THEN 5
    WHEN 'add_payment_info' THEN 6
    WHEN 'purchase' THEN 7
  END;

-- ------------------------------------------------------------
-- 3. Session Counts by Funnel Event
-- Purpose:
-- Count distinct sessions associated with each major funnel
-- event to establish the baseline session-level funnel volume.
-- ------------------------------------------------------------

WITH funnel_events AS (
  SELECT
    event_name,
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id
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
)

SELECT
  event_name,
  COUNT(
    DISTINCT CONCAT(
      user_pseudo_id,
      '-',
      CAST(ga_session_id AS STRING)
    )
  ) AS sessions
FROM funnel_events
GROUP BY event_name
ORDER BY
  CASE event_name
    WHEN 'session_start' THEN 1
    WHEN 'view_item' THEN 2
    WHEN 'add_to_cart' THEN 3
    WHEN 'begin_checkout' THEN 4
    WHEN 'add_shipping_info' THEN 5
    WHEN 'add_payment_info' THEN 6
    WHEN 'purchase' THEN 7
  END;

-- ------------------------------------------------------------
-- 4. Funnel Event Inventory
-- Purpose:
-- Summarize event volume and distinct users across the major
-- commerce funnel stages before building session-level metrics.
-- ------------------------------------------------------------

SELECT
  event_name,
  COUNT(*) AS event_count,
  COUNT(DISTINCT user_pseudo_id) AS users
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
GROUP BY event_name
ORDER BY
  CASE event_name
    WHEN 'session_start' THEN 1
    WHEN 'view_item' THEN 2
    WHEN 'add_to_cart' THEN 3
    WHEN 'begin_checkout' THEN 4
    WHEN 'add_shipping_info' THEN 5
    WHEN 'add_payment_info' THEN 6
    WHEN 'purchase' THEN 7
  END;

-- ------------------------------------------------------------
-- 5. Purchase Transaction Audit
-- Purpose:
-- Compare purchase-event volume with transaction ID coverage,
-- distinct purchase sessions, and summed purchase revenue.
-- ------------------------------------------------------------

SELECT
  COUNT(*) AS purchase_events,

  COUNTIF(
    ecommerce.transaction_id IS NULL
    OR ecommerce.transaction_id = ''
  ) AS missing_transaction_id,

  COUNT(DISTINCT ecommerce.transaction_id)
    AS unique_transaction_ids,

  COUNT(DISTINCT CONCAT(
    user_pseudo_id,
    '-',
    CAST(
      (
        SELECT value.int_value
        FROM UNNEST(event_params)
        WHERE key = 'ga_session_id'
      ) AS STRING
    )
  )) AS purchase_sessions,

  ROUND(
    SUM(ecommerce.purchase_revenue),
    2
  ) AS summed_purchase_revenue

FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

WHERE event_name = 'purchase';

-- ------------------------------------------------------------
-- 6. Transaction ID Integrity
-- Purpose:
-- Validate whether transaction IDs uniquely represent orders
-- and identify duplicate IDs, cross-user/session reuse, or
-- inconsistent revenue values.
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
    event_timestamp

  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name = 'purchase'
),

transaction_summary AS (
  SELECT
    transaction_id,

    COUNT(*) AS purchase_event_count,

    COUNT(DISTINCT user_pseudo_id)
      AS user_count,

    COUNT(
      DISTINCT CONCAT(
        user_pseudo_id,
        '-',
        CAST(ga_session_id AS STRING)
      )
    ) AS session_count,

    COUNT(DISTINCT purchase_revenue)
      AS revenue_versions,

    MIN(purchase_revenue)
      AS min_revenue,

    MAX(purchase_revenue)
      AS max_revenue

  FROM purchases

  WHERE transaction_id IS NOT NULL
    AND transaction_id != ''

  GROUP BY transaction_id
)

SELECT

  -- Missing transaction IDs
  (
    SELECT COUNTIF(transaction_id IS NULL)
    FROM purchases
  ) AS null_transaction_ids,

  (
    SELECT COUNTIF(transaction_id = '')
    FROM purchases
  ) AS blank_transaction_ids,

  -- Valid transaction IDs
  COUNT(*) AS valid_unique_transactions,

  COUNTIF(purchase_event_count > 1)
    AS duplicated_transaction_ids,

  SUM(purchase_event_count)
    AS purchase_events_with_valid_id,

  MAX(purchase_event_count)
    AS max_events_per_transaction,

  -- Integrity checks
  COUNTIF(user_count > 1)
    AS transaction_ids_multiple_users,

  COUNTIF(session_count > 1)
    AS transaction_ids_multiple_sessions,

  COUNTIF(revenue_versions > 1)
    AS transaction_ids_revenue_mismatch

FROM transaction_summary;

-- ------------------------------------------------------------
-- 7. Repeated Transaction IDs
-- Purpose:
-- Inspect transaction IDs that appear in multiple purchase
-- events and check whether duplicates span users, sessions,
-- or inconsistent revenue values.
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
    event_timestamp

  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name = 'purchase'
)

SELECT
  transaction_id,

  COUNT(*) AS purchase_events,

  COUNT(DISTINCT user_pseudo_id) AS users,

  COUNT(
    DISTINCT CONCAT(
      user_pseudo_id,
      '-',
      CAST(ga_session_id AS STRING)
    )
  ) AS sessions,

  COUNT(DISTINCT purchase_revenue)
    AS revenue_versions,

  MIN(purchase_revenue)
    AS min_revenue,

  MAX(purchase_revenue)
    AS max_revenue

FROM purchases

WHERE transaction_id IS NOT NULL
  AND transaction_id != ''

GROUP BY transaction_id

HAVING COUNT(*) > 1

ORDER BY purchase_events DESC

LIMIT 30;

-- ------------------------------------------------------------
-- 8. Composite Order Grain Audit
-- Purpose:
-- Test whether a composite key of user, session, and transaction
-- ID provides a more reliable order grain and inspect placeholder
-- transaction behavior separately.
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
    event_timestamp

  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name = 'purchase'
),

valid_transactions AS (
  SELECT *
  FROM purchases
  WHERE transaction_id IS NOT NULL
    AND transaction_id != ''
    AND transaction_id != '(not set)'
),

composite_orders AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    transaction_id,

    COUNT(*) AS purchase_events,

    COUNT(DISTINCT purchase_revenue)
      AS revenue_versions,

    MIN(purchase_revenue)
      AS min_revenue,

    MAX(purchase_revenue)
      AS max_revenue

  FROM valid_transactions

  GROUP BY
    user_pseudo_id,
    ga_session_id,
    transaction_id
),

session_orders AS (
  SELECT
    user_pseudo_id,
    ga_session_id,

    COUNT(DISTINCT transaction_id)
      AS transaction_ids_in_session

  FROM valid_transactions

  GROUP BY
    user_pseudo_id,
    ga_session_id
),

placeholder_sessions AS (
  SELECT
    user_pseudo_id,
    ga_session_id,

    COUNT(*) AS purchase_events,

    COUNT(DISTINCT purchase_revenue)
      AS revenue_versions

  FROM purchases

  WHERE transaction_id IS NULL
     OR transaction_id = ''
     OR transaction_id = '(not set)'

  GROUP BY
    user_pseudo_id,
    ga_session_id
)

SELECT

  -- Valid composite transaction keys
  (SELECT COUNT(*)
   FROM composite_orders)
    AS composite_orders,

  (SELECT COUNTIF(purchase_events > 1)
   FROM composite_orders)
    AS repeated_composite_orders,

  (SELECT COUNTIF(revenue_versions > 1)
   FROM composite_orders)
    AS composite_revenue_mismatches,

  (SELECT MAX(purchase_events)
   FROM composite_orders)
    AS max_events_per_composite_order,

  -- Multiple distinct orders within one session
  (SELECT COUNTIF(transaction_ids_in_session > 1)
   FROM session_orders)
    AS sessions_with_multiple_transaction_ids,

  -- Placeholder / missing transaction IDs
  (SELECT COUNT(*)
   FROM placeholder_sessions)
    AS placeholder_purchase_sessions,

  (SELECT COUNTIF(purchase_events > 1)
   FROM placeholder_sessions)
    AS repeated_placeholder_sessions,

  (SELECT COUNTIF(revenue_versions > 1)
   FROM placeholder_sessions)
    AS placeholder_sessions_multiple_revenues

;

-- ------------------------------------------------------------
-- 9. Placeholder Purchase Patterns
-- Purpose:
-- Inspect repeated purchase events where transaction IDs are
-- missing or stored as placeholder values, and review whether
-- those events occur within the same user-session combination.
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

placeholder_purchases AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    purchase_revenue,
    total_item_quantity,
    event_timestamp,

    TIMESTAMP_MICROS(event_timestamp)
      AS purchase_time

  FROM purchases

  WHERE transaction_id IS NULL
     OR transaction_id = ''
     OR transaction_id = '(not set)'
),

repeated_placeholder_sessions AS (
  SELECT
    user_pseudo_id,
    ga_session_id

  FROM placeholder_purchases

  GROUP BY
    user_pseudo_id,
    ga_session_id

  HAVING COUNT(*) > 1
)

SELECT
  p.user_pseudo_id,
  p.ga_session_id,
  p.purchase_time,
  p.purchase_revenue,
  p.total_item_quantity

FROM placeholder_purchases AS p

INNER JOIN repeated_placeholder_sessions AS r
  ON p.user_pseudo_id = r.user_pseudo_id
 AND p.ga_session_id = r.ga_session_id

ORDER BY
  p.user_pseudo_id,
  p.ga_session_id,
  p.event_timestamp;

-- ------------------------------------------------------------
-- 10. Purchase Funnel Completeness
-- Purpose:
-- Audit whether purchase sessions contain the expected commerce
-- funnel steps and whether those steps occur in chronological order.
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

session_steps AS (
  SELECT
    user_pseudo_id,
    ga_session_id,

    MIN(IF(event_name = 'session_start', event_timestamp, NULL))
      AS session_start_ts,

    MIN(IF(event_name = 'view_item', event_timestamp, NULL))
      AS view_item_ts,

    MIN(IF(event_name = 'add_to_cart', event_timestamp, NULL))
      AS add_to_cart_ts,

    MIN(IF(event_name = 'begin_checkout', event_timestamp, NULL))
      AS begin_checkout_ts,

    MIN(IF(event_name = 'add_shipping_info', event_timestamp, NULL))
      AS shipping_ts,

    MIN(IF(event_name = 'add_payment_info', event_timestamp, NULL))
      AS payment_ts,

    MIN(IF(event_name = 'purchase', event_timestamp, NULL))
      AS purchase_ts

  FROM session_events

  WHERE user_pseudo_id IS NOT NULL
    AND ga_session_id IS NOT NULL

  GROUP BY
    user_pseudo_id,
    ga_session_id
),

purchase_audit AS (
  SELECT
    *,

    -- Core funnel steps all recorded
    (
      view_item_ts IS NOT NULL
      AND add_to_cart_ts IS NOT NULL
      AND begin_checkout_ts IS NOT NULL
      AND payment_ts IS NOT NULL
      AND purchase_ts IS NOT NULL
    ) AS has_all_core_steps,

    -- Core funnel steps recorded in expected order
    (
      view_item_ts IS NOT NULL
      AND add_to_cart_ts IS NOT NULL
      AND begin_checkout_ts IS NOT NULL
      AND payment_ts IS NOT NULL
      AND purchase_ts IS NOT NULL
      AND view_item_ts <= add_to_cart_ts
      AND add_to_cart_ts <= begin_checkout_ts
      AND begin_checkout_ts <= payment_ts
      AND payment_ts <= purchase_ts
    ) AS has_ordered_core_funnel

  FROM session_steps

  WHERE purchase_ts IS NOT NULL
)

SELECT
  COUNT(*) AS purchase_sessions,

  COUNTIF(view_item_ts IS NULL) AS missing_view_item,
  COUNTIF(add_to_cart_ts IS NULL) AS missing_add_to_cart,
  COUNTIF(begin_checkout_ts IS NULL) AS missing_checkout,
  COUNTIF(shipping_ts IS NULL) AS missing_shipping,
  COUNTIF(payment_ts IS NULL) AS missing_payment,

  COUNTIF(has_all_core_steps) AS complete_core_funnel,
  COUNTIF(has_ordered_core_funnel) AS complete_ordered_funnel,

  ROUND(
    100 * SAFE_DIVIDE(
      COUNTIF(has_all_core_steps),
      COUNT(*)
    ),
    2
  ) AS complete_core_pct,

  ROUND(
    100 * SAFE_DIVIDE(
      COUNTIF(has_ordered_core_funnel),
      COUNT(*)
    ),
    2
  ) AS ordered_core_pct

FROM purchase_audit;

-- ------------------------------------------------------------
-- 11. Purchase Session Paths
-- Purpose:
-- Inspect the recorded timestamps for major funnel events within
-- purchase sessions to understand whether expected steps appear
-- before the purchase event.
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

session_steps AS (
  SELECT
    user_pseudo_id,
    ga_session_id,

    CONCAT(
      user_pseudo_id,
      '-',
      CAST(ga_session_id AS STRING)
    ) AS session_key,

    MIN(IF(event_name = 'session_start', event_timestamp, NULL))
      AS session_start_ts,

    MIN(IF(event_name = 'view_item', event_timestamp, NULL))
      AS view_item_ts,

    MIN(IF(event_name = 'add_to_cart', event_timestamp, NULL))
      AS add_to_cart_ts,

    MIN(IF(event_name = 'begin_checkout', event_timestamp, NULL))
      AS begin_checkout_ts,

    MIN(IF(event_name = 'add_shipping_info', event_timestamp, NULL))
      AS shipping_ts,

    MIN(IF(event_name = 'add_payment_info', event_timestamp, NULL))
      AS payment_ts,

    MIN(IF(event_name = 'purchase', event_timestamp, NULL))
      AS purchase_ts

  FROM session_events

  WHERE user_pseudo_id IS NOT NULL
    AND ga_session_id IS NOT NULL

  GROUP BY
    user_pseudo_id,
    ga_session_id
)

SELECT
  session_key,

  TIMESTAMP_MICROS(session_start_ts) AS session_start_time,
  TIMESTAMP_MICROS(view_item_ts) AS view_item_time,
  TIMESTAMP_MICROS(add_to_cart_ts) AS add_to_cart_time,
  TIMESTAMP_MICROS(begin_checkout_ts) AS checkout_time,
  TIMESTAMP_MICROS(shipping_ts) AS shipping_time,
  TIMESTAMP_MICROS(payment_ts) AS payment_time,
  TIMESTAMP_MICROS(purchase_ts) AS purchase_time

FROM session_steps

WHERE purchase_ts IS NOT NULL

LIMIT 100;

-- ------------------------------------------------------------
-- 12. Daily Transaction Coverage
-- Purpose:
-- Measure daily purchase-event quality and track how often
-- valid transaction IDs are available over time.
-- ------------------------------------------------------------

WITH purchases AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,

    user_pseudo_id,

    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,

    ecommerce.transaction_id AS transaction_id,
    ecommerce.purchase_revenue AS purchase_revenue

  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name = 'purchase'
),

daily_purchase_quality AS (
  SELECT
    event_date,

    COUNT(*) AS purchase_events,

    COUNT(
      DISTINCT CONCAT(
        user_pseudo_id,
        '-',
        CAST(ga_session_id AS STRING)
      )
    ) AS purchase_sessions,

    COUNTIF(
      transaction_id IS NOT NULL
      AND transaction_id != ''
      AND transaction_id != '(not set)'
    ) AS events_with_valid_transaction_id,

    COUNTIF(
      transaction_id IS NULL
      OR transaction_id = ''
      OR transaction_id = '(not set)'
    ) AS events_with_placeholder_transaction_id,

    COUNT(
      DISTINCT CASE
        WHEN transaction_id IS NOT NULL
          AND transaction_id != ''
          AND transaction_id != '(not set)'
        THEN CONCAT(
          user_pseudo_id,
          '-',
          CAST(ga_session_id AS STRING),
          '-',
          transaction_id
        )
      END
    ) AS clean_orders,

    ROUND(
      100 * SAFE_DIVIDE(
        COUNTIF(
          transaction_id IS NOT NULL
          AND transaction_id != ''
          AND transaction_id != '(not set)'
        ),
        COUNT(*)
      ),
      2
    ) AS valid_transaction_event_pct

  FROM purchases

  WHERE user_pseudo_id IS NOT NULL
    AND ga_session_id IS NOT NULL

  GROUP BY event_date
)

SELECT *
FROM daily_purchase_quality
ORDER BY event_date;

-- ------------------------------------------------------------
-- 13. Transaction Coverage by Period
-- Purpose:
-- Compare transaction ID quality across major instrumentation
-- periods and identify when purchase tracking becomes reliable.
-- ------------------------------------------------------------

WITH purchases AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,

    user_pseudo_id,

    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,

    ecommerce.transaction_id AS transaction_id

  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name = 'purchase'
),

period_summary AS (
  SELECT
    CASE
      WHEN event_date < DATE '2020-11-11'
        THEN 'Pre-instrumentation'
      WHEN event_date = DATE '2020-11-11'
        THEN 'Transition day'
      ELSE 'Stable period'
    END AS period,

    COUNT(*) AS purchase_events,

    COUNTIF(
      transaction_id IS NOT NULL
      AND transaction_id != ''
      AND transaction_id != '(not set)'
    ) AS valid_transaction_events,

    COUNTIF(
      transaction_id IS NULL
      OR transaction_id = ''
      OR transaction_id = '(not set)'
    ) AS placeholder_events

  FROM purchases

  WHERE user_pseudo_id IS NOT NULL
    AND ga_session_id IS NOT NULL

  GROUP BY period
)

SELECT
  period,
  purchase_events,
  valid_transaction_events,
  placeholder_events,

  ROUND(
    100 * SAFE_DIVIDE(
      valid_transaction_events,
      purchase_events
    ),
    2
  ) AS valid_transaction_pct

FROM period_summary

ORDER BY
  CASE period
    WHEN 'Pre-instrumentation' THEN 1
    WHEN 'Transition day' THEN 2
    WHEN 'Stable period' THEN 3
  END;

-- ------------------------------------------------------------
-- 14. January Transaction Coverage
-- Purpose:
-- Examine daily transaction ID quality during January 2021
-- to identify whether tracking reliability deteriorated near
-- the end of the observation period.
-- ------------------------------------------------------------

WITH purchases AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,

    ecommerce.transaction_id AS transaction_id

  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name = 'purchase'
    AND PARSE_DATE('%Y%m%d', event_date)
        BETWEEN DATE '2021-01-01' AND DATE '2021-01-31'
)

SELECT
  event_date,

  COUNT(*) AS purchase_events,

  COUNTIF(
    transaction_id IS NOT NULL
    AND transaction_id != ''
    AND transaction_id != '(not set)'
  ) AS valid_transaction_events,

  COUNTIF(
    transaction_id IS NULL
    OR transaction_id = ''
    OR transaction_id = '(not set)'
  ) AS placeholder_events,

  ROUND(
    100 * SAFE_DIVIDE(
      COUNTIF(
        transaction_id IS NOT NULL
        AND transaction_id != ''
        AND transaction_id != '(not set)'
      ),
      COUNT(*)
    ),
    2
  ) AS valid_transaction_pct

FROM purchases

GROUP BY event_date
ORDER BY event_date;

-- ------------------------------------------------------------
-- 15. Clean Order Quality
-- Purpose:
-- Validate the final clean-order grain and confirm consistency
-- of revenue and item quantity across validated purchase records.
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

order_audit AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    transaction_id,

    COUNT(*) AS purchase_events,

    COUNT(DISTINCT purchase_revenue)
      AS revenue_versions,

    COUNT(DISTINCT total_item_quantity)
      AS quantity_versions,

    COUNTIF(purchase_revenue IS NULL)
      AS null_revenue_events,

    COUNTIF(total_item_quantity IS NULL)
      AS null_quantity_events

  FROM valid_purchases

  GROUP BY
    user_pseudo_id,
    ga_session_id,
    transaction_id
)

SELECT
  COUNT(*) AS orders,

  COUNTIF(revenue_versions > 1)
    AS revenue_mismatch_orders,

  COUNTIF(quantity_versions > 1)
    AS quantity_mismatch_orders,

  COUNTIF(null_revenue_events > 0)
    AS orders_with_null_revenue,

  COUNTIF(null_quantity_events > 0)
    AS orders_with_null_quantity

FROM order_audit;
