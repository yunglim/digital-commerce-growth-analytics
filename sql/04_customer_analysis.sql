-- ============================================================
-- 04. CUSTOMER ANALYSIS
-- Digital Commerce Growth Analytics
-- ============================================================

-- ------------------------------------------------------------
-- 1. New vs. Returning Customer Funnel
-- Purpose:
-- Compare funnel performance between new and returning users
-- across the main analysis periods.
-- ------------------------------------------------------------

WITH base_events AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    event_timestamp,
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
    'first_visit',
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

    MAX(IF(event_name = 'session_start', 1, 0))
      AS started_session,

    MAX(IF(event_name = 'first_visit', 1, 0))
      AS first_visit_session,

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

period_users AS (
  SELECT
    CASE
      WHEN session_date BETWEEN DATE '2020-11-12' AND DATE '2020-11-30'
        THEN 'Nov 12-30'

      WHEN session_date BETWEEN DATE '2020-12-01' AND DATE '2020-12-31'
        THEN 'December'

      WHEN session_date BETWEEN DATE '2021-01-01' AND DATE '2021-01-25'
        THEN 'Jan 1-25'
    END AS period,

    CASE
      WHEN first_visit_session = 1
        THEN 'New'
      ELSE 'Returning'
    END AS user_type,

    started_session,
    viewed_item,
    began_checkout,
    purchased

  FROM session_level

  WHERE session_date
    BETWEEN DATE '2020-11-12'
        AND DATE '2021-01-25'
),

user_performance AS (
  SELECT
    period,
    user_type,

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

  FROM period_users

  GROUP BY
    period,
    user_type
),

period_totals AS (
  SELECT
    period,
    SUM(sessions) AS total_sessions

  FROM user_performance

  GROUP BY period
)

SELECT
  u.period,
  u.user_type,

  u.sessions,

  ROUND(
    100 * SAFE_DIVIDE(
      u.sessions,
      t.total_sessions
    ),
    2
  ) AS session_share_pct,

  u.product_view_sessions,
  u.checkout_sessions,
  u.purchase_sessions,

  ROUND(
    100 * SAFE_DIVIDE(
      u.product_view_sessions,
      u.sessions
    ),
    2
  ) AS product_view_rate_pct,

  ROUND(
    100 * SAFE_DIVIDE(
      u.checkout_sessions,
      u.product_view_sessions
    ),
    2
  ) AS view_to_checkout_pct,

  ROUND(
    100 * SAFE_DIVIDE(
      u.purchase_sessions,
      u.checkout_sessions
    ),
    2
  ) AS checkout_to_purchase_pct,

  ROUND(
    100 * SAFE_DIVIDE(
      u.purchase_sessions,
      u.sessions
    ),
    2
  ) AS session_conversion_pct

FROM user_performance AS u

JOIN period_totals AS t
  ON u.period = t.period

ORDER BY
  CASE u.period
    WHEN 'Nov 12-30' THEN 1
    WHEN 'December' THEN 2
    WHEN 'Jan 1-25' THEN 3
  END,
  u.user_type;

-- ------------------------------------------------------------
-- 2. New vs. Returning Conversion Decomposition
-- Purpose:
-- Decompose the conversion-rate change from December to January
-- into differences in New/Returning customer mix versus changes
-- in segment-level conversion behavior.
-- ------------------------------------------------------------

WITH base_events AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
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
    'first_visit',
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

    MAX(IF(event_name = 'session_start', 1, 0))
      AS started_session,

    MAX(IF(event_name = 'first_visit', 1, 0))
      AS first_visit_session,

    MAX(IF(event_name = 'purchase', 1, 0))
      AS purchased

  FROM base_events

  WHERE user_pseudo_id IS NOT NULL
    AND ga_session_id IS NOT NULL

  GROUP BY
    user_pseudo_id,
    ga_session_id
),

classified AS (
  SELECT
    CASE
      WHEN session_date BETWEEN DATE '2020-12-01'
                            AND DATE '2020-12-31'
        THEN 'December'

      WHEN session_date BETWEEN DATE '2021-01-01'
                            AND DATE '2021-01-25'
        THEN 'January'
    END AS period,

    CASE
      WHEN first_visit_session = 1
        THEN 'New'
      ELSE 'Returning'
    END AS user_type,

    started_session,
    purchased

  FROM session_level

  WHERE session_date BETWEEN DATE '2020-12-01'
                         AND DATE '2021-01-25'
),

segment_performance AS (
  SELECT
    period,
    user_type,

    COUNTIF(started_session = 1) AS sessions,

    COUNTIF(
      started_session = 1
      AND purchased = 1
    ) AS purchase_sessions,

    SAFE_DIVIDE(
      COUNTIF(
        started_session = 1
        AND purchased = 1
      ),
      COUNTIF(started_session = 1)
    ) AS conversion_rate

  FROM classified

  GROUP BY
    period,
    user_type
),

period_totals AS (
  SELECT
    period,
    SUM(sessions) AS total_sessions

  FROM segment_performance

  GROUP BY period
),

segment_weights AS (
  SELECT
    s.*,

    SAFE_DIVIDE(
      s.sessions,
      t.total_sessions
    ) AS session_share

  FROM segment_performance AS s

  JOIN period_totals AS t
    USING (period)
),

december AS (
  SELECT *
  FROM segment_weights
  WHERE period = 'December'
),

january AS (
  SELECT *
  FROM segment_weights
  WHERE period = 'January'
),

comparison AS (
  SELECT
    d.user_type,

    d.session_share AS december_share,
    j.session_share AS january_share,

    d.conversion_rate AS december_conversion,
    j.conversion_rate AS january_conversion

  FROM december AS d

  JOIN january AS j
    USING (user_type)
)

SELECT

  -- Actual December conversion
  ROUND(
    100 * SUM(
      december_share * december_conversion
    ),
    3
  ) AS actual_december_conversion_pct,

  -- Actual January conversion
  ROUND(
    100 * SUM(
      january_share * january_conversion
    ),
    3
  ) AS actual_january_conversion_pct,

  -- Keep January behavior,
  -- but restore December's New/Returning mix
  ROUND(
    100 * SUM(
      december_share * january_conversion
    ),
    3
  ) AS jan_conversion_with_december_mix_pct,

  -- Keep January mix,
  -- but restore December's segment conversion rates
  ROUND(
    100 * SUM(
      january_share * december_conversion
    ),
    3
  ) AS jan_conversion_with_december_behavior_pct

FROM comparison;
