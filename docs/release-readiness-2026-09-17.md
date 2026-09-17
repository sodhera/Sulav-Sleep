# SleepBlock conversion update: release readiness

The iOS change is in draft PR [#1](https://github.com/sodhera/Sulav-Sleep/pull/1).
It includes the illustrated blocking preview, shorter and clearer setup,
persistent onboarding draft, consented funnel analytics, and subscription
event ledger. The deliberate 1.8-second plan reveal and current paywall
headline remain. Generic iOS Debug and Release compile checks pass for the app
and all four extensions; `git diff --check` also passes. The Release compile
used explicit non-production placeholders for values that are intentionally
not committed. No simulator was launched.

The privacy policy source was updated in `sodhera/orecci` commit `57e4e94`.
GitHub reports a successful Production deployment for that commit. It now
describes existing profile/session cloud sync and the new optional analytics.

## Live status and remaining sequence

1. Migrations `009_product_events.sql`, `010_subscription_events.sql`, and
   `011_onboarding_remote_variants.sql` are live. Direct production probes
   confirm both event tables exist, anonymous reads are denied, the analytics
   insert path reaches the event-name constraint, and the iOS config row is
   `concise` / `twilight`. The deliberately invalid insert was rejected and
   did not persist.
2. The `revenuecat-webhook` endpoint is live and rejects requests without its
   shared secret. An authorized RevenueCat test event or real sandbox purchase
   must still confirm that the deployed function writes `subscription_events`;
   trial starts must not count as paid conversions.
3. Supply the local Release configuration. `SUPABASE_URL` and
   `SUPABASE_ANON_KEY` are set; `REVENUECAT_API_KEY`, `APPLE_APP_ID`,
   `TIKTOK_APP_ID`, and `TIKTOK_ACCESS_TOKEN` remain intentionally absent from
   the gitignored local file. A production archive needs the real values.
4. Review and update App Store Connect privacy answers to match the manifest,
   policy, and actual third-party SDK behavior. The new first-party events are
   optional but may become account-linked after sign-in; they are not
   anonymous. Check device ID, product interaction, purchase history, user ID,
   and the app's existing account, sleep, and advertising disclosures.
5. After those steps and real-device purchase/Screen Time checks, prepare the
   app build for review. App Store submission is outside this task.

`docs/conversion-funnel.sql` is the cohort query. Its denominator is opted-in
installs, not all App Store downloads, and its paid stage comes only from the
RevenueCat webhook ledger.
