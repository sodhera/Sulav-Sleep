-- SleepBlock referral + sleep partner (see docs/roadmap-partner-referral.md).
-- Run after 004. One program: the partner invite IS the referral code.
--
-- Trust model, table by table:
--   * Clients WRITE nothing here directly. Redemptions and rewards are
--     written only by edge functions (service role bypasses RLS);
--     partnership state changes only through the SECURITY DEFINER RPCs
--     below, which hold the invariants. The single exception is
--     partner_summaries, which its owner upserts directly on sync.
--   * The ONLY cross-account read in the whole database is a confirmed
--     partner reading the other's partner_summaries row — derived
--     numbers, never raw sleep_sessions. That policy is the privacy
--     model; guard it accordingly.

-- ============================================================
-- referral_codes: one shareable code per user, created lazily
-- ============================================================

create table if not exists public.referral_codes (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  code       text not null unique,
  created_at timestamptz not null default now()
);

alter table public.referral_codes enable row level security;

create policy "Users read own referral code"
  on public.referral_codes for select
  using (auth.uid() = user_id);

-- ============================================================
-- referral_redemptions: who redeemed whose code, and the 30
-- free nights it granted. PK on invitee_id = one redemption
-- per account, ever, enforced by the table itself.
-- ============================================================

create table if not exists public.referral_redemptions (
  invitee_id   uuid primary key references auth.users(id) on delete cascade,
  referrer_id  uuid not null references auth.users(id) on delete cascade,
  code         text not null,
  free_until   timestamptz not null,
  -- Set by the RevenueCat webhook on the invitee's first *paid*
  -- transaction; the guard that a conversion is counted once.
  converted_at timestamptz,
  redeemed_at  timestamptz not null default now(),

  constraint redemption_not_self check (invitee_id <> referrer_id)
);

alter table public.referral_redemptions enable row level security;

-- The invitee's app reads free_until from here; the referrer's Settings
-- counts invited friends. Neither can write.
create policy "Members read own redemptions"
  on public.referral_redemptions for select
  using (auth.uid() = invitee_id or auth.uid() = referrer_id);

create index if not exists idx_redemptions_referrer
  on public.referral_redemptions (referrer_id);

-- ============================================================
-- referral_rewards: the referrer's banked months, a ledger.
-- 30 days bank per conversion; the webhook applies banked days
-- as App Store renewal extensions (<=90/call, 2 calls/year —
-- hence the 180-days-per-365 cap enforced at insert time in
-- the webhook, not here: the cap is policy, not integrity).
-- ============================================================

create table if not exists public.referral_rewards (
  id                    uuid primary key default gen_random_uuid(),
  referrer_id           uuid not null references auth.users(id) on delete cascade,
  -- One reward per conversion, enforced structurally.
  redemption_invitee_id uuid not null unique references public.referral_redemptions(invitee_id) on delete cascade,
  days                  int not null default 30,
  status                text not null default 'banked',
  applied_at            timestamptz,
  created_at            timestamptz not null default now(),

  constraint reward_status_valid check (status in ('banked', 'applied', 'void'))
);

alter table public.referral_rewards enable row level security;

create policy "Referrers read own rewards"
  on public.referral_rewards for select
  using (auth.uid() = referrer_id);

create index if not exists idx_rewards_referrer_status
  on public.referral_rewards (referrer_id, status);

-- ============================================================
-- partnerships: the consent record. Redemption files a pending
-- row; nothing is shared until the inviter confirms. One
-- CONFIRMED partnership per user (v1) — held by the RPCs.
-- ============================================================

create table if not exists public.partnerships (
  id           uuid primary key default gen_random_uuid(),
  inviter_id   uuid not null references auth.users(id) on delete cascade,
  invitee_id   uuid not null references auth.users(id) on delete cascade,
  -- Copied from profiles.name at redemption time (service role) so the
  -- inviter's confirm card can say WHO is asking — the summaries table
  -- is deliberately unreadable until the partnership is confirmed, and
  -- a nameless "someone wants to see your sleep" card is unanswerable.
  invitee_name text not null default '',
  status       text not null default 'pending',
  created_at   timestamptz not null default now(),
  confirmed_at timestamptz,

  constraint partnership_not_self check (inviter_id <> invitee_id),
  constraint partnership_status_valid check (status in ('pending', 'confirmed')),
  unique (inviter_id, invitee_id)
);

alter table public.partnerships enable row level security;

create policy "Members read own partnerships"
  on public.partnerships for select
  using (auth.uid() = inviter_id or auth.uid() = invitee_id);

create index if not exists idx_partnerships_invitee
  on public.partnerships (invitee_id);

-- ============================================================
-- partner_summaries: the derived numbers a confirmed partner
-- may see. Owner-written on each cloud sync; raw sessions
-- never cross accounts.
-- ============================================================

create table if not exists public.partner_summaries (
  user_id              uuid primary key references auth.users(id) on delete cascade,
  name                 text not null default '',
  streak               int not null default 0,
  streak_dying         bool not null default false,
  avg_bed_minutes      int,
  avg_wake_minutes     int,
  avg_duration_minutes int,
  nights               int not null default 0,
  updated_at           timestamptz not null default now()
);

alter table public.partner_summaries enable row level security;

create policy "Users manage own summary"
  on public.partner_summaries for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- THE cross-account read: a confirmed partner, either direction.
create policy "Confirmed partners read each other's summary"
  on public.partner_summaries for select
  using (
    exists (
      select 1 from public.partnerships p
      where p.status = 'confirmed'
        and ((p.inviter_id = auth.uid() and p.invitee_id = partner_summaries.user_id)
          or (p.invitee_id = auth.uid() and p.inviter_id = partner_summaries.user_id))
    )
  );

drop trigger if exists partner_summaries_updated_at on public.partner_summaries;
create trigger partner_summaries_updated_at
  before update on public.partner_summaries
  for each row execute function public.handle_updated_at();

-- ============================================================
-- RPCs. SECURITY DEFINER so the invariants live here, not in
-- app code; search_path pinned per the usual definer hygiene.
-- ============================================================

-- The caller's shareable code, created on first ask. Retries on the
-- (astronomically rare) collision; the alphabet drops 0/O/1/I/L so the
-- code survives being read aloud.
create or replace function public.get_or_create_referral_code()
returns text
language plpgsql security definer set search_path = public
as $$
declare
  v_code text;
  v_alphabet constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select code into v_code from referral_codes where user_id = auth.uid();
  if v_code is not null then
    return v_code;
  end if;

  loop
    v_code := (
      select string_agg(substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1), '')
      from generate_series(1, 6)
    );
    begin
      insert into referral_codes (user_id, code) values (auth.uid(), v_code);
      return v_code;
    exception
      when unique_violation then
        -- Either the code collided (retry) or a concurrent call already
        -- created the caller's row (return it).
        select code into v_code from referral_codes where user_id = auth.uid();
        if v_code is not null then
          return v_code;
        end if;
    end;
  end loop;
end;
$$;

-- Inviter accepts. Holds the single-slot rule: fails if either side
-- already has a confirmed partnership. Advisory locks on both user ids
-- close the race where two confirms land at once.
create or replace function public.confirm_partnership(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v partnerships%rowtype;
begin
  select * into v from partnerships where id = p_id and status = 'pending';
  if not found then
    raise exception 'no pending partnership';
  end if;
  if v.inviter_id <> auth.uid() then
    raise exception 'only the inviter can confirm';
  end if;

  perform pg_advisory_xact_lock(hashtext(v.inviter_id::text));
  perform pg_advisory_xact_lock(hashtext(v.invitee_id::text));

  if exists (
    select 1 from partnerships
    where status = 'confirmed'
      and (inviter_id in (v.inviter_id, v.invitee_id)
        or invitee_id in (v.inviter_id, v.invitee_id))
  ) then
    raise exception 'partner slot already taken';
  end if;

  update partnerships
     set status = 'confirmed', confirmed_at = now()
   where id = p_id;
end;
$$;

-- Either member walks away from a pending request…
create or replace function public.decline_partnership(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  delete from partnerships
   where id = p_id and status = 'pending'
     and (inviter_id = auth.uid() or invitee_id = auth.uid());
  if not found then
    raise exception 'no pending partnership';
  end if;
end;
$$;

-- …or from a confirmed one. Unilateral and immediate, by design.
create or replace function public.unlink_partnership(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  delete from partnerships
   where id = p_id and status = 'confirmed'
     and (inviter_id = auth.uid() or invitee_id = auth.uid());
  if not found then
    raise exception 'no confirmed partnership';
  end if;
end;
$$;

-- Definer functions default to PUBLIC-executable; tighten to signed-in.
revoke execute on function public.get_or_create_referral_code() from public, anon;
revoke execute on function public.confirm_partnership(uuid) from public, anon;
revoke execute on function public.decline_partnership(uuid) from public, anon;
revoke execute on function public.unlink_partnership(uuid) from public, anon;
grant execute on function public.get_or_create_referral_code() to authenticated;
grant execute on function public.confirm_partnership(uuid) to authenticated;
grant execute on function public.decline_partnership(uuid) to authenticated;
grant execute on function public.unlink_partnership(uuid) to authenticated;
