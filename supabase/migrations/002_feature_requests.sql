-- SleepBlock feature request board
-- Run in the Supabase SQL Editor or via `supabase db push`.
--
-- ============================================================
-- IMPORTANT: this is the app's FIRST cross-user data.
-- ============================================================
-- Every table in 001 is strictly private: the policy is always
-- `auth.uid() = <owner column>`, so a user can only ever see
-- their own rows. The board breaks that on purpose — the whole
-- point is reading what other people asked for — so the rules
-- here are written far more defensively than 001's:
--
--   * Request TEXT is world-readable (to signed-in users).
--   * Individual VOTES are NOT. You can read only your own, so
--     "who downvoted me" is unanswerable by design. The public
--     signal is the aggregate `score` column and nothing else.
--   * `score` is NOT user-writable. There is deliberately no
--     UPDATE policy on feature_requests at all; the column is
--     maintained solely by a SECURITY DEFINER trigger on the
--     votes table. Without this, "users manage own rows" would
--     have let anyone set their own request to score = 9999.
--   * Inserts are pinned to `auth.uid()` and forced to start at
--     score 0 / status 'open', so a request can't be born
--     popular or pre-approved.

-- ============================================================
-- feature_requests: one row per idea
--
-- author_id CASCADEs on user delete. The delete-account flow
-- promises "permanently deletes your account and sleep history
-- from our servers"; leaving a user's posted text on a public
-- board after they deleted their account would not honor that,
-- so their requests go with them (and the votes cast on those
-- requests cascade in turn).
-- ============================================================

create table if not exists public.feature_requests (
  id         uuid primary key default gen_random_uuid(),
  author_id  uuid not null references auth.users(id) on delete cascade,
  title      text not null,
  -- 'hidden' is the moderation lever: it is filtered out of every
  -- client read, so taking abusive content down is a one-line
  -- UPDATE and never a DELETE (the audit trail survives).
  status     text not null default 'open',
  score      int  not null default 0,
  created_at timestamptz not null default now(),

  constraint feature_requests_title_length
    check (char_length(btrim(title)) between 3 and 140),
  constraint feature_requests_status_valid
    check (status in ('open', 'planned', 'shipped', 'hidden'))
);

alter table public.feature_requests enable row level security;

-- Read: any signed-in user sees the board, minus moderated rows.
create policy "Signed-in users read the board"
  on public.feature_requests for select
  to authenticated
  using (status <> 'hidden');

-- Write: you may only post as yourself, and only at a standing
-- start. No UPDATE policy exists, so nothing here is editable
-- after the fact — including by the author.
create policy "Users post their own requests"
  on public.feature_requests for insert
  to authenticated
  with check (
    auth.uid() = author_id
    and score = 0
    and status = 'open'
  );

create policy "Users delete their own requests"
  on public.feature_requests for delete
  to authenticated
  using (auth.uid() = author_id);

-- Board ordering: highest score first, newest as the tiebreak.
create index if not exists idx_feature_requests_rank
  on public.feature_requests (score desc, created_at desc);

-- ============================================================
-- feature_request_votes: one vote per user per request
-- The PK is what makes a vote idempotent — re-voting upserts
-- over the old row rather than stacking, so no one can vote a
-- request up twice by tapping twice.
-- ============================================================

create table if not exists public.feature_request_votes (
  request_id uuid not null references public.feature_requests(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  value      smallint not null,
  created_at timestamptz not null default now(),

  primary key (request_id, user_id),
  constraint feature_request_votes_value_valid check (value in (-1, 1))
);

alter table public.feature_request_votes enable row level security;

-- Deliberately NOT world-readable: only your own ballot. The
-- board shows aggregate score, never who cast what.
create policy "Users manage own votes"
  on public.feature_request_votes for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ============================================================
-- score maintenance
--
-- SECURITY DEFINER because users hold no UPDATE privilege on
-- feature_requests — that's the whole point. The function owner
-- does, and owners bypass RLS, so the score stays a value only
-- the database itself can move. search_path is pinned so the
-- elevated function can't be redirected at a shadowed table.
-- ============================================================

create or replace function public.sync_feature_request_score()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (tg_op = 'INSERT') then
    update public.feature_requests
       set score = score + new.value
     where id = new.request_id;
  elsif (tg_op = 'UPDATE') then
    update public.feature_requests
       set score = score - old.value + new.value
     where id = new.request_id;
  elsif (tg_op = 'DELETE') then
    update public.feature_requests
       set score = score - old.value
     where id = old.request_id;
  end if;
  return null;
end;
$$;

drop trigger if exists feature_request_votes_score on public.feature_request_votes;
create trigger feature_request_votes_score
  after insert or update or delete on public.feature_request_votes
  for each row execute function public.sync_feature_request_score();

-- ============================================================
-- spam guard
--
-- A public board with a free-text input is the one surface in
-- this app a single account can flood. Five a day is generous
-- for a genuine user and useless to a script.
-- ============================================================

create or replace function public.check_feature_request_quota()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  recent int;
begin
  select count(*) into recent
    from public.feature_requests
   where author_id = new.author_id
     and created_at > now() - interval '1 day';

  if recent >= 5 then
    raise exception 'Feature request limit reached. Try again tomorrow.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists feature_requests_quota on public.feature_requests;
create trigger feature_requests_quota
  before insert on public.feature_requests
  for each row execute function public.check_feature_request_quota();
