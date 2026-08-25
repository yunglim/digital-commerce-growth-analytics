-- ============================================================
-- 03. MARKETING CHANNEL ANALYSIS
-- Digital Commerce Growth Analytics
-- ============================================================

-- ------------------------------------------------------------
-- 1. Acquisition Funnel Performance
-- Purpose:
-- Compare session volume, traffic share, and funnel conversion
-- performance across first-touch acquisition source and medium.
-- ------------------------------------------------------------

WITH base_events AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    event_timestamp,
    event_name,
    user_pseudo_id,

    traffic_source.source AS first_source,
    traffic_source.medium AS first_medium,

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
        first_source,
        NULL
      )
      IGNORE NULLS
      ORDER BY event_timestamp
      LIMIT 1
    )[SAFE_OFFSET(0)] AS first_source,

    ARRAY_AGG(
      IF(
        event_name = 'session_start',
        first_medium,
        NULL
      )
      IGNORE NULLS
      ORDER BY event_timestamp
      LIMIT 1
    )[SAFE_OFFSET(0)] AS first_medium,

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

period_source AS (
  SELECT
    CASE
      WHEN session_date BETWEEN DATE '2020-11-12' AND DATE '2020-11-30'
        THEN 'Nov 12-30'

      WHEN session_date BETWEEN DATE '2020-12-01' AND DATE '2020-12-31'
        THEN 'December'

      WHEN session_date BETWEEN DATE '2021-01-01' AND DATE '2021-01-25'
        THEN 'Jan 1-25'
    END AS period,

    COALESCE(first_source, '(unknown)')
      AS first_source,

    COALESCE(first_medium, '(unknown)')
      AS first_medium,

    started_session,
    viewed_item,
    began_checkout,
    purchased

  FROM session_level

  WHERE session_date
    BETWEEN DATE '2020-11-12'
        AND DATE '2021-01-25'
),

source_performance AS (
  SELECT
    period,
    first_source,
    first_medium,

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

  FROM period_source

  GROUP BY
    period,
    first_source,
    first_medium
),

period_totals AS (
  SELECT
    period,
    SUM(sessions) AS total_sessions

  FROM source_performance

  GROUP BY period
)

SELECT
  s.period,
  s.first_source,
  s.first_medium,

  s.sessions,

  ROUND(
    100 * SAFE_DIVIDE(
      s.sessions,
      t.total_sessions
    ),
    2
  ) AS session_share_pct,

  s.product_view_sessions,
  s.checkout_sessions,
  s.purchase_sessions,

  ROUND(
    100 * SAFE_DIVIDE(
      s.product_view_sessions,
      s.sessions
    ),
    2
  ) AS product_view_rate_pct,

  ROUND(
    100 * SAFE_DIVIDE(
      s.checkout_sessions,
      s.product_view_sessions
    ),
    2
  ) AS view_to_checkout_pct,

  ROUND(
    100 * SAFE_DIVIDE(
      s.purchase_sessions,
      s.checkout_sessions
    ),
    2
  ) AS checkout_to_purchase_pct,

  ROUND(
    100 * SAFE_DIVIDE(
      s.purchase_sessions,
      s.sessions
    ),
    2
  ) AS session_conversion_pct

FROM source_performance AS s

JOIN period_totals AS t
  ON s.period = t.period

WHERE s.sessions >= 100

ORDER BY
  CASE s.period
    WHEN 'Nov 12-30' THEN 1
    WHEN 'December' THEN 2
    WHEN 'Jan 1-25' THEN 3
  END,
  s.sessions DESC;

-- ------------------------------------------------------------
-- 2. Acquisition Mix
-- Purpose:
-- Summarize traffic volume and user counts by first-touch
-- acquisition source and medium across the analysis periods.
-- ------------------------------------------------------------

WITH session_starts AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS session_date,
    user_pseudo_id,

    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,

    COALESCE(traffic_source.source, '(unknown)')
      AS first_source,

    COALESCE(traffic_source.medium, '(unknown)')
      AS first_medium

  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name = 'session_start'
),

period_sessions AS (
  SELECT
    CASE
      WHEN session_date BETWEEN DATE '2020-11-12' AND DATE '2020-11-30'
        THEN 'Nov 12-30'

      WHEN session_date BETWEEN DATE '2020-12-01' AND DATE '2020-12-31'
        THEN 'December'

      WHEN session_date BETWEEN DATE '2021-01-01' AND DATE '2021-01-25'
        THEN 'Jan 1-25'
    END AS period,

    first_source,
    first_medium,
    user_pseudo_id,
    ga_session_id

  FROM session_starts

  WHERE session_date BETWEEN DATE '2020-11-12' AND DATE '2021-01-25'
),

source_summary AS (
  SELECT
    period,
    first_source,
    first_medium,

    COUNT(*) AS sessions,
    COUNT(DISTINCT user_pseudo_id) AS users

  FROM period_sessions

  GROUP BY
    period,
    first_source,
    first_medium
),

period_totals AS (
  SELECT
    period,
    SUM(sessions) AS total_sessions

  FROM source_summary

  GROUP BY period
)

SELECT
  s.period,
  s.first_source,
  s.first_medium,
  s.sessions,
  s.users,

  ROUND(
    100 * SAFE_DIVIDE(
      s.sessions,
      t.total_sessions
    ),
    2
  ) AS session_share_pct

FROM source_summary AS s

JOIN period_totals AS t
  ON s.period = t.period

ORDER BY
  CASE s.period
    WHEN 'Nov 12-30' THEN 1
    WHEN 'December' THEN 2
    WHEN 'Jan 1-25' THEN 3
  END,
  s.sessions DESC;
