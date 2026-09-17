-- Run in the Supabase SQL editor after migrations 009-011 and the reviewed
-- client build have been deployed. Counts opted-in installs whose first
-- recorded event is in the last 7 days. Give cohorts time to finish.
with cohort as (
  select install_id,
         min(occurred_at) as first_open,
         min(app_version) as app_version
  from public.product_events
  group by install_id
  having min(occurred_at) >= now() - interval '7 days'
),
client_steps as (
  select c.install_id, c.app_version, c.first_open,
         bool_or(e.event_name = 'get_started_tapped') as got_started,
         bool_or(e.event_name = 'onboarding_finished') as finished_setup,
         bool_or(e.event_name = 'auth_succeeded') as signed_up,
         bool_or(e.event_name = 'paywall_viewed') as saw_paywall,
         bool_or(e.event_name = 'purchase_tapped') as tapped_purchase,
         bool_or(e.event_name = 'entitlement_granted') as got_access,
         bool_or(e.event_name = 'apps_configured') as configured_apps,
         bool_or(e.event_name = 'sleep_started') as started_sleep,
         (array_agg(e.user_id) filter (where e.user_id is not null))[1] as user_id
  from cohort c
  join public.product_events e on e.install_id = c.install_id
  group by c.install_id, c.app_version, c.first_open
),
paid_users as (
  select user_id, min(occurred_at) as first_payment
  from public.subscription_events
  where event_type in ('INITIAL_PURCHASE', 'RENEWAL')
    and period_type = 'NORMAL'
  group by user_id
)
select app_version,
       count(*) as opted_in_installs,
       count(*) filter (where got_started) as got_started,
       count(*) filter (where finished_setup) as finished_setup,
       count(*) filter (where signed_up) as authenticated,
       count(*) filter (where saw_paywall) as saw_paywall,
       count(*) filter (where tapped_purchase) as tapped_purchase,
       count(*) filter (where got_access) as got_access,
       count(*) filter (where p.user_id is not null) as paid_users,
       count(*) filter (where configured_apps) as configured_apps,
       count(*) filter (where started_sleep) as started_sleep
from client_steps c
left join paid_users p on p.user_id = c.user_id
  and p.first_payment >= c.first_open
group by app_version
order by app_version;

-- To inspect a single opted-in journey, replace the UUID. This contains
-- only stable screen/control names, not answer text or sleep records.
-- select occurred_at, event_name, screen, control
-- from public.product_events
-- where install_id = '00000000-0000-0000-0000-000000000000'
-- order by occurred_at, id;
