-- ============================================================
-- 02. PRODUCT FUNNEL ANALYSIS
-- Digital Commerce Growth Analytics
-- ============================================================

-- ------------------------------------------------------------
-- 1. Device Funnel Performance
-- Purpose:
-- Compare major commerce funnel conversion rates across device
-- categories and analysis periods.
-- ------------------------------------------------------------

WITH base_events AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    event_timestamp,
    event_name,
    user_pseudo_id,
    device.category AS device_category,

    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id

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
    user_pseudo_id,
    ga_session_id,

    MIN(
      IF(
        event_name = 'session_start',
        event_date,
        NULL
      )
    ) AS session_date,

    ARRAY_AGG(
      IF(
        event_name = 'session_start',
        device_category,
        NULL
      )
      IGNORE NULLS
      ORDER BY event_timestamp
      LIMIT 1
    )[SAFE_OFFSET(0)] AS device_category,

    MAX(IF(event_name = 'session_start', 1, 0))
      AS started_session,

    MAX(IF(event_name = 'view_item', 1, 0))
      AS viewed_item,

    MAX(IF(event_name = 'begin_checkout', 1, 0))
      AS began_checkout,

    MAX(IF(event_name = 'purchase', 1, 0))
      AS purchased

  FROM base_events

  WHERE user_pseudo_id IS NOT NULL
    AND ga_session_id IS NOT NULL

  GROUP BY
    user_pseudo_id,
    ga_session_id
),

period_device AS (
  SELECT
    CASE
      WHEN session_date BETWEEN DATE '2020-11-12' AND DATE '2020-11-30'
        THEN 'Nov 12-30'

      WHEN session_date BETWEEN DATE '2020-12-01' AND DATE '2020-12-31'
        THEN 'December'

      WHEN session_date BETWEEN DATE '2021-01-01' AND DATE '2021-01-25'
        THEN 'Jan 1-25'
    END AS period,

    COALESCE(device_category, 'unknown') AS device_category,

    started_session,
    viewed_item,
    began_checkout,
    purchased

  FROM session_level

  WHERE session_date BETWEEN DATE '2020-11-12' AND DATE '2021-01-25'
)

SELECT
  period,
  device_category,

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
  ) AS purchase_sessions,

  ROUND(
    100 * SAFE_DIVIDE(
      COUNTIF(
        started_session = 1
        AND viewed_item = 1
      ),
      COUNTIF(started_session = 1)
    ),
    2
  ) AS product_view_rate_pct,

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
  ) AS session_conversion_pct

FROM period_device

GROUP BY
  period,
  device_category

ORDER BY
  CASE period
    WHEN 'Nov 12-30' THEN 1
    WHEN 'December' THEN 2
    WHEN 'Jan 1-25' THEN 3
  END,
  sessions DESC;
