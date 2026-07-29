-- SleepBlock remote app config: the update gate.
-- Run after 003 (any order works — nothing here depends on the board).
--
-- One row per platform. The client compares its own version against
-- these on launch/foreground (`SleepUpdateGate.swift`):
--
--   * installed < min_supported_version  → full-screen blocking
--     "update required" gate. Reserved for releases where old clients
--     are actually broken (e.g. a schema change the old client can't
--     read). NEVER bump this before the new build is live on the App
--     Store — a gate whose Update button has nothing to install is a
--     trap. See docs/development.md "App update gate" for the release
--     checklist.
--   * installed < latest_version → quiet dismissible "update
--     available" card on Profile, once per version. Optional to
--     maintain; if it lags behind reality the nudge simply doesn't
--     fire.
--
-- Trust model matches the board's `score` column: no INSERT/UPDATE/
-- DELETE policies at all — the row is edited only via the SQL editor
-- or service role. Clients can read, nothing else.

create table if not exists public.app_config (
  platform              text primary key,
  min_supported_version text not null default '0.0.0',
  latest_version        text not null default '0.0.0',
  -- Optional copy shown on the blocking gate instead of the client's
  -- built-in fallback line, so the reason can be stated ("This version
  -- can't read your sleep record anymore.") without an app release.
  update_message        text,
  updated_at            timestamptz not null default now(),

  constraint app_config_platform_valid
    check (platform in ('ios', 'android'))
);

alter table public.app_config enable row level security;

-- Readable before sign-in resolves: the gate must be able to block a
-- broken client on the welcome screen too, not only after auth.
create policy "Anyone can read app config"
  on public.app_config for select
  to anon, authenticated
  using (true);

-- Reuses migration 001's trigger function.
drop trigger if exists app_config_updated_at on public.app_config;
create trigger app_config_updated_at
  before update on public.app_config
  for each row execute function public.handle_updated_at();

-- Seed both platforms at 0.0.0 — every client passes until a human
-- deliberately raises the bar.
insert into public.app_config (platform)
values ('ios'), ('android')
on conflict (platform) do nothing;
