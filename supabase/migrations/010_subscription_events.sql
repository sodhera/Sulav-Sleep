-- RevenueCat's authenticated webhook is the source of truth for money events.
-- No client insert or read policies: service role only. Retain event IDs for
-- idempotent retries and keep the ledger separate from client tap analytics.
create table if not exists public.subscription_events (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  event_type text not null,
  period_type text,
  product_id text,
  price numeric,
  currency text,
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  constraint subscription_event_type_short check (length(event_type) between 1 and 40),
  constraint subscription_event_id_short check (length(id) between 1 and 128),
  constraint subscription_event_product_short check (product_id is null or length(product_id) <= 128),
  constraint subscription_event_currency_short check (currency is null or length(currency) = 3)
);

create index if not exists subscription_events_user_time_idx
  on public.subscription_events (user_id, occurred_at desc);
create index if not exists subscription_events_type_time_idx
  on public.subscription_events (event_type, occurred_at desc);

alter table public.subscription_events enable row level security;
revoke all on public.subscription_events from anon, authenticated;
