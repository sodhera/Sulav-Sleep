-- Minimal first-party conversion funnel. No answer text, sleep/health data,
-- app tokens, email addresses, or arbitrary JSON properties are accepted.
-- Run this migration before distributing a build that writes product_events.
create table if not exists public.product_events (
  id uuid primary key,
  install_id uuid not null,
  user_id uuid default auth.uid() references auth.users(id) on delete cascade,
  event_name text not null,
  screen text,
  control text,
  app_version text not null,
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  constraint product_event_name_valid check (event_name in (
    'app_open', 'welcome_viewed', 'get_started_tapped', 'sign_in_tapped',
    'onboarding_step_viewed', 'onboarding_option_tapped', 'onboarding_next_tapped',
    'onboarding_back_tapped', 'onboarding_finished', 'auth_started',
    'auth_succeeded', 'auth_failed', 'auth_cancelled', 'paywall_viewed', 'plans_loaded',
    'plans_failed', 'plan_selected', 'purchase_tapped', 'purchase_cancelled',
    'purchase_failed', 'entitlement_granted', 'paywall_closed',
    'screen_time_primer_viewed', 'screen_time_permission_result',
    'app_picker_opened', 'app_picker_closed', 'apps_configured',
    'sleep_started', 'sleep_completed'
  )),
  constraint product_event_screen_short check (screen is null or length(screen) <= 48),
  constraint product_event_control_short check (control is null or length(control) <= 48),
  constraint product_event_version_short check (length(app_version) between 1 and 32),
  constraint product_event_time_valid check (occurred_at <= now() + interval '5 minutes')
);

create index if not exists product_events_funnel_idx
  on public.product_events (received_at desc, event_name);
create index if not exists product_events_install_idx
  on public.product_events (install_id, occurred_at);

alter table public.product_events enable row level security;
revoke all on public.product_events from anon, authenticated;
grant insert on public.product_events to anon, authenticated;

-- The server supplies user_id from the verified JWT. A caller cannot attach
-- events to a different account. Anonymous events retain install_id so the
-- same install can be joined after sign-up without collecting identity data.
create policy "Clients insert own funnel events"
  on public.product_events for insert to anon, authenticated
  with check (user_id is not distinct from auth.uid());
