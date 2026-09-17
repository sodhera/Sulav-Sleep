# SleepBlock conversion update: release readiness

The iOS change is in draft PR [#1](https://github.com/sodhera/Sulav-Sleep/pull/1).
It includes the illustrated blocking preview, shorter and clearer setup,
persistent onboarding draft, consented funnel analytics, and subscription
event ledger. The deliberate 1.8-second plan reveal and current paywall
headline remain. The generic iOS Debug build and `git diff --check` pass;
no simulator was launched.

The privacy policy source was updated in `sodhera/orecci` commit `57e4e94`.
GitHub reports a successful Production deployment for that commit. It now
describes existing profile/session cloud sync and the new optional analytics.

## Live sequence before distribution

1. Grant the company deployment account access to the linked SleepBlock
   Supabase project. On September 17, the current Supabase CLI account returned
   HTTP 403 for migration and function-list operations. Do not substitute one
   of the other visible projects.
2. Apply migrations `009_product_events.sql`, `010_subscription_events.sql`,
   and `011_onboarding_remote_variants.sql` in order. Check `product_events`
   insert-only RLS and service-role-only `subscription_events` access.
3. Deploy `revenuecat-webhook` and verify its shared-secret configuration and
   a RevenueCat test event. A confirmed paid event must appear in
   `subscription_events`; trial starts must not count as paid conversions.
4. Supply the local Release configuration. `SUPABASE_URL` and
   `SUPABASE_ANON_KEY` are set; `REVENUECAT_API_KEY`, `APPLE_APP_ID`,
   `TIKTOK_APP_ID`, and `TIKTOK_ACCESS_TOKEN` are missing. The Release build
   currently fails its intentional guard at the first missing key.
5. Review and update App Store Connect privacy answers to match the manifest,
   policy, and actual third-party SDK behavior. The new first-party events are
   optional but may become account-linked after sign-in; they are not
   anonymous. Check device ID, product interaction, purchase history, user ID,
   and the app's existing account, sleep, and advertising disclosures.
6. After those steps and real-device purchase/Screen Time checks, prepare the
   app build for review. App Store submission is outside this task.

`docs/conversion-funnel.sql` is the cohort query. Its denominator is opted-in
installs, not all App Store downloads, and its paid stage comes only from the
RevenueCat webhook ledger.
