-- SleepBlock cloud sync tables
-- Run this in your Supabase SQL Editor or via `supabase db push`.
--
-- Two tables, both owned by the user via auth.uid(), with RLS enabled.
-- The delete-account edge function already deletes auth.users rows;
-- ON DELETE CASCADE propagates to both tables automatically.

-- ============================================================
-- profiles: one row per user
-- Replaces the auth user_metadata `sleep_profile` key with a
-- proper queryable table. Holds the portable slice of the
-- user's profile (schedule, onboarding answers). Device-bound
-- settings (Health sync, Screen Time lockdown) stay local.
-- ============================================================

create table if not exists public.profiles (
  id               uuid primary key references auth.users(id) on delete cascade,
  name             text not null default '',
  bedtime          int not null default 1380,   -- minutes from midnight (23:00)
  wake_time        int not null default 420,    -- minutes from midnight (07:00)
  onboarded        bool not null default false,
  struggles        text[] not null default '{}',
  time_sinks       text[] not null default '{}',
  goal             text not null default '',
  late_night_phone text not null default '',
  wake_feeling     text not null default '',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Users manage own profile"
  on public.profiles for all
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- ============================================================
-- sleep_sessions: one row per logged night
-- The core user data — must survive device loss and reinstall.
-- Composite PK (user_id, id) so each user's session IDs are
-- unique but different users can have colliding IDs safely.
-- ============================================================

create table if not exists public.sleep_sessions (
  id               text not null,
  user_id          uuid not null references auth.users(id) on delete cascade,
  started_at       timestamptz not null,
  ended_at         timestamptz not null,
  duration_minutes int not null,
  source           text not null default 'local',
  created_at       timestamptz not null default now(),
  primary key (user_id, id)
);

alter table public.sleep_sessions enable row level security;

create policy "Users manage own sessions"
  on public.sleep_sessions for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Chronological queries (profile chart, restore)
create index if not exists idx_sessions_user_ended
  on public.sleep_sessions (user_id, ended_at desc);

-- ============================================================
-- Auto-update profiles.updated_at on any row change
-- ============================================================

create or replace function public.handle_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger profiles_updated_at
  before update on public.profiles
  for each row execute function public.handle_updated_at();
