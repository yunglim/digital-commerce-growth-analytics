-- ============================================================
-- 06. LIFECYCLE & RETENTION ANALYSIS
-- Digital Commerce Growth Analytics
-- ============================================================

-- ------------------------------------------------------------
-- 1. Weekly Retention - Long Format
-- Purpose:
-- Build acquisition cohorts based on each user's first visit
-- and measure weekly retention for up to 8 weeks after acquisition.
-- ------------------------------------------------------------

WITH user_activity AS (
  SELECT
    user_pseudo_id,
    PARSE_DATE('%Y%m%d', event_date) AS activity_date,

    MAX(
      IF(event_name = 'first_visit', 1, 0)
    ) AS had_first_visit,

    MAX(
      IF(event_name = 'session_start', 1, 0)
    ) AS had_session

  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name IN (
    'first_visit',
    'session_start'
  )

    AND user_pseudo_id IS NOT NULL

  GROUP BY
    user_pseudo_id,
    activity_date
),

user_first_visit AS (
  SELECT
    user_pseudo_id,

    MIN(
      IF(
        had_first_visit = 1,
        activity_date,
        NULL
      )
    ) AS first_visit_date

  FROM user_activity

  GROUP BY user_pseudo_id
),

cohort_users AS (
  SELECT
    user_pseudo_id,
    first_visit_date,

    DATE_TRUNC(
      first_visit_date,
      WEEK(MONDAY)
    ) AS cohort_week

  FROM user_first_visit

  WHERE first_visit_date IS NOT NULL
),

activity_after_acquisition AS (
  SELECT
    c.user_pseudo_id,
    c.cohort_week,

    DATE_TRUNC(
      a.activity_date,
      WEEK(MONDAY)
    ) AS activity_week

  FROM cohort_users AS c

  JOIN user_activity AS a
    ON c.user_pseudo_id = a.user_pseudo_id

  WHERE a.had_session = 1
    AND a.activity_date >= c.first_visit_date
),

cohort_activity AS (
  SELECT
    user_pseudo_id,
    cohort_week,

    DATE_DIFF(
      activity_week,
      cohort_week,
      WEEK
    ) AS weeks_since_acquisition

  FROM activity_after_acquisition

  WHERE DATE_DIFF(
    activity_week,
    cohort_week,
    WEEK
  ) >= 0

  GROUP BY
    user_pseudo_id,
    cohort_week,
    weeks_since_acquisition
),

cohort_sizes AS (
  SELECT
    cohort_week,

    COUNT(DISTINCT user_pseudo_id)
      AS cohort_size

  FROM cohort_users

  GROUP BY cohort_week
),

retention AS (
  SELECT
    cohort_week,
    weeks_since_acquisition,

    COUNT(DISTINCT user_pseudo_id)
      AS retained_users

  FROM cohort_activity

  GROUP BY
    cohort_week,
    weeks_since_acquisition
)

SELECT
  r.cohort_week,

  c.cohort_size,

  r.weeks_since_acquisition,

  r.retained_users,

  ROUND(
    100 * SAFE_DIVIDE(
      r.retained_users,
      c.cohort_size
    ),
    2
  ) AS retention_rate_pct

FROM retention AS r

JOIN cohort_sizes AS c
  USING (cohort_week)

WHERE r.weeks_since_acquisition <= 8

ORDER BY
  r.cohort_week,
  r.weeks_since_acquisition;

-- ------------------------------------------------------------
-- 2. Weekly Retention Matrix
-- Purpose:
-- Convert weekly cohort retention into a matrix format and
-- preserve NULL values for future weeks that are not yet observable.
-- ------------------------------------------------------------

WITH user_activity AS (
  SELECT
    user_pseudo_id,
    PARSE_DATE('%Y%m%d', event_date) AS activity_date,

    MAX(IF(event_name = 'first_visit', 1, 0))
      AS had_first_visit,

    MAX(IF(event_name = 'session_start', 1, 0))
      AS had_session

  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name IN (
    'first_visit',
    'session_start'
  )
    AND user_pseudo_id IS NOT NULL

  GROUP BY
    user_pseudo_id,
    activity_date
),

dataset_end AS (
  SELECT
    MAX(activity_date) AS max_activity_date
  FROM user_activity
),

user_first_visit AS (
  SELECT
    user_pseudo_id,

    MIN(
      IF(
        had_first_visit = 1,
        activity_date,
        NULL
      )
    ) AS first_visit_date

  FROM user_activity

  GROUP BY user_pseudo_id
),

cohort_users AS (
  SELECT
    user_pseudo_id,

    DATE_TRUNC(
      first_visit_date,
      WEEK(MONDAY)
    ) AS cohort_week

  FROM user_first_visit

  WHERE first_visit_date IS NOT NULL

    -- Exclude the partial first cohort
    AND DATE_TRUNC(
      first_visit_date,
      WEEK(MONDAY)
    ) > DATE '2020-10-26'
),

cohort_sizes AS (
  SELECT
    cohort_week,

    COUNT(DISTINCT user_pseudo_id)
      AS cohort_size

  FROM cohort_users

  GROUP BY cohort_week
),

activity_by_week AS (
  SELECT DISTINCT
    c.user_pseudo_id,
    c.cohort_week,

    DATE_DIFF(
      DATE_TRUNC(
        a.activity_date,
        WEEK(MONDAY)
      ),
      c.cohort_week,
      WEEK
    ) AS weeks_since_acquisition

  FROM cohort_users AS c

  JOIN user_activity AS a
    ON c.user_pseudo_id = a.user_pseudo_id

  WHERE a.had_session = 1
    AND a.activity_date >= c.cohort_week
),

retained AS (
  SELECT
    cohort_week,
    weeks_since_acquisition,

    COUNT(DISTINCT user_pseudo_id)
      AS retained_users

  FROM activity_by_week

  WHERE weeks_since_acquisition
    BETWEEN 0 AND 8

  GROUP BY
    cohort_week,
    weeks_since_acquisition
),

cohort_week_grid AS (
  SELECT
    c.cohort_week,
    c.cohort_size,
    week_number,

    DATE_ADD(
      c.cohort_week,
      INTERVAL week_number WEEK
    ) AS retention_week_start,

    d.max_activity_date

  FROM cohort_sizes AS c

  CROSS JOIN UNNEST(
    GENERATE_ARRAY(0, 8)
  ) AS week_number

  CROSS JOIN dataset_end AS d
),

retention_rates AS (
  SELECT
    g.cohort_week,
    g.cohort_size,
    g.week_number,

    CASE
      -- Do not treat unobservable future weeks as zero retention
      WHEN g.retention_week_start
           > g.max_activity_date
        THEN NULL

      ELSE ROUND(
        100 * SAFE_DIVIDE(
          COALESCE(r.retained_users, 0),
          g.cohort_size
        ),
        2
      )
    END AS retention_rate_pct

  FROM cohort_week_grid AS g

  LEFT JOIN retained AS r
    ON g.cohort_week = r.cohort_week
   AND g.week_number = r.weeks_since_acquisition
)

SELECT
  cohort_week,
  cohort_size,

  MAX(IF(week_number = 0, retention_rate_pct, NULL))
    AS week_0,

  MAX(IF(week_number = 1, retention_rate_pct, NULL))
    AS week_1,

  MAX(IF(week_number = 2, retention_rate_pct, NULL))
    AS week_2,

  MAX(IF(week_number = 3, retention_rate_pct, NULL))
    AS week_3,

  MAX(IF(week_number = 4, retention_rate_pct, NULL))
    AS week_4,

  MAX(IF(week_number = 5, retention_rate_pct, NULL))
    AS week_5,

  MAX(IF(week_number = 6, retention_rate_pct, NULL))
    AS week_6,

  MAX(IF(week_number = 7, retention_rate_pct, NULL))
    AS week_7,

  MAX(IF(week_number = 8, retention_rate_pct, NULL))
    AS week_8

FROM retention_rates

GROUP BY
  cohort_week,
  cohort_size

ORDER BY cohort_week;

-- ------------------------------------------------------------
-- 3. Monthly Weighted Retention Summary
-- Purpose:
-- Summarize cohort retention at Weeks 1, 2, and 4 using
-- cohort-size-weighted retention rates while excluding periods
-- that are not yet observable in the dataset.
-- ------------------------------------------------------------

WITH user_activity AS (
  SELECT
    user_pseudo_id,
    PARSE_DATE('%Y%m%d', event_date) AS activity_date,

    MAX(IF(event_name = 'first_visit', 1, 0))
      AS had_first_visit,

    MAX(IF(event_name = 'session_start', 1, 0))
      AS had_session

  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE event_name IN (
    'first_visit',
    'session_start'
  )
    AND user_pseudo_id IS NOT NULL

  GROUP BY
    user_pseudo_id,
    activity_date
),

dataset_end AS (
  SELECT
    MAX(activity_date) AS max_activity_date
  FROM user_activity
),

user_first_visit AS (
  SELECT
    user_pseudo_id,

    MIN(
      IF(
        had_first_visit = 1,
        activity_date,
        NULL
      )
    ) AS first_visit_date

  FROM user_activity

  GROUP BY user_pseudo_id
),

cohort_users AS (
  SELECT
    user_pseudo_id,
    first_visit_date,

    DATE_TRUNC(
      first_visit_date,
      WEEK(MONDAY)
    ) AS cohort_week

  FROM user_first_visit

  WHERE first_visit_date IS NOT NULL

    AND DATE_TRUNC(
      first_visit_date,
      WEEK(MONDAY)
    ) > DATE '2020-10-26'
),

cohort_sizes AS (
  SELECT
    cohort_week,

    COUNT(DISTINCT user_pseudo_id)
      AS cohort_size

  FROM cohort_users

  GROUP BY cohort_week
),

weekly_activity AS (
  SELECT DISTINCT
    c.user_pseudo_id,
    c.cohort_week,

    DATE_DIFF(
      DATE_TRUNC(
        a.activity_date,
        WEEK(MONDAY)
      ),
      c.cohort_week,
      WEEK
    ) AS weeks_since_acquisition

  FROM cohort_users AS c

  JOIN user_activity AS a
    ON c.user_pseudo_id = a.user_pseudo_id

  WHERE a.had_session = 1
    AND a.activity_date >= c.first_visit_date
),

retained AS (
  SELECT
    cohort_week,
    weeks_since_acquisition,

    COUNT(DISTINCT user_pseudo_id)
      AS retained_users

  FROM weekly_activity

  WHERE weeks_since_acquisition IN (1, 2, 4)

  GROUP BY
    cohort_week,
    weeks_since_acquisition
),

cohort_retention AS (
  SELECT
    c.cohort_week,
    c.cohort_size,

    FORMAT_DATE(
      '%Y-%m',
      c.cohort_week
    ) AS cohort_month,

    d.max_activity_date,

    SAFE_DIVIDE(
      MAX(IF(r.weeks_since_acquisition = 1,
             r.retained_users,
             NULL)),
      c.cohort_size
    ) AS week_1_rate,

    SAFE_DIVIDE(
      MAX(IF(r.weeks_since_acquisition = 2,
             r.retained_users,
             NULL)),
      c.cohort_size
    ) AS week_2_rate,

    SAFE_DIVIDE(
      MAX(IF(r.weeks_since_acquisition = 4,
             r.retained_users,
             NULL)),
      c.cohort_size
    ) AS week_4_rate

  FROM cohort_sizes AS c

  CROSS JOIN dataset_end AS d

  LEFT JOIN retained AS r
    USING (cohort_week)

  GROUP BY
    c.cohort_week,
    c.cohort_size,
    d.max_activity_date
),

eligibility AS (
  SELECT
    *,

    DATE_ADD(
      cohort_week,
      INTERVAL 1 WEEK
    ) <= max_activity_date AS eligible_week_1,

    DATE_ADD(
      cohort_week,
      INTERVAL 2 WEEK
    ) <= max_activity_date AS eligible_week_2,

    DATE_ADD(
      cohort_week,
      INTERVAL 4 WEEK
    ) <= max_activity_date AS eligible_week_4

  FROM cohort_retention
)

SELECT
  cohort_month,

  SUM(cohort_size) AS acquired_users,

  COUNTIF(eligible_week_1)
    AS cohorts_observed_for_week_1,

  ROUND(
    100 * SAFE_DIVIDE(
      SUM(
        IF(
          eligible_week_1,
          cohort_size * COALESCE(week_1_rate, 0),
          0
        )
      ),
      SUM(
        IF(
          eligible_week_1,
          cohort_size,
          0
        )
      )
    ),
    2
  ) AS weighted_week_1_retention_pct,

  ROUND(
    100 * SAFE_DIVIDE(
      SUM(
        IF(
          eligible_week_2,
          cohort_size * COALESCE(week_2_rate, 0),
          0
        )
      ),
      SUM(
        IF(
          eligible_week_2,
          cohort_size,
          0
        )
      )
    ),
    2
  ) AS weighted_week_2_retention_pct,

  ROUND(
    100 * SAFE_DIVIDE(
      SUM(
        IF(
          eligible_week_4,
          cohort_size * COALESCE(week_4_rate, 0),
          0
        )
      ),
      SUM(
        IF(
          eligible_week_4,
          cohort_size,
          0
        )
      )
    ),
    2
  ) AS weighted_week_4_retention_pct

FROM eligibility

GROUP BY cohort_month

ORDER BY cohort_month;
