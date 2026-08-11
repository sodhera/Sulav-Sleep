// Supabase Edge Function: revenuecat-webhook
//
// RevenueCat's server → us, on every subscription event. Three jobs, all
// referral-program bookkeeping (docs/roadmap-partner-referral.md):
//
//   1. CONVERSION — the first *paid* transaction (period_type NORMAL; trial
//      starts don't count) of a user who redeemed a referral code marks the
//      redemption converted and banks a 30-day reward for the referrer,
//      capped at 180 banked days per rolling 365 (Apple's own extension
//      ceiling: 90 days/call, 2 calls/subscription/year).
//   2. REFUND — a refunded conversion voids the referrer's still-banked
//      reward. Applied rewards are never clawed back.
//   3. APPLY — any event is an excuse to try turning banked days into a
//      real App Store renewal extension for whoever it concerns. Riding on
//      webhook traffic means retries need no cron: a failed apply stays
//      banked and the next event tries again.
//
// Idempotency: RevenueCat retries deliveries, so every step must be
// replay-safe. Inserts are guarded by PKs/UNIQUEs, conversion by the
// converted_at null-check, and the (non-idempotent) Apple call flips the
// ledger to `applied` first and reverts on failure — losing a reward to a
// crash in that window is recoverable by hand; silently granting doubles
// is not.
//
// Deploy (JWT verification OFF — RevenueCat is not a Supabase user; see
// config.toml — auth is the shared token instead):
//   supabase functions deploy revenuecat-webhook
//
// Secrets (supabase secrets set …):
//   REVENUECAT_WEBHOOK_TOKEN  the exact Authorization header value the
//                             RevenueCat dashboard is configured to send
//   REVENUECAT_SECRET_KEY     RevenueCat REST secret key (sk_…), used to
//                             look up a referrer's transaction id
//   ASC_ISSUER_ID / ASC_KEY_ID / ASC_PRIVATE_KEY
//                             App Store Connect In-App Purchase API key
//                             (.p8 contents in ASC_PRIVATE_KEY)
//   APP_BUNDLE_ID             e.g. com.sulav.sleepblock
//   ASC_USE_SANDBOX           optional "true" → sandbox StoreKit host

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

const REWARD_DAYS = 30;
const BANK_CAP_DAYS_PER_YEAR = 180;
const MAX_EXTEND_PER_CALL = 90;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// ---------------------------------------------------------------- Apple JWT

/// Short-lived ES256 token for the App Store Server API, signed with the
/// In-App Purchase key. Rebuilt per request — at 20 minutes' validity,
/// caching would buy nothing but a stale-token bug.
async function appleToken(): Promise<string> {
  const issuer = Deno.env.get("ASC_ISSUER_ID")!;
  const keyId = Deno.env.get("ASC_KEY_ID")!;
  const pem = Deno.env.get("ASC_PRIVATE_KEY")!;
  const bundleId = Deno.env.get("APP_BUNDLE_ID")!;

  const der = Uint8Array.from(
    atob(pem.replace(/-----[^-]+-----/g, "").replace(/\s/g, "")),
    (c) => c.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const b64url = (data: Uint8Array | string) => {
    const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
    return btoa(String.fromCharCode(...bytes))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  };

  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "ES256", kid: keyId, typ: "JWT" }));
  const payload = b64url(JSON.stringify({
    iss: issuer,
    iat: now,
    exp: now + 20 * 60,
    aud: "appstoreconnect-v1",
    bid: bundleId,
  }));
  const sig = new Uint8Array(await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(`${header}.${payload}`),
  ));
  return `${header}.${payload}.${b64url(sig)}`;
}

function appleHost(): string {
  return Deno.env.get("ASC_USE_SANDBOX") === "true"
    ? "https://api.storekit-sandbox.itunes.apple.com"
    : "https://api.storekit.itunes.apple.com";
}

/// PUT the renewal extension. Returns whether Apple accepted it.
async function extendRenewal(
  originalTransactionId: string,
  days: number,
): Promise<boolean> {
  try {
    const res = await fetch(
      `${appleHost()}/inApps/v1/subscriptions/extend/${originalTransactionId}`,
      {
        method: "PUT",
        headers: {
          Authorization: `Bearer ${await appleToken()}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          extendByDays: days,
          extendReasonCode: 1, // customer satisfaction
          requestIdentifier: crypto.randomUUID(),
        }),
      },
    );
    if (!res.ok) {
      console.error("extendRenewal: Apple said", res.status, await res.text());
      return false;
    }
    const body = await res.json();
    return body?.success === true;
  } catch (e) {
    console.error("extendRenewal failed:", e);
    return false;
  }
}

// ------------------------------------------------- RevenueCat REST lookup

/// The referrer isn't the event's subject, so their current App Store
/// transaction id has to come from RevenueCat's REST API. Only an active,
/// *paid* App Store subscription qualifies — extensions on a trial are
/// refused by Apple anyway.
async function lookupTransactionId(appUserId: string): Promise<string | null> {
  const key = Deno.env.get("REVENUECAT_SECRET_KEY");
  if (!key) return null;
  try {
    const res = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserId)}`,
      { headers: { Authorization: `Bearer ${key}` } },
    );
    if (!res.ok) return null;
    const body = await res.json();
    const subs = body?.subscriber?.subscriptions ?? {};
    for (const sub of Object.values(subs) as Record<string, unknown>[]) {
      if (sub.store !== "app_store") continue;
      if (sub.period_type !== "normal") continue;
      const expires = sub.expires_date ? Date.parse(String(sub.expires_date)) : 0;
      if (expires < Date.now()) continue;
      const id = sub.original_transaction_id ?? sub.store_transaction_id;
      if (id) return String(id);
    }
    return null;
  } catch (e) {
    console.error("lookupTransactionId failed:", e);
    return null;
  }
}

// ------------------------------------------------------------ bookkeeping

/// First paid transaction of a referred user → converted + banked reward.
async function handleConversion(admin: SupabaseClient, uid: string) {
  const { data: redemption } = await admin
    .from("referral_redemptions")
    .select("invitee_id, referrer_id, converted_at")
    .eq("invitee_id", uid)
    .is("converted_at", null)
    .maybeSingle();
  if (!redemption) return;

  await admin
    .from("referral_redemptions")
    .update({ converted_at: new Date().toISOString() })
    .eq("invitee_id", uid)
    .is("converted_at", null);

  // The 180/365 cap is policy, enforced here where the insert happens.
  const yearAgo = new Date(Date.now() - 365 * 24 * 60 * 60 * 1000).toISOString();
  const { data: recent } = await admin
    .from("referral_rewards")
    .select("days, status")
    .eq("referrer_id", redemption.referrer_id)
    .neq("status", "void")
    .gte("created_at", yearAgo);
  const banked = (recent ?? []).reduce((sum, r) => sum + r.days, 0);
  if (banked + REWARD_DAYS > BANK_CAP_DAYS_PER_YEAR) {
    console.log("conversion counted but reward capped for", redemption.referrer_id);
    return;
  }

  // UNIQUE(redemption_invitee_id) makes a webhook replay a no-op.
  const { error } = await admin.from("referral_rewards").insert({
    referrer_id: redemption.referrer_id,
    redemption_invitee_id: uid,
    days: REWARD_DAYS,
  });
  if (error && error.code !== "23505") {
    console.error("reward insert failed:", error.message);
  }
}

/// Refunded conversion → void the reward if it hasn't been applied yet.
async function handleRefund(admin: SupabaseClient, uid: string) {
  await admin
    .from("referral_rewards")
    .update({ status: "void" })
    .eq("redemption_invitee_id", uid)
    .eq("status", "banked");
}

/// Turn banked days into a real extension, if the user currently has an
/// applicable subscription. `eventTransactionId` short-circuits the REST
/// lookup when the user is the event's own subject.
async function applyBanked(
  admin: SupabaseClient,
  uid: string,
  eventTransactionId: string | null,
) {
  const { data: rewards } = await admin
    .from("referral_rewards")
    .select("id, days")
    .eq("referrer_id", uid)
    .eq("status", "banked")
    .order("created_at", { ascending: true });
  if (!rewards || rewards.length === 0) return;

  const txId = eventTransactionId ?? await lookupTransactionId(uid);
  if (!txId) return; // no active paid sub — stays banked

  // Greedy batch of whole rewards up to Apple's 90-day ceiling.
  const batch: { id: string; days: number }[] = [];
  let total = 0;
  for (const r of rewards) {
    if (total + r.days > MAX_EXTEND_PER_CALL) break;
    batch.push(r);
    total += r.days;
  }
  if (total === 0) return;

  // Applied-before-calling, reverted on failure — see the idempotency note
  // in the header.
  const ids = batch.map((r) => r.id);
  const now = new Date().toISOString();
  const { error: markErr } = await admin
    .from("referral_rewards")
    .update({ status: "applied", applied_at: now })
    .in("id", ids)
    .eq("status", "banked");
  if (markErr) {
    console.error("reward mark failed:", markErr.message);
    return;
  }

  const ok = await extendRenewal(txId, total);
  if (!ok) {
    await admin
      .from("referral_rewards")
      .update({ status: "banked", applied_at: null })
      .in("id", ids);
    console.log(`extension failed — ${total}d re-banked for`, uid);
    return;
  }
  console.log(`extended ${uid} by ${total}d (${ids.length} reward(s))`);
}

// ------------------------------------------------------------------ serve

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  // Shared-secret auth: the dashboard is configured to send exactly this
  // header value. Accept a "Bearer "-prefixed variant so either dashboard
  // convention works.
  const token = Deno.env.get("REVENUECAT_WEBHOOK_TOKEN");
  const header = req.headers.get("Authorization") ?? "";
  if (!token || (header !== token && header !== `Bearer ${token}`)) {
    return json({ error: "Unauthorized" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "Server is misconfigured" }, 500);
  }
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  let event: Record<string, unknown>;
  try {
    event = (await req.json())?.event ?? {};
  } catch {
    return json({ error: "Invalid body" }, 400);
  }

  // The app logs the RevenueCat identity in as the lowercased Supabase
  // uid (see the App User ID case gotcha in docs/development.md), so a
  // usable id is a UUID. Anonymous ids ($RCAnonymousID:…) mean a user the
  // referral program can't attribute — acknowledged and skipped, because
  // a non-2xx would make RevenueCat retry a permanently unusable event.
  const uid = [event.app_user_id, event.original_app_user_id]
    .map((v) => String(v ?? "").toLowerCase())
    .find((v) => UUID_RE.test(v));
  if (!uid) {
    return json({ skipped: "no attributable user" }, 200);
  }

  const type = String(event.type ?? "");
  const periodType = String(event.period_type ?? "").toUpperCase();
  const isPaid = periodType === "NORMAL" &&
    (type === "INITIAL_PURCHASE" || type === "RENEWAL");
  const isRefund = type === "CANCELLATION" &&
    String(event.cancel_reason ?? "") === "CUSTOMER_SUPPORT";

  let referrerId: string | null = null;
  if (isPaid) {
    // Capture the referrer before conversion flips the row.
    const { data } = await admin
      .from("referral_redemptions")
      .select("referrer_id")
      .eq("invitee_id", uid)
      .is("converted_at", null)
      .maybeSingle();
    referrerId = data?.referrer_id ?? null;
    await handleConversion(admin, uid);
  }
  if (isRefund) {
    await handleRefund(admin, uid);
  }

  // Apply attempts: the event's own subject first (their transaction id is
  // right here in the event), then the referrer this event just rewarded.
  const eventTxId = isPaid && event.original_transaction_id
    ? String(event.original_transaction_id)
    : null;
  await applyBanked(admin, uid, eventTxId);
  if (referrerId && referrerId !== uid) {
    await applyBanked(admin, referrerId, null);
  }

  return json({ ok: true }, 200);
});
