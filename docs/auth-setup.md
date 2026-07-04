# Auth setup (Supabase + Apple + Google)

SleepBlock gates the app behind sign-up/sign-in right after onboarding
(`AuthView.swift`), backed by a real [Supabase](https://supabase.com) project.
Sleep data itself stays local-first (see `product-brief.md`) — this only adds
account identity on top. This doc is the one-time external setup a developer
does before the app can authenticate against something real. Without it, the
app still builds and runs (see `Config.xcconfig.example`); auth calls just
fail with a network/config error until real values are in place.

## 1. Create the Supabase project

1. Go to [supabase.com](https://supabase.com) → New project.
2. Once created, open **Project Settings → API**. Copy:
   - **Project URL** (`https://<project-ref>.supabase.co`)
   - **anon / public** API key (not the `service_role` key — never ship that
     one client-side)
3. Copy `ios/SulavSleep/Config.xcconfig.example` to
   `ios/SulavSleep/Config.xcconfig` (gitignored) and fill in
   `SUPABASE_URL` / `SUPABASE_ANON_KEY` with those two values.

Email/password auth is enabled by default on a new Supabase project —
"Manual" sign-up/sign-in needs no further Supabase configuration.

## 2. Enable Sign in with Apple

SleepBlock uses the **native** Apple flow
(`ASAuthorizationAppleIDProvider` → Supabase's `signInWithIdToken`), so no
Apple config is needed on the Supabase side — only in the Apple Developer
portal and Xcode:

1. [developer.apple.com](https://developer.apple.com) → **Certificates,
   Identifiers & Profiles → Identifiers** → select the app's App ID
   (`com.sulav.sleepblock` or whatever it's registered as).
2. Under **Capabilities**, enable **Sign In with Apple** → Save.
3. In Xcode, the `SulavSleep.entitlements` file already declares
   `com.apple.developer.applesignin`; just make sure the target's signing
   team matches the Apple Developer account from step 1, then let Xcode
   re-sync the entitlement (Signing & Capabilities tab → the "Sign In with
   Apple" capability should show no warning).

That's it — no Services ID, no private key, no redirect URL, because the
identity token is verified by Supabase server-side against Apple's public
keys once we hand it the native token.

## 3. Enable Google sign-in

SleepBlock uses Supabase's OAuth web flow (`ASWebAuthenticationSession`) for
Google, not the Google SDK, so setup lives entirely in Google Cloud Console +
the Supabase dashboard:

1. [console.cloud.google.com](https://console.cloud.google.com) → create/
   select a project → **APIs & Services → Credentials → Create Credentials →
   OAuth client ID**.
2. Application type: **Web application** (not iOS — the iOS SDK isn't used
   here).
3. Under **Authorized redirect URIs**, add:
   `https://<project-ref>.supabase.co/auth/v1/callback`
4. Save, copy the generated **Client ID** and **Client secret**.
5. In the Supabase dashboard: **Authentication → Providers → Google** →
   paste the Client ID/secret → Enable → Save.
6. In the Supabase dashboard: **Authentication → URL Configuration →
   Redirect URLs** → add `sleepblock://auth-callback` (this is the app's
   custom URL scheme, already registered in `Info.plist`).

With that, tapping "Continue with Google" in the app opens a system sheet,
the user signs in with Google, and Supabase redirects back into the app via
`sleepblock://auth-callback`.

## 4. Account deletion (Edge Function)

The Settings sheet has a **Delete account** button. Deleting a Supabase user
can't be done from the app (that needs the `service_role` key, which must never
ship client-side), so it goes through a server-side Edge Function that runs with
the service role and deletes the caller's own user. Deleting the `auth.users`
row cascades to any table with an `ON DELETE CASCADE` foreign key to it, so this
removes everything the user owns. Today SleepBlock is local-first (sleep history
lives on-device), so the auth user is the only server record; the app wipes the
on-device data itself once the server delete succeeds.

The function lives at `supabase/functions/delete-account/index.ts`. To deploy:

1. Install the [Supabase CLI](https://supabase.com/docs/guides/cli) and log in:
   `supabase login`.
2. From the repo root, link to your project (uses the `<project-ref>` from your
   Project URL): `supabase link --project-ref <project-ref>`.
3. Deploy: `supabase functions deploy delete-account`.
   - `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are
     injected automatically for deployed functions — you do **not** set any
     secret by hand.
4. The client calls `POST <project-url>/functions/v1/delete-account` with the
   user's access token; no app config beyond the existing `SUPABASE_URL` /
   `SUPABASE_ANON_KEY` is needed.

If you later add user-owned tables, either give their foreign key to
`auth.users` `ON DELETE CASCADE`, or delete those rows explicitly inside the
function before the user delete.

**Until this function is deployed, the Delete account button will fail** with an
error alert (the account is not touched) — it does not silently sign out.

## Verifying it all works

1. Build and run via `./scripts/run-ios-simulator.sh`.
2. Onboard fresh (or reset from Settings), and confirm the new sign-up/
   sign-in screen appears right after onboarding.
3. Try each path: Apple (native sheet), Google (web sheet), and Manual
   (email/password sign-up, then sign-in).
4. Force-quit and relaunch — the app should skip both onboarding and auth
   (session restored from Keychain via `supabase-swift`).
