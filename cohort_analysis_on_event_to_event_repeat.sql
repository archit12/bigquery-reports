
#standardSQL
# select users who have done the first_event (first_open in this case)
WITH events as (
  SELECT user_pseudo_id,
    FORMAT_DATE('%Y-%V', DATE(TIMESTAMP_MICROS(CAST(event_timestamp as INT64)))) AS period
  FROM `solid-coral.analytics.events_*` AS events, unnest(event_params) as params
  WHERE 
  events._TABLE_SUFFIX BETWEEN '20190401' AND '20190415'
  AND event_name ='first_open'
  # actual first_opens have `previous_first_open_count` set to 0
  AND params.key='previous_first_open_count' AND params.value.int_value=0 
  GROUP BY user_pseudo_id, period),
# users who did the repeat event
returning_events as (
  SELECT user_pseudo_id,
    FORMAT_DATE('%Y-%V', DATE(TIMESTAMP_MICROS(CAST(event_timestamp as INT64)))) AS period
  FROM `solid-coral.analytics.events_*` AS events
  WHERE 
  events._TABLE_SUFFIX BETWEEN '20190401' AND '20190415'
  AND event_name='sign_up' or event_name = 'login'
  GROUP BY user_pseudo_id, period),
cohorts AS (
  SELECT user_pseudo_id, MIN(period) AS cohort FROM events GROUP BY user_pseudo_id
), 
periods AS (
  SELECT period, ROW_NUMBER() OVER(ORDER BY period) AS num
  FROM (SELECT DISTINCT cohort AS period FROM cohorts)
), 
cohorts_size AS (
  SELECT cohort, periods.num AS num, COUNT(DISTINCT events.user_pseudo_id) AS ids 
  FROM cohorts JOIN events ON events.period = cohorts.cohort AND cohorts.user_pseudo_id = events.user_pseudo_id
  JOIN periods ON periods.period = cohorts.cohort
  GROUP BY cohort, num
), 
# joining first_event users with repeat_event users on users and period to calculate retention
retention AS (
  SELECT cohort, returning_events.period AS period, periods.num AS num, COUNT(DISTINCT cohorts.user_pseudo_id) AS ids
  FROM periods JOIN returning_events ON returning_events.period = periods.period
  JOIN cohorts ON cohorts.user_pseudo_id = returning_events.user_pseudo_id 
  GROUP BY cohort, period, num 
)
SELECT 
  CONCAT(cohorts_size.cohort, ' - ',  FORMAT("%'d", cohorts_size.ids), ' users') AS cohort, 
  retention.num - cohorts_size.num AS period_lag, 
  retention.period as period_label,
  ROUND(retention.ids / cohorts_size.ids * 100, 2) AS retention , retention.ids AS rids
FROM retention
JOIN cohorts_size ON cohorts_size.cohort = retention.cohort
WHERE cohorts_size.cohort >= FORMAT_DATE('%Y-%V', DATE('2019-04-01'))
ORDER BY cohort, period_lag, period_label  
