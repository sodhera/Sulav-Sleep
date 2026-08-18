# Roadmap: Sleep partner + referral

Status: **shipped, then re-architected** (August 2026). This doc records the
original v1 spec below (fused referral + partner, single partner). It was
superseded during the build — see the v2 note next — so read the v2 note
first; the v1 text is kept for the decision trail, not as current behavior.
`docs/development.md` and DESIGN.md carry the current maintenance and screen
rules.

## v3 — pairing codes (current, August 2026)

v2's partner invite link had a hole that only shows up in the field: a
`sleepblock://` URL resolves for nobody who doesn't already have the app.
There's no associated-domains entitlement, so no Universal Link and no App
Store fallback; most messengers won't even linkify a custom scheme, so it
often arrives as dead grey text. The sender gets no signal that any of this
happened.

v3 adds a **6-character pairing code** (migration 008) and makes it the
lead affordance, with the link demoted to a tertiary "copy a link instead".

Why a code fixes it: nothing has to survive the install. "Get SleepBlock,
then enter 4KM9PX" works whether or not the app is there yet, and it works
*spoken* — across a kitchen table, over a phone call — which is the common
case for sleep partners (roommates, couples, the friend you're actually
accountable to). The share message bundles Apple's own App Store URL with
the code, so none of this needs a domain or a web page of ours.

**Explicitly rejected: a permanent per-user ID / username.** It was the
first idea, and it's the wrong shape here:

- A fixed handle is guessable and forever, so anyone could type it at you.
  That forces back the pending/confirm step v2 deliberately deleted, and
  hands every user a request queue to triage.
- What a partner sees is bed and wake time — a schedule of when a home is
  unattended. Not something to gate behind a guessable, permanent name.
- It drags in uniqueness at signup, squatting, renames, moderation of
  offensive handles, and a lookup RPC that becomes an enumeration oracle
  over the user base.

Temporary codes keep v2's auto-confirm honest instead: one use, 24 hours
(not 10 minutes — the recipient may need to install and sign up first),
plus the one thing links never needed, **server-side rate limiting**, since
a live 6-character space is brute-forceable in a way a 96-bit token isn't.

One structural consequence worth knowing before editing 008:
`redeem_partner_code` **returns** `{ok, name, error}` rather than raising.
A raise aborts the transaction, which would roll back the very attempt row
the rate limiter counts — a raising function cannot rate-limit itself.
`accept_partner_invite` (the link path) is untouched and still raises.

QR was considered and cut. It would have worked — scanned from *inside*
the app it can carry any payload, no domain needed — but it's a second
in-person mechanism next to a code that already covers in-person, and it
costs a camera permission and a scanner view.

Everything below is v2, still accurate except that the invite link is no
longer the primary way in.

## v2 — referral and partnership decoupled

v1 fused the two: the only way to get a sleep partner was to redeem
someone's referral code. Two problems surfaced immediately:

1. It capped everyone at one partner (the code is one-per-account).
2. An **already-paid** user couldn't become anyone's partner — they can't
   meaningfully redeem a code, so two existing subscribers had no way to
   connect at all.

They're really orthogonal intents — *refer* a coworker (give them a free
month, share nothing) versus *partner* with a friend (see each other's
sleep, no money involved) — so v2 splits them into two features that share
nothing:

- **Referral** is unchanged from v1's growth half: a code, 30 free nights
  for the referee, a banked free month for the referrer on conversion.
  `redeem-referral` no longer files a partnership (migration 006).
- **Sleep partner** is now its own thing: a **partner invite link**
  (`sleepblock://partner/<token>`, minted by `create_partner_invite`,
  accepted by `accept_partner_invite`) that anyone can send to anyone
  regardless of subscription. Accepting auto-confirms — both sides
  consented, the owner by making the link, the tapper by opening it — so
  there is **no pending/confirm step** (v1's consent card is gone). Safety
  is single-use + 7-day expiry + instant unilateral unlink. **Multiple
  partners**, capped at 10.

UI moved too: the partner card left Profile for a dedicated
**Sleep Partners** screen behind a Home top-right button; the referral kept
its Settings "Invite a friend" row and paywall redeem link, de-partnered to
pure "give a free month". The free-nights **ending nudge** and **expiry
paywall headline** (v1's conversion mechanics) are unchanged.

Everything below is the original v1 spec, superseded by the above.

---

# v1 spec (superseded)

Status: **planned — being built now** (August 2026). This doc is the spec;
when the build lands, `docs/development.md` carries the maintenance-facing
version and DESIGN.md the screen rules. Written the way
`roadmap-lockdown-and-widget.md` was: decisions with reasons, so a future
reader knows what was deliberate.

## The one-sentence version

Invite a friend to be your **sleep partner**: they get **30 free nights**
instead of 7, you see each other's streak and schedule, and when they
subscribe you get **a month free** — one code, one flow, both halves.

## Why this shape

The referral and the partner feature are deliberately **one program, not
two**, because each fixes the other's weakness:

- A bare referral code is a coupon; asking someone to install an app for a
  discount is an awkward text to send. "Do this with me — we'll see each
  other's streaks" is a reason that isn't money.
- A bare partner feature has no growth engine. The referral reward gives
  the inviter a second reason to actually send the invite.

The reward economics (settled in discussion, worth restating):

- **Referee: 30 free nights, granted app-side.** They aren't being billed
  yet, so no Apple billing machinery is involved — this is a row in our
  database and a lock exemption in the app, exactly like the offline grace
  period. It deliberately does **not** touch the App Store intro offer:
  the 7-night trial remains available and Apple's own eligibility rules
  apply independently.
- **Referrer: 30 days per conversion, banked, applied as a real renewal
  extension.** The reward triggers on the referee's **first paid
  transaction** (trial starts don't count), because that is the moment
  fraud dies: faking it costs ~3× more than the reward is worth.
  RevenueCat "promotional entitlements" are NOT usable here — they grant
  access but don't stop Apple billing an active subscriber, so a paying
  user would get nothing. The only genuine free month for an active
  subscriber is `extendSubscriptionRenewalDate` on the App Store Server
  API, which needs a server-held Apple key (see Setup).
- **Cap: 180 banked days per rolling 365** — six months. Not arbitrary:
  Apple limits renewal extensions to **90 days per call, two calls per
  subscription per year**, so 180/365 is the physical ceiling anyway.
  Rewards accrue in a ledger and are applied in batches of ≤90 days; a
  referrer with more banked days than applicable keeps the balance.

### Rules (product-level)

1. Every account owns at most one referral code (created lazily). Codes
   are 6 chars from `23456789ABCDEFGHJKMNPQRSTUVWXYZ` (no 0/O/1/I/L).
2. An account can **redeem** at most one code, ever. You cannot redeem
   your own. Redemption grants `free_until = now() + 30 days` —
   server-dated, so a device clock rollback buys nothing.
3. Redemption also files a **pending partnership** (invitee → inviter).
   The inviter must **confirm** before any stats are shared in either
   direction. Consent is explicit even though the inviter shared the code
   — codes leak, and sleep data is sensitive.
4. Sharing is **symmetric or nothing**: a confirmed partnership makes both
   summaries readable to both sides; there is no one-way mode.
5. One **confirmed** partner at a time (v1). The code stays multi-use for
   *referrals* regardless — extra redemptions still grant nights and bank
   rewards; they just can't become partnerships while a slot is full.
6. Either side can **unlink** at any time, unilaterally, effective
   immediately. Unlinking never claws back referral rewards.
7. What a partner sees: **streak count, avg bedtime, avg wake, avg
   duration, nights counted, display name** — derived numbers over the
   last 7 logged nights (the app-wide `SleepStats.recentWindow`), never
   raw sessions. The summary row is written by its owner on each cloud
   sync; raw `sleep_sessions` rows never cross accounts.
8. Referrer reward voids if the qualifying purchase is refunded before
   the reward is applied. Applied extensions are not clawed back (Apple
   has no API for it, and clawing back a delivered reward is hostile).

## Schema (migration 005)

Five tables, all RLS-on, following 001's owner-only pattern except where
the whole point is a controlled cross-account read:

```
referral_codes      user_id uuid PK → auth.users (cascade)
                    code text UNIQUE not null
                    created_at
  RLS: owner SELECT. Writes only via RPC/service role.

referral_redemptions
                    invitee_id uuid PK → auth.users (cascade)   -- one redemption per account, by PK
                    referrer_id uuid not null → auth.users (cascade)
                    code text not null
                    free_until timestamptz not null             -- the 30 nights
                    converted_at timestamptz                    -- set by webhook on first paid event
                    redeemed_at timestamptz default now()
  RLS: invitee SELECT own row (the app reads free_until from it);
       referrer SELECT rows where referrer_id = auth.uid() (Settings
       "invited friends" count). Writes only via edge function.

referral_rewards    id uuid PK default gen_random_uuid()
                    referrer_id uuid not null → auth.users (cascade)
                    redemption_invitee_id uuid UNIQUE not null  -- one reward per conversion
                    days int not null default 30
                    status text not null default 'banked'       -- banked | applied | void
                    applied_at timestamptz
                    created_at timestamptz default now()
  RLS: referrer SELECT own. Writes only via webhook (service role).

partnerships        id uuid PK default gen_random_uuid()
                    inviter_id uuid not null → auth.users (cascade)
                    invitee_id uuid not null → auth.users (cascade)
                    status text not null default 'pending'      -- pending | confirmed
                    created_at, confirmed_at
                    UNIQUE (inviter_id, invitee_id); CHECK (inviter_id <> invitee_id)
  RLS: both members SELECT. status changes via RPCs only.

partner_summaries   user_id uuid PK → auth.users (cascade)
                    name text, streak int, streak_dying bool,
                    avg_bed_minutes int, avg_wake_minutes int,
                    avg_duration_minutes int, nights int,
                    updated_at timestamptz default now()
  RLS: owner ALL; partner SELECT iff a *confirmed* partnership joins
       auth.uid() and user_id (either direction). This policy is the
       feature's entire privacy model — the only cross-account read
       in the app.
```

RPCs (`security definer`, so the invariants live server-side, not in app
code): `get_or_create_referral_code()`, `confirm_partnership(id)` (fails
if either side already has a confirmed one — the single-slot rule),
`decline_partnership(id)`, `unlink_partnership(id)`.

## Edge functions

**`redeem-referral`** (verify_jwt = true, same identity pattern as
delete-account): caller sends `{ code }`. Validates: code exists, not the
caller's own, caller has no prior redemption. Service-role writes the
redemption (+ pending partnership when possible) and returns
`{ free_until }`. All failures are distinct, user-facing messages.

**`revenuecat-webhook`** (verify_jwt = false; authenticated instead by a
shared secret in the `Authorization` header, configured on both ends —
RevenueCat's dashboard and a Supabase secret). Flow per event:

1. Reject unless the header token matches `REVENUECAT_WEBHOOK_TOKEN`.
2. Identify the event's `app_user_id` (= Supabase user id, lowercased —
   the case gotcha in development.md applies here too).
3. **Conversion detection**: an event whose `period_type` is `NORMAL`
   (first non-trial, non-intro payment — `INITIAL_PURCHASE` or the
   `RENEWAL` that converts a trial) for a user who has an unconverted
   redemption row → set `converted_at`, insert a `banked` reward for the
   referrer (skipped if it would breach the 180/365 cap).
4. **Refund voiding**: `CANCELLATION` with a refund reason for a
   converted invitee → void that invitee's still-banked reward.
5. **Application attempt**: for any event, if the affected user (and, on
   conversions, the referrer) has banked rewards and an active paid
   subscription, batch up to 90 days and call
   `PUT /inApps/v1/subscriptions/extend/{originalTransactionId}` with an
   ES256 JWT signed by the App Store Connect In-App Purchase key. The
   `originalTransactionId` comes from the webhook event itself when the
   user is the event's subject, else from RevenueCat's REST API
   (`GET /v1/subscribers/{app_user_id}`, `REVENUECAT_SECRET_KEY`).
   Success → mark applied; failure → leave banked, retried on the next
   event. Piggybacking retries on webhook traffic means no cron.

Idempotency: RevenueCat retries deliveries, so every step is written to
be replay-safe (PK/UNIQUE constraints make double-inserts no-ops;
`converted_at` guards re-conversion; the extension call is the one
non-idempotent step, so the reward row is flipped to `applied` *before*
acknowledging, and Apple's own 2-per-year limit backstops a worst-case
double-apply).

## iOS

**Service seam** (`SleepReferral.swift`, the `CloudSyncing` pattern):
`ReferralSyncing` protocol + Supabase impl + disabled stub. Calls:
`myCode()`, `redeem(code:)`, `myRedemption()` (for `free_until` +
converted state), `invitedFriends()` (count + converted count),
`partnerState()` (pending requests + confirmed partner + their summary),
`confirm/decline/unlink`, `upsertMySummary(_:)`.

**Store** (`SleepStore`):

- `referralFreeUntil: Date?`, loaded on sign-in/foreground, cached in
  `SleepPersistence` (`sulav.referralFreeUntil.v1`, cleared on sign-out —
  the grant belongs to the account). `isWithinReferralNights` gates on
  the *server-issued* date; the cache only bridges offline launches.
- `isLocked` grows the third exemption:
  `notEntitled && !offlineGrace && !referralNights`. Everything else —
  `needsPaywall`, `presentPaywallIfLocked`, the primer — inherits it for
  free, which is the payoff of having made `isLocked` the single truth.
- Partner state (`partner`, `pendingPartnerRequests`, `partnerSummary`)
  refreshed alongside the existing cloud restore/foreground sync.
- `upsertMySummary` fires wherever sessions sync today (after
  `startSleep`'s persist → cloud push, wake, Health import) — derived
  from the same `streak` and `SleepStats.averages` the Profile band uses,
  so partner and Profile can never disagree.

**UI** (DESIGN.md gets the full grammar; the shape):

- **Paywall**: a quiet "Have a referral code?" text button above the
  footer → glass sheet, one code field, redeem. Success flips the lock
  (`isLocked` recomputes off the new `free_until`) and the route falls
  through to Main — the referred user's first impression is the app, not
  a wall.
- **Profile root**: a **Sleep partner** card between the sleep section
  and settings. Empty → one-line pitch + "Invite" (share sheet: code +
  App Store link) and "I have a code". Pending (inviter) → confirm /
  decline row with the requester's name. Linked → partner's name, their
  streak flame, avg bed/wake, avg duration next to yours. Unlink lives
  behind the card's detail, deliberately un-prominent.
- **Settings**: the Subscription group gains a **referral status row**
  while on referral nights ("Free nights · N left"), and an **Invite a
  friend** row ("1 month free when they subscribe") that shares the code.
- Locked users can invite too — their reward banks and applies when they
  themselves subscribe. No reason to gate generosity on payment.

## What is deliberately NOT in v1

- No push notifications about the partner (no "they're still up", no
  broken-streak alerts). The quiet version ships first; noise is easy to
  add and impossible to un-ship.
- No multi-partner. One slot keeps the card, the RLS, and the mental
  model singular.
- No in-app messaging, reactions, or free text between partners — which
  is also what keeps the App Review UGC surface at "a display name".
- No Android (goes on `docs/android.md` phase-2; the schema is shared, so
  Android is client work only).
- No deferred-deep-link attribution SDK. The code is typed by a human.

## External setup (owner: Sulav — the code can't do these)

1. Supabase: run migration 005; deploy both functions; set secrets
   `REVENUECAT_WEBHOOK_TOKEN` (any long random string),
   `REVENUECAT_SECRET_KEY` (RevenueCat → API keys → secret),
   `ASC_ISSUER_ID`, `ASC_KEY_ID`, `ASC_PRIVATE_KEY` (App Store Connect →
   Users and Access → Integrations → In-App Purchase key, the .p8
   contents), `APP_BUNDLE_ID`.
2. RevenueCat dashboard: add the webhook URL
   (`…/functions/v1/revenuecat-webhook`) with the same Authorization
   token value.
3. Nothing in App Store Connect changes — the intro offer stays as is.

## Testing reality

- Migration + RPCs: exercisable via SQL locally.
- Edge functions: deployable and smoke-testable with curl (the doc's
  payload examples); the **Apple extension call cannot be tested without
  the real key and a sandbox subscription** — it ships behind the banked
  ledger precisely so a failed call loses nothing.
- iOS: simulator runs in dev mode (everyone entitled), so lock-exemption
  paths are unit-reasoned + device-tested; the partner card and code
  sheet get DEBUG preview args (`-review-partner`, `-review-referral`)
  in the `-review-paywall` tradition.

## Sequencing

1. Plan (this doc) → 2. migration → 3. edge functions → 4. iOS service +
store → 5. iOS UI → 6. docs + build. Each its own commit. The program is
inert until the external setup lands, which makes shipping the code ahead
of the dashboard config safe.
