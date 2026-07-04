// Supabase Edge Function: delete-account
//
// Permanently deletes the calling user and everything owned by them.
//
// The iOS app (see `SupabaseAuthClient.deleteAccount()`) POSTs here with the
// signed-in user's own access token (JWT) in the Authorization header. We
// verify that token, then use the SERVICE ROLE key — which lives only on the
// server, never in the shipped app — to delete that exact user from
// `auth.users`. Deleting the auth row cascades to any table whose foreign key
// to `auth.users` is declared `ON DELETE CASCADE`, so "delete the user" removes
// all of their data in one call. SleepBlock is local-first today (sleep history
// lives on-device), so the auth user is the only server-side record; if you add
// user-owned tables or Storage objects later, delete those here *before* the
// user-delete (or rely on cascade for tables).
//
// Deploy:
//   supabase functions deploy delete-account
//
// Env: SUPABASE_URL, SUPABASE_ANON_KEY, and SUPABASE_SERVICE_ROLE_KEY are all
// injected automatically into deployed functions — no manual secrets needed.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  // CORS preflight (harmless for the native app, needed if ever called from web).
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "Missing Authorization header" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json({ error: "Server is misconfigured" }, 500);
  }

  // 1. Identify the caller from their JWT. Using the anon client with the
  //    caller's Authorization header means getUser() resolves to *them* — we
  //    can only ever delete the user who made the request, never an arbitrary id.
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user },
    error: userErr,
  } = await userClient.auth.getUser();
  if (userErr || !user) {
    return json({ error: "Invalid or expired session" }, 401);
  }

  // 2. Delete that user with the privileged service-role client. Cascades to any
  //    `ON DELETE CASCADE` tables referencing auth.users.
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { error: delErr } = await admin.auth.admin.deleteUser(user.id);
  if (delErr) {
    return json({ error: delErr.message }, 500);
  }

  return json({ deleted: true, userId: user.id }, 200);
});
