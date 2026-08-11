-- SleepBlock: decouple partnerships from referrals, add multi-partner via
-- invite links (see docs/roadmap-partner-referral.md).
--
-- The old model fused the two: the only way to get a partner was to redeem
-- someone's referral code, which capped everyone at one partner and left
-- existing paid users unable to partner at all (they can't meaningfully
-- redeem). This splits them cleanly:
--
--   * Referral stays a growth mechanic — a code that grants free nights and
--     banks a reward when the referee subscribes. It no longer touches
--     partnerships at all (the redeem-referral function drops that write).
--   * Partnership becomes its own thing: an invite LINK anyone can send to
--     anyone, regardless of subscription. Both sides consent — the owner by
--     creating the link, the recipient by tapping it — so accepting connects
--     directly with no separate confirm step. Safety rests on the token
--     being single-use and short-lived, plus unilateral unlink either side
--     can pull instantly.
--
-- Multiple partners are allowed (capped). The partner_summaries RLS from 005
-- already scales to many (it's an EXISTS over confirmed partnerships), so the
-- only real work here is the invite table + the two RPCs.

-- ============================================================
-- partner_invites: one-time, expiring tokens behind the links
-- ============================================================

create table if not exists public.partner_invites (
  token       text primary key,
  owner_id    uuid not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null,
  -- Set the moment someone accepts; a second accept then finds nothing.
  consumed_at timestamptz,
  consumed_by uuid references auth.users(id) on delete set null
);

alter table public.partner_invites enable row level security;

-- The owner may read their own invites (to show / revoke); creation and
-- consumption happen only through the SECURITY DEFINER RPCs below.
create policy "Owners read own invites"
  on public.partner_invites for select
  using (auth.uid() = owner_id);

create index if not exists idx_partner_invites_owner
  on public.partner_invites (owner_id);

-- ============================================================
-- partnerships: carry both display names, so the partners list
-- has a name to show even before the other side has synced a
-- summary row. (invitee_name already exists from 005.)
-- ============================================================

alter table public.partnerships
  add column if not exists inviter_name text not null default '';

-- The single-confirmed-partner rule lived in `confirm_partnership`; the new
-- flow auto-confirms and never calls it, and redemptions no longer create
-- pending rows, so the confirm/decline RPCs are dead. Drop them so nothing
-- reintroduces the one-partner cap by accident.
drop function if exists public.confirm_partnership(uuid);
drop function if exists public.decline_partnership(uuid);

-- ============================================================
-- How many partners a user already has (either side of a
-- confirmed partnership). Used for the cap.
-- ============================================================

create or replace function public.partner_count(p_user uuid)
returns int
language sql stable security definer set search_path = public
as $$
  select count(*)::int
  from partnerships
  where status = 'confirmed'
    and (inviter_id = p_user or invitee_id = p_user);
$$;

-- The most partners one account may hold. Generous but bounded — a runaway
-- graph is both a privacy surface and a fetch cost.
-- (Expressed inline in accept_partner_invite; kept here as documentation.)

-- ============================================================
-- create_partner_invite(): mint a link token for the caller
-- ============================================================

create or replace function public.create_partner_invite()
returns text
language plpgsql security definer set search_path = public
as $$
declare
  v_token text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  -- 96 bits of URL-safe randomness — unguessable, and short-lived + one-use
  -- on top of that.
  v_token := replace(replace(
    encode(gen_random_bytes(12), 'base64'), '+', '-'), '/', '_');
  v_token := rtrim(v_token, '=');

  insert into partner_invites (token, owner_id, expires_at)
  values (v_token, auth.uid(), now() + interval '7 days');

  return v_token;
end;
$$;

-- ============================================================
-- accept_partner_invite(token): connect the caller to the
-- invite's owner. Auto-confirmed — both parties consented.
-- Returns the new partner's display name (or '').
-- ============================================================

create or replace function public.accept_partner_invite(p_token text)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  v_owner   uuid;
  v_me      uuid := auth.uid();
  v_cap     constant int := 10;
  v_owner_name text;
  v_my_name    text;
begin
  if v_me is null then
    raise exception 'not authenticated';
  end if;

  -- Valid = exists, unconsumed, unexpired. Lock the row so two simultaneous
  -- accepts of the same one-time token can't both win.
  select owner_id into v_owner
  from partner_invites
  where token = p_token and consumed_at is null and expires_at > now()
  for update;

  if v_owner is null then
    raise exception 'This invite has expired or already been used.';
  end if;
  if v_owner = v_me then
    raise exception 'That''s your own invite — send it to a friend.';
  end if;

  -- Already partners? Treat as success (idempotent re-tap), just consume.
  if exists (
    select 1 from partnerships
    where status = 'confirmed'
      and ((inviter_id = v_owner and invitee_id = v_me)
        or (inviter_id = v_me and invitee_id = v_owner))
  ) then
    update partner_invites
      set consumed_at = now(), consumed_by = v_me
      where token = p_token;
    select name into v_owner_name from profiles where id = v_owner;
    return coalesce(v_owner_name, '');
  end if;

  if partner_count(v_owner) >= v_cap then
    raise exception 'Your friend already has the maximum number of partners.';
  end if;
  if partner_count(v_me) >= v_cap then
    raise exception 'You already have the maximum number of partners.';
  end if;

  select name into v_owner_name from profiles where id = v_owner;
  select name into v_my_name from profiles where id = v_me;

  insert into partnerships
    (inviter_id, invitee_id, inviter_name, invitee_name, status, confirmed_at)
  values
    (v_owner, v_me, coalesce(v_owner_name, ''), coalesce(v_my_name, ''),
     'confirmed', now());

  update partner_invites
    set consumed_at = now(), consumed_by = v_me
    where token = p_token;

  return coalesce(v_owner_name, '');
end;
$$;

-- Signed-in only.
revoke execute on function public.create_partner_invite() from public, anon;
revoke execute on function public.accept_partner_invite(text) from public, anon;
revoke execute on function public.partner_count(uuid) from public, anon;
grant execute on function public.create_partner_invite() to authenticated;
grant execute on function public.accept_partner_invite(text) to authenticated;
