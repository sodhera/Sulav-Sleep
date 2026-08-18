-- SleepBlock: partner pairing CODES, an in-app alternative to the
-- sleepblock:// invite link (see docs/roadmap-partner-referral.md, "v3").
--
-- Why this exists
-- ---------------
-- 006 shipped partnering as a custom-scheme link. That link only works if
-- the recipient already has the app: there is no associated-domains
-- entitlement, so no Universal Link and no App Store fallback, and most
-- messengers won't even make a `sleepblock://` string tappable. A friend
-- without SleepBlock hits a dead end, and the sender never learns it failed.
--
-- A short typed code fixes exactly that, because nothing has to survive the
-- install: "get SleepBlock, then enter 4KM9PX" works whether or not the app
-- is there yet, and it works out loud, in person — which is the common case
-- for sleep partners (roommates, couples, close friends).
--
-- What is deliberately NOT here
-- -----------------------------
-- A permanent per-user ID. A fixed, guessable handle would force back the
-- pending/confirm step 006 removed, because anyone could type it at you —
-- and what a partner sees (bed and wake time) is a schedule of when your
-- home is empty. These codes stay single-use and short-lived so the
-- auto-confirm in 006 remains honest.
--
-- Security shape, versus the link tokens in 006
-- --------------------------------------------
-- A link token is 96 bits and unguessable. A 6-character code is ~31^6
-- (about 887 million) and, unlike a link, is live in a guessable space for
-- a whole day. So this file adds the thing the link flow never needed:
-- server-side rate limiting on redemption attempts.
--
-- Which forces one structural choice worth understanding before editing:
-- `redeem_partner_code` RETURNS a result instead of RAISING. A raise aborts
-- the transaction, which would roll back the very attempt row the rate
-- limiter counts — so a raising function cannot rate-limit itself. The RPC
-- therefore never raises on user-facing failures; it returns
-- {ok, name, error} and the client turns `ok:false` into its error text.
-- `accept_partner_invite` (the link path) is left exactly as it was.

-- ============================================================
-- partner_code_attempts: the rate limiter's ledger
-- ============================================================

create table if not exists public.partner_code_attempts (
  id           bigint generated always as identity primary key,
  user_id      uuid not null references auth.users(id) on delete cascade,
  attempted_at timestamptz not null default now()
);

alter table public.partner_code_attempts enable row level security;

-- No client ever reads or writes this directly; only the SECURITY DEFINER
-- RPC below touches it. No policy = no client access, which is the intent.

create index if not exists idx_partner_code_attempts_user
  on public.partner_code_attempts (user_id, attempted_at desc);

-- ============================================================
-- create_partner_code(): mint (or re-show) the caller's code
-- ============================================================
--
-- Returns the SAME code while one is still alive rather than minting on
-- every tap: the user who reopens the screen to re-read a code they already
-- read out loud must not find a different one. 24 hours, not the 10 minutes
-- an in-person handoff would want, because the recipient may need to install
-- the app and make an account first.

create or replace function public.create_partner_code()
returns text
language plpgsql security definer set search_path = public
as $$
declare
  v_code text;
  -- Same alphabet as get_or_create_referral_code (005): no 0/O/1/I/L, so a
  -- code read aloud or off a screen can't be mistyped into a near-miss.
  v_alphabet constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  -- A live code the caller already has. Length 6 distinguishes codes from
  -- 006's base64url link tokens, which share this table.
  select token into v_code
  from partner_invites
  where owner_id = auth.uid()
    and length(token) = 6
    and consumed_at is null
    and expires_at > now()
  order by created_at desc
  limit 1;

  if v_code is not null then
    return v_code;
  end if;

  loop
    v_code := (
      select string_agg(substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1), '')
      from generate_series(1, 6)
    );
    begin
      insert into partner_invites (token, owner_id, expires_at)
      values (v_code, auth.uid(), now() + interval '24 hours');
      return v_code;
    exception
      when unique_violation then
        -- Collided with a live code someone else holds; go around again.
        null;
    end;
  end loop;
end;
$$;

-- ============================================================
-- redeem_partner_code(code): connect the caller to the code's
-- owner. Returns jsonb {ok, name, error} and NEVER raises for
-- a user-facing failure — see the header note on rate limiting.
-- ============================================================

create or replace function public.redeem_partner_code(p_code text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_code    text;
  v_owner   uuid;
  v_me      uuid := auth.uid();
  v_cap     constant int := 10;
  -- 10 wrong guesses per 15 minutes. Against ~887M codes that leaves brute
  -- force hopeless while staying invisible to anyone actually typing one.
  v_max_attempts constant int := 10;
  v_window  constant interval := interval '15 minutes';
  v_recent  int;
  v_owner_name text;
  v_my_name    text;
begin
  if v_me is null then
    return jsonb_build_object('ok', false, 'error', 'not authenticated');
  end if;

  -- Normalize to what the user meant: spaces and dashes out, uppercase in.
  v_code := upper(regexp_replace(coalesce(p_code, ''), '[\s-]', '', 'g'));
  if length(v_code) <> 6 then
    return jsonb_build_object('ok', false, 'error', 'That code doesn''t look right. Codes are 6 characters.');
  end if;

  -- Housekeeping, cheap and indexed: this ledger has no other reaper.
  delete from partner_code_attempts
  where user_id = v_me and attempted_at < now() - interval '1 day';

  select count(*) into v_recent
  from partner_code_attempts
  where user_id = v_me and attempted_at > now() - v_window;

  if v_recent >= v_max_attempts then
    return jsonb_build_object('ok', false, 'error', 'Too many tries. Wait a few minutes and try again.');
  end if;

  insert into partner_code_attempts (user_id) values (v_me);

  -- Valid = exists, unconsumed, unexpired. Locked so two simultaneous
  -- redemptions of one single-use code can't both win.
  select owner_id into v_owner
  from partner_invites
  where token = v_code and consumed_at is null and expires_at > now()
  for update;

  if v_owner is null then
    return jsonb_build_object('ok', false, 'error', 'That code has expired or already been used.');
  end if;
  if v_owner = v_me then
    return jsonb_build_object('ok', false, 'error', 'That''s your own code — give it to a friend.');
  end if;

  -- Already partners? Idempotent success; just burn the code.
  if exists (
    select 1 from partnerships
    where status = 'confirmed'
      and ((inviter_id = v_owner and invitee_id = v_me)
        or (inviter_id = v_me and invitee_id = v_owner))
  ) then
    update partner_invites
      set consumed_at = now(), consumed_by = v_me
      where token = v_code;
    select name into v_owner_name from profiles where id = v_owner;
    return jsonb_build_object('ok', true, 'name', coalesce(v_owner_name, ''));
  end if;

  if partner_count(v_owner) >= v_cap then
    return jsonb_build_object('ok', false, 'error', 'Your friend already has the maximum number of partners.');
  end if;
  if partner_count(v_me) >= v_cap then
    return jsonb_build_object('ok', false, 'error', 'You already have the maximum number of partners.');
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
    where token = v_code;

  -- A successful redemption shouldn't count against the next one.
  delete from partner_code_attempts where user_id = v_me;

  return jsonb_build_object('ok', true, 'name', coalesce(v_owner_name, ''));
end;
$$;

-- Signed-in only.
revoke execute on function public.create_partner_code() from public, anon;
revoke execute on function public.redeem_partner_code(text) from public, anon;
grant execute on function public.create_partner_code() to authenticated;
grant execute on function public.redeem_partner_code(text) to authenticated;
