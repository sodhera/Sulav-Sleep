-- Show who asked: an author name on every feature request.
-- Run after 002.
--
-- ============================================================
-- Why the name is COPIED onto the row, not joined from profiles
-- ============================================================
-- The obvious implementation is a join to public.profiles.name,
-- which would require a SELECT policy letting any signed-in user
-- read other people's profile rows. That table also holds
-- bedtime, wake time, sleep struggles, goals and onboarding
-- answers — opening it up to read one column would expose all
-- of them, and would expose every user, including people who
-- never posted anything.
--
-- Instead the name is snapshotted onto the request at insert
-- time by a trigger. Consequences, both intended:
--
--   * profiles stays completely private. The only names that
--     ever become public are those of users who chose to post.
--   * The name is not client-supplied. The trigger overwrites
--     whatever the client sent, so a caller hitting PostgREST
--     directly cannot post under someone else's name.
--   * A later rename does not rewrite old posts. That is the
--     correct behavior for a board — a request is a thing
--     someone said at a point in time — but it does mean the
--     board and Settings can legitimately disagree.

alter table public.feature_requests
  add column if not exists author_name text not null default '';

-- ============================================================
-- Stamp the author's current profile name onto each new row.
-- SECURITY DEFINER so it can read profiles despite that table's
-- owner-only RLS; search_path pinned so the elevated function
-- can't be pointed at a shadowed table.
-- ============================================================

create or replace function public.set_feature_request_author_name()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  profile_name text;
begin
  select btrim(p.name) into profile_name
    from public.profiles p
   where p.id = new.author_id;

  -- Users who somehow have no profile row, or a blank name, post
  -- as "Someone" rather than as an empty gap in the layout.
  new.author_name := coalesce(nullif(profile_name, ''), 'Someone');
  return new;
end;
$$;

drop trigger if exists feature_requests_author_name on public.feature_requests;
create trigger feature_requests_author_name
  before insert on public.feature_requests
  for each row execute function public.set_feature_request_author_name();

-- ============================================================
-- Backfill rows created before this migration.
-- ============================================================

update public.feature_requests fr
   set author_name = coalesce(nullif(btrim(p.name), ''), 'Someone')
  from public.profiles p
 where p.id = fr.author_id
   and btrim(fr.author_name) = '';

update public.feature_requests
   set author_name = 'Someone'
 where btrim(author_name) = '';
