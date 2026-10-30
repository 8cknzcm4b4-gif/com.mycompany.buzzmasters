# Buzz Masters — App Store release readiness

Status as of 2026-10-30, branch `dev`. **Not ready to submit**: the app's
code side is in place, but signing, the backend project and store
credentials are not, and TestFlight cannot be produced on this Mac.

## 1. What is verified, and how

| Check | Result | How |
|---|---|---|
| Static analysis | 0 errors; `lib/bm`, `test`, `tool` clean | `flutter analyze` |
| Flutter tests | 237 / 237 | `flutter test` |
| Server tests (real PostgreSQL 16 via PGlite) | 28 / 28 | `cd supabase/tests && npm test` |
| Layout on iPhone SE 1st gen (320 pt) → 16 Pro Max (440 pt) | 68 / 68 screens, no overflow | `test/layout_sizes_test.dart` |
| Web release build | succeeds | `flutter build web --release` |
| Real browser journey (release build) | complete, 0 console errors | `screenshots/redesign/browser-journey-log.txt` |
| iOS release build | **not possible here** — Xcode not installed (`xcodebuild` needs full Xcode) | `flutter build ios` → "Application not configured for iOS" |
| Android release build | **not possible here** — no Android SDK | `flutter build appbundle` |

## 2. App Store compliance checklist

| Requirement | Status |
|---|---|
| App icon (original, opaque 1024 px, all sizes) | ✅ done — `tool/icon/` regenerates it; was the Flutter logo |
| Launch screen | ✅ arena navy + icon (iOS storyboard, Android drawable) |
| Privacy manifest (`PrivacyInfo.xcprivacy`) | ✅ filled: no tracking; user id, email, gameplay, purchase history for app functionality; UserDefaults reason CA92.1 |
| Privacy policy | ✅ in-app (Settings → Privacy Policy). ⚠️ App Store Connect also needs a **public URL**: host the same text and enter it. Have it reviewed for your jurisdiction. |
| Support contact | ⚠️ set `--dart-define=BM_SUPPORT_EMAIL=…` and the Support URL in App Store Connect |
| Account deletion (5.1.1(v)) | ✅ Settings → Account → Delete; server purge tested on Postgres (`account.test.mjs`); erase-device-data works offline. Live deletion needs the backend deployed. |
| Sign in with Apple when Google is offered (4.8) | ✅ both offered; ⚠️ needs Apple Services ID/key in Supabase |
| In-app purchases | ✅ prices only from the store; restore in VIP screen; entitlements now **server-verified** (RevenueCat webhook + sync). ⚠️ needs RevenueCat project, App Store Connect products and secrets |
| Rewarded ads | ✅ coins only after Google SSV signature check (server). ⚠️ needs production AdMob ids + SSV URL |
| AdMob app id in native config (launch crash otherwise) | ✅ added — iOS `GADApplicationIdentifier` via `ADMOB_APP_ID` (Flutter/*.xcconfig), Android meta-data via `admobAppId`. **Defaults are Google's TEST ids — replace before release.** |
| App Tracking Transparency | ✅ not needed: the app does not track (`NSPrivacyTracking` false, no IDFA prompt). If you later want personalised ads, add ATT + `NSUserTrackingUsageDescription`. |
| Export compliance | ✅ `ITSAppUsesNonExemptEncryption = false` (standard HTTPS only) |
| Permissions / purpose strings | ✅ none needed: no camera, photos, location or microphone use |
| Minimum iOS | iOS 15.0 (Podfile + project) — fine for all dependencies |
| Bundle id | ❌ `com.mycompany.buzzmasters` is a placeholder. Choose your real id, register it in your Apple Developer account, and update it in the iOS and Android projects (and FlutterFlow). |
| Signing | ❌ no Apple team set (`DEVELOPMENT_TEAM`). Android release now uses `android/key.properties` when present (never committed). |
| Age rating / content | Trivia, no user-generated content beyond racing names (16 chars) — answer the questionnaire accordingly |
| Screenshots for the listing | Use the 6.9" / 6.5" sizes from a device or simulator; browser captures in `screenshots/redesign/` show the content |

## 3. App Store privacy "nutrition label" (matches the manifest)

- **Data linked to you, used for app functionality:** User ID, Email
  address (only when signed in with email/Apple/Google), Gameplay content
  (race results), Purchase history.
- **Not used for tracking.** Google AdMob's own SDK declares its data in its
  bundled privacy manifest; review Google's guidance when answering the
  advertising questions.

## 4. External blockers (need your accounts or approval)

1. **Buzz Masters Supabase project** — create it, apply the four migrations
   in `supabase/migrations`, deploy the five Edge Functions, set secrets (see
   `docs/multiplayer-backend.md`). The only project reachable here belongs to
   another app and was not touched.
2. **Apple Developer** — team id for signing, bundle id, Sign in with Apple
   Services ID + key, App Store Connect app record, IAP products.
3. **RevenueCat** — project, public SDK keys, secret API key and webhook
   secret (server only).
4. **AdMob** — production app ids (iOS and Android), rewarded unit id, SSV URL.
5. **A Mac with Xcode** (and Android Studio) — to build, sign and upload to
   TestFlight. Nothing was uploaded.
6. **FlutterFlow** — see `docs/flutterflow-integration.md`. The project
   exports with your saved token, but it does not contain this app.

## 5. Release commands (once the above exist)

```sh
flutter build ipa --release \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable key> \
  --dart-define=REVENUECAT_PUBLIC_API_KEY=<appl_ public key> \
  --dart-define=ADMOB_REWARDED_AD_UNIT_ID=<ios rewarded unit> \
  --dart-define=BM_SUPPORT_EMAIL=<support address>
# ios/Flutter/Release.xcconfig: ADMOB_APP_ID = <production iOS app id>
# then upload build/ios/ipa/*.ipa with Xcode Organizer or Transporter
```
