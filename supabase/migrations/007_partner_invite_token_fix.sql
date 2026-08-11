-- Fix: create_partner_invite() failed at runtime.
--
-- The function is SECURITY DEFINER with `search_path = public` (correct
-- definer hygiene), but it called `gen_random_bytes` — which on Supabase
-- lives in the `extensions` schema, not `public` — so it couldn't resolve
-- and every invite mint threw. `gen_random_uuid()` is core Postgres
-- (pg_catalog, always on the path), needs no extension, and 122 bits of
-- randomness in 32 hex chars is plenty for a single-use, 7-day token.
--
-- Idempotent: create-or-replace, safe to re-run.

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

  -- 32 URL-safe hex chars, no pgcrypto dependency.
  v_token := replace(gen_random_uuid()::text, '-', '')
           || replace(gen_random_uuid()::text, '-', '');

  insert into partner_invites (token, owner_id, expires_at)
  values (v_token, auth.uid(), now() + interval '7 days');

  return v_token;
end;
$$;

revoke execute on function public.create_partner_invite() from public, anon;
grant execute on function public.create_partner_invite() to authenticated;
