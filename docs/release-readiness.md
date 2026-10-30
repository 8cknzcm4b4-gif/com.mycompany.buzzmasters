# Buzz Masters — App Store release readiness

Status as of 2026-10-30, branch `dev`. **Not ready to submit.** The code is
built and tested, but the backend is not deployed, nothing is signed, and the
store and ad accounts are not connected. Every critical item marked FAIL or
BLOCKED below must pass first.

PASS = verified here · FAIL = defect or missing work · BLOCKED = needs an
account, credential or tool this machine does not have.

## 1. Verification

| Check | Result | Evidence |
|---|---|---|
| Static analysis | PASS — 0 errors; `lib/bm`, `test`, `tool` clean (remaining notes are style hints in the unused FlutterFlow pages in `lib/pages`) | `flutter analyze` |
| Flutter tests | PASS — 243 / 243 | `flutter test` |
| Backend tests, all 5 migrations in order on PostgreSQL 16 (PGlite) | PASS — 39 / 39 | `cd supabase/tests && npm test` |
| Layout, iPhone SE 1st gen (320 pt) → 16 Pro Max (440 pt) | PASS — 68 / 68 screens, no overflow | `test/layout_sizes_test.dart` |
| Web release build | PASS | `flutter build web --release` |
| iOS release build | BLOCKED — Xcode not installed (Command Line Tools only) | `flutter build ios --release --no-codesign` → "Application not configured for iOS" |
| Android release build | BLOCKED — no Android SDK | `flutter build appbundle` |
| Truly simultaneous answers from separate connections | BLOCKED offline — PGlite is a single connection. Duplicate answers are refused by a primary key and row locks serialise answers; verify under load on the deployed project. | `multiplayer.test.mjs` |

## 2. Services

| Service | Status | Found on this Mac | Next action |
|---|---|---|---|
| GitHub | PASS | `gh` signed in as the repo owner; `dev` pushed | — |
| Supabase | BLOCKED | CLI runs but is not logged in; the connector here is bound to another app's project (left untouched) | `npx supabase@2.54.11 login`, create "buzz-masters" (London) in BUZZ MASTERS, then `tool/supabase/deploy.sh <ref>` |
| Apple Developer / App Store Connect | BLOCKED | no signing identities, provisioning profiles or App Store Connect API keys; no team id anywhere | choose the bundle id, register it, set the team in Xcode, create the App Store Connect record |
| Sign in with Apple | BLOCKED | code ready (Supabase OAuth); provider disabled in `supabase/config.toml` until keys exist | Services ID + key → Supabase Apple provider |
| Google Sign-In | BLOCKED | code ready; no Google Cloud login or OAuth client for Buzz Masters | OAuth client (Web) → Supabase Google provider |
| Google Play Console | BLOCKED | no Play credentials, no upload keystore | create the app, upload key in `android/key.properties` (git-ignored) |
| RevenueCat | BLOCKED | no account access, keys or webhook secret | create the app, entitlement `vip`, products; set the secrets in Supabase |
| AdMob | FAIL until replaced | native config uses **Google's test app ids** | production app ids in `ios/Flutter/Release.xcconfig` and `-PadmobAppId`, rewarded unit via `--dart-define`, SSV URL → `admob-ssv` |
| FlutterFlow | BLOCKED (not a sync target) | key valid; project `buzz-masters-9ci2h7` exports a different, older app; API is export-only | build and release from this repository |

## 3. App Store compliance

| Requirement | Status |
|---|---|
| App icon (original, opaque 1024 px, all sizes) | PASS — `tool/icon/` |
| Launch screen | PASS — arena navy + icon |
| Privacy manifest (`PrivacyInfo.xcprivacy`) | PASS — no tracking; user id, email, gameplay, purchase history for app functionality; UserDefaults CA92.1 |
| Privacy policy in app | PASS — Settings → Privacy Policy |
| Public privacy policy URL, support URL/email | BLOCKED — host the text; set `--dart-define=BM_SUPPORT_EMAIL=…`; have it reviewed for your jurisdiction |
| Account deletion (5.1.1(v)) | PASS in code and on Postgres (incl. blocks, reports, history, notifications); live deletion needs the backend deployed |
| Sign in with Apple offered alongside Google (4.8) | PASS in UI; BLOCKED on keys |
| User-generated content (names) — report and block (1.2) | PASS — report and block players (Friends), report questions (in race), server rate limits |
| In-app purchases and restore | PASS in code (server-verified entitlements); BLOCKED on RevenueCat/App Store Connect products |
| Rewarded ads | PASS in code (server SSV check); FAIL until production AdMob ids |
| App Tracking Transparency | PASS — not needed (no tracking, no IDFA prompt). Add ATT if you later want personalised ads. |
| Export compliance | PASS — `ITSAppUsesNonExemptEncryption = false` |
| Permissions / purpose strings | PASS — none needed |
| Minimum iOS | PASS — iOS 15.0 |
| Bundle id | FAIL — `com.mycompany.buzzmasters` is a placeholder; change it in iOS, Android and FlutterFlow once chosen |
| Signing | BLOCKED — no Apple team (`DEVELOPMENT_TEAM` unset), no certificates |
| Listing screenshots | BLOCKED — need a simulator/device (Xcode) |

## 4. App Store privacy "nutrition label" (matches the manifest)

- **Data linked to you, used for app functionality:** User ID, Email
  address (only when signed in with email/Apple/Google), Gameplay content
  (race results), Purchase history, and Other user content (reports you
  send).
- **Not used for tracking.** Google AdMob's SDK declares its own data in its
  bundled privacy manifest; review Google's guidance for the advertising
  questions.

## 5. Next actions, in order

1. `npx supabase@2.54.11 login`; create the Buzz Masters project; run
   `tool/supabase/deploy.sh <ref>`; set the Edge Function secrets; review the
   advisors.
2. Choose the real bundle id; register it with Sign in with Apple; create
   the App Store Connect record and IAP products; RevenueCat app and keys.
3. AdMob: production app ids and rewarded unit; SSV callback
   `https://<ref>.supabase.co/functions/v1/admob-ssv`.
4. Host the privacy policy; set the support email.
5. On a Mac with Xcode: set the team, then

```sh
flutter build ipa --release \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable key> \
  --dart-define=REVENUECAT_PUBLIC_API_KEY=<appl_ public key> \
  --dart-define=ADMOB_REWARDED_AD_UNIT_ID=<ios rewarded unit> \
  --dart-define=BM_SUPPORT_EMAIL=<support address>
# ios/Flutter/Release.xcconfig: ADMOB_APP_ID = <production iOS app id>
```

6. Upload to TestFlight only after your approval.
