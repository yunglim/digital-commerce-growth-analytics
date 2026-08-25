-- ============================================================
-- 05. PRODUCT CATEGORY ANALYSIS
-- Digital Commerce Growth Analytics
-- ============================================================

-- ------------------------------------------------------------
-- 1. Product Category Inventory
-- Purpose:
-- Review product-category coverage across item-view events and
-- quantify users and sessions associated with each category.
-- ------------------------------------------------------------

SELECT
  COALESCE(NULLIF(item.item_category, ''), '(not set)')
    AS item_category,

  COUNT(*) AS item_event_records,

  COUNT(DISTINCT user_pseudo_id)
    AS users,

  COUNT(
    DISTINCT CONCAT(
      user_pseudo_id,
      '-',
      CAST(
        (
          SELECT value.int_value
          FROM UNNEST(event_params)
          WHERE key = 'ga_session_id'
        ) AS STRING
      )
    )
  ) AS sessions

FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

CROSS JOIN UNNEST(items) AS item

WHERE event_name = 'view_item'

GROUP BY item_category

ORDER BY item_event_records DESC;

-- ------------------------------------------------------------
-- 2. Product Mix vs. Behavior Decomposition
-- Purpose:
-- Decompose the change in view-to-checkout performance between
-- December and January into changes in product mix versus changes
-- in product-family conversion behavior.
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
    ) AS ga_session_id,

    CASE
      WHEN event_name = 'view_item' THEN (
        SELECT ANY_VALUE(item.item_category)
        FROM UNNEST(items) AS item
      )
      ELSE NULL
    END AS raw_item_category

  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name IN (
    'session_start',
    'view_item',
    'begin_checkout'
  )
),

normalized_events AS (
  SELECT
    *,

    CASE
      WHEN raw_item_category IS NULL
        OR TRIM(raw_item_category) = ''
        OR LOWER(raw_item_category) = '(not set)'
        THEN '(not set)'

      WHEN REGEXP_CONTAINS(
        LOWER(raw_item_category),
        r"apparel|men's|women's|kids|t-shirts"
      )
        THEN 'Apparel'

      WHEN REGEXP_CONTAINS(
        LOWER(raw_item_category),
        r'drinkware|mugs|tumblers|water bottles'
      )
        THEN 'Drinkware'

      WHEN REGEXP_CONTAINS(
        LOWER(raw_item_category),
        r'bags|backpacks'
      )
        THEN 'Bags'

      WHEN REGEXP_CONTAINS(
        LOWER(raw_item_category),
        r'stationery|notebooks|writing'
      )
        THEN 'Stationery'

      WHEN REGEXP_CONTAINS(
        LOWER(raw_item_category),
        r'eco-friendly'
      )
        THEN 'Eco-Friendly'

      WHEN REGEXP_CONTAINS(
        LOWER(raw_item_category),
        r'shop by brand|google|android|youtube'
      )
        THEN 'Shop by Brand'

      WHEN REGEXP_CONTAINS(
        LOWER(raw_item_category),
        r'sale'
      )
        THEN 'Sale'

      WHEN REGEXP_CONTAINS(
        LOWER(raw_item_category),
        r'new'
      )
        THEN 'New'

      WHEN REGEXP_CONTAINS(
        LOWER(raw_item_category),
        r'campus collection'
      )
        THEN 'Campus Collection'

      WHEN REGEXP_CONTAINS(
        LOWER(raw_item_category),
        r'lifestyle|small goods|accessories'
      )
        THEN 'Lifestyle & Accessories'

      ELSE 'Other'
    END AS product_family

  FROM base_events
),

session_level AS (
  SELECT
    user_pseudo_id,
    ga_session_id,

    MIN(
      IF(event_name = 'session_start', event_date, NULL)
    ) AS session_date,

    ARRAY_AGG(
      IF(event_name = 'view_item', product_family, NULL)
      IGNORE NULLS
      ORDER BY event_timestamp
      LIMIT 1
    )[SAFE_OFFSET(0)] AS product_family,

    MAX(IF(event_name = 'session_start', 1, 0))
      AS started_session,

    MAX(IF(event_name = 'begin_checkout', 1, 0))
      AS began_checkout

  FROM normalized_events

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

    product_family,
    began_checkout

  FROM session_level

  WHERE started_session = 1
    AND product_family IS NOT NULL
    AND session_date BETWEEN DATE '2020-12-01'
                         AND DATE '2021-01-25'
),

scoped AS (
  SELECT
    'All product families' AS scope,
    *
  FROM classified

  UNION ALL

  SELECT
    'Known categories only' AS scope,
    *
  FROM classified
  WHERE product_family != '(not set)'
),

family_performance AS (
  SELECT
    scope,
    period,
    product_family,

    COUNT(*) AS product_view_sessions,
    COUNTIF(began_checkout = 1) AS checkout_sessions,

    SAFE_DIVIDE(
      COUNTIF(began_checkout = 1),
      COUNT(*)
    ) AS view_to_checkout_rate

  FROM scoped

  GROUP BY
    scope,
    period,
    product_family
),

period_totals AS (
  SELECT
    scope,
    period,
    SUM(product_view_sessions) AS total_product_view_sessions

  FROM family_performance

  GROUP BY
    scope,
    period
),

weighted AS (
  SELECT
    f.*,

    SAFE_DIVIDE(
      f.product_view_sessions,
      t.total_product_view_sessions
    ) AS product_mix_share

  FROM family_performance AS f

  JOIN period_totals AS t
    USING (scope, period)
),

december AS (
  SELECT *
  FROM weighted
  WHERE period = 'December'
),

january AS (
  SELECT *
  FROM weighted
  WHERE period = 'January'
),

comparison AS (
  SELECT
    d.scope,
    d.product_family,

    d.product_mix_share AS december_share,
    j.product_mix_share AS january_share,

    d.view_to_checkout_rate AS december_rate,
    j.view_to_checkout_rate AS january_rate

  FROM december AS d

  JOIN january AS j
    USING (scope, product_family)
)

SELECT
  scope,

  ROUND(
    100 * SUM(
      december_share * december_rate
    ),
    3
  ) AS actual_december_view_to_checkout_pct,

  ROUND(
    100 * SUM(
      january_share * january_rate
    ),
    3
  ) AS actual_january_view_to_checkout_pct,

  -- January behavior + December product mix
  ROUND(
    100 * SUM(
      december_share * january_rate
    ),
    3
  ) AS jan_rate_with_december_product_mix_pct,

  -- January product mix + December product-family behavior
  ROUND(
    100 * SUM(
      january_share * december_rate
    ),
    3
  ) AS jan_rate_with_december_family_behavior_pct

FROM comparison

GROUP BY scope

ORDER BY scope;

-- ------------------------------------------------------------
-- 3. Product Family Funnel
-- Purpose:
-- Compare product-family traffic share and downstream funnel
-- performance from product view through checkout and purchase.
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
    ) AS ga_session_id,

    CASE
      WHEN event_name = 'view_item' THEN (
        SELECT ANY_VALUE(item.item_category)
        FROM UNNEST(items) AS item
      )
      ELSE NULL
    END AS raw_item_category

  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name IN (
    'session_start',
    'view_item',
    'begin_checkout',
    'purchase'
  )
),

normalized_events AS (
  SELECT
    *,

    CASE
      WHEN raw_item_category IS NULL
        OR TRIM(raw_item_category) = ''
        OR LOWER(raw_item_category) = '(not set)'
        THEN '(not set)'

      WHEN REGEXP_CONTAINS(
        LOWER(raw_item_category),
        r"apparel|men''s|women''s|kids|t-shirts"
      )
        THEN 'Apparel'

      WHEN REGEXP_CONTAINS(
        LOWER(raw_item_category),
        r'drinkware|mugs|tumblers|water bottles'
      )
        THEN 'Drinkware'

      WHEN REGEXP_CONTAINS(
        LOWER(raw_item_category),
        r'bags|backpacks'
      )
        THEN 'Bags'

      WHEN REGEXP_CONTAINS(
        LOWER(raw_item_category),
        r'stationery|notebooks|writing'
      )
        THEN 'Stationery'

      WHEN REGEXP_CONTAINS(
        LOWER(raw_item_category),
        r'eco-friendly'
      )
        THEN 'Eco-Friendly'

      WHEN REGEXP_CONTAINS(
        LOWER(raw_item_category),
        r'shop by brand|google|android|youtube'
      )
        THEN 'Shop by Brand'

      WHEN REGEXP_CONTAINS(
        LOWER(raw_item_category),
        r'sale'
      )
        THEN 'Sale'

      WHEN REGEXP_CONTAINS(
        LOWER(raw_item_category),
        r'new'
      )
        THEN 'New'

      WHEN REGEXP_CONTAINS(
        LOWER(raw_item_category),
        r'campus collection'
      )
        THEN 'Campus Collection'

      WHEN REGEXP_CONTAINS(
        LOWER(raw_item_category),
        r'lifestyle|small goods|accessories'
      )
        THEN 'Lifestyle & Accessories'

      ELSE 'Other'
    END AS product_family

  FROM base_events
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
        event_name = 'view_item',
        product_family,
        NULL
      )
      IGNORE NULLS
      ORDER BY event_timestamp
      LIMIT 1
    )[SAFE_OFFSET(0)] AS first_view_product_family,

    MAX(IF(event_name = 'session_start', 1, 0))
      AS started_session,

    MAX(IF(event_name = 'view_item', 1, 0))
      AS viewed_item,

    MAX(IF(event_name = 'begin_checkout', 1, 0))
      AS began_checkout,

    MAX(IF(event_name = 'purchase', 1, 0))
      AS purchased

  FROM normalized_events

  WHERE user_pseudo_id IS NOT NULL
    AND ga_session_id IS NOT NULL

  GROUP BY
    user_pseudo_id,
    ga_session_id
),

period_category AS (
  SELECT
    CASE
      WHEN session_date BETWEEN DATE '2020-11-12'
                            AND DATE '2020-11-30'
        THEN 'Nov 12-30'

      WHEN session_date BETWEEN DATE '2020-12-01'
                            AND DATE '2020-12-31'
        THEN 'December'

      WHEN session_date BETWEEN DATE '2021-01-01'
                            AND DATE '2021-01-25'
        THEN 'Jan 1-25'
    END AS period,

    first_view_product_family AS product_family,

    began_checkout,
    purchased

  FROM session_level

  WHERE session_date BETWEEN DATE '2020-11-12'
                         AND DATE '2021-01-25'

    AND started_session = 1
    AND first_view_product_family IS NOT NULL
),

category_performance AS (
  SELECT
    period,
    product_family,

    COUNT(*) AS product_view_sessions,

    COUNTIF(began_checkout = 1)
      AS checkout_sessions,

    COUNTIF(purchased = 1)
      AS purchase_sessions

  FROM period_category

  GROUP BY
    period,
    product_family
),

period_totals AS (
  SELECT
    period,
    SUM(product_view_sessions) AS all_product_view_sessions

  FROM category_performance

  GROUP BY period
)

SELECT
  c.period,
  c.product_family,

  c.product_view_sessions,

  ROUND(
    100 * SAFE_DIVIDE(
      c.product_view_sessions,
      t.all_product_view_sessions
    ),
    2
  ) AS product_view_share_pct,

  c.checkout_sessions,
  c.purchase_sessions,

  ROUND(
    100 * SAFE_DIVIDE(
      c.checkout_sessions,
      c.product_view_sessions
    ),
    2
  ) AS view_to_checkout_pct,

  ROUND(
    100 * SAFE_DIVIDE(
      c.purchase_sessions,
      c.checkout_sessions
    ),
    2
  ) AS checkout_to_purchase_pct,

  ROUND(
    100 * SAFE_DIVIDE(
      c.purchase_sessions,
      c.product_view_sessions
    ),
    2
  ) AS product_view_to_purchase_pct

FROM category_performance AS c

JOIN period_totals AS t
  USING (period)

WHERE c.product_view_sessions >= 100

ORDER BY
  CASE c.period
    WHEN 'Nov 12-30' THEN 1
    WHEN 'December' THEN 2
    WHEN 'Jan 1-25' THEN 3
  END,
  c.product_view_sessions DESC;
