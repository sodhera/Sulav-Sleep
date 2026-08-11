// Supabase Edge Function: redeem-referral
//
// A signed-in user redeems a friend's referral code. On success they get
// 30 free nights (`free_until`, server-dated — the app's lock exemption
// reads this row, so a device clock rollback buys nothing) and a *pending*
// partnership request is filed toward the code's owner. Nothing is shared
// until the owner confirms — see docs/roadmap-partner-referral.md.
//
// Client writes are impossible here by RLS design: redemptions are created
// only by this function's service-role client, after the checks the tables
// themselves can't express (code exists, isn't the caller's own). The
// one-redemption-per-account rule needs no code at all — it's the table's
// primary key.
//
// Deploy:
//   supabase functions deploy redeem-referral
//
// Env: SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are
// injected automatically. verify_jwt stays ON (config.toml).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const FREE_NIGHTS_DAYS = 30;

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

  // Codes are typed by humans off a text message: forgive case, spaces,
  // and stray hyphens. The alphabet has no 0/O/1/I/L ambiguity to map.
  let code: string;
  try {
    const body = await req.json();
    code = String(body?.code ?? "").toUpperCase().replace(/[\s-]/g, "");
  } catch {
    return json({ error: "Invalid request body" }, 400);
  }
  if (!/^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{6}$/.test(code)) {
    return json({ error: "That doesn't look like a referral code." }, 400);
  }

  // Identify the caller from their own JWT (the delete-account pattern):
  // we can only ever act as the user who made the request.
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

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: codeRow } = await admin
    .from("referral_codes")
    .select("user_id, code")
    .eq("code", code)
    .maybeSingle();
  if (!codeRow) {
    return json({ error: "That code doesn't exist. Check it and try again." }, 404);
  }
  if (codeRow.user_id === user.id) {
    return json({ error: "That's your own code — send it to a friend instead." }, 400);
  }

  const freeUntil = new Date(
    Date.now() + FREE_NIGHTS_DAYS * 24 * 60 * 60 * 1000,
  ).toISOString();

  // The PK enforces one-redemption-per-account; a duplicate insert is the
  // "already used a code" answer, not a server error.
  const { error: insertErr } = await admin.from("referral_redemptions").insert({
    invitee_id: user.id,
    referrer_id: codeRow.user_id,
    code: codeRow.code,
    free_until: freeUntil,
  });
  if (insertErr) {
    if (insertErr.code === "23505") {
      return json({ error: "This account has already used a referral code." }, 409);
    }
    console.error("redeem-referral: insert failed", insertErr.message);
    return json({ error: "Couldn't redeem the code. Try again in a moment." }, 500);
  }

  // File the partnership request. Best-effort: the unique pair constraint
  // makes a re-file a no-op, and a failure here must not undo the nights
  // the user was just told they have. The invitee's name rides on the row
  // because the summaries table stays unreadable until confirmation.
  const { data: profile } = await admin
    .from("profiles")
    .select("name")
    .eq("id", user.id)
    .maybeSingle();
  const { error: pErr } = await admin.from("partnerships").upsert(
    {
      inviter_id: codeRow.user_id,
      invitee_id: user.id,
      invitee_name: profile?.name ?? "",
    },
    { onConflict: "inviter_id,invitee_id", ignoreDuplicates: true },
  );
  if (pErr) {
    console.error("redeem-referral: partnership file failed", pErr.message);
  }

  return json({ free_until: freeUntil }, 200);
});
