# Buzz Masters — release readiness

Status as of 2026-10-30, branch `dev`. **Not ready for TestFlight.** The app
and its Firebase backend are built and tested, but the backend functions are
not deployed (Blaze plan off), Firebase Authentication is not started, and
nothing is signed. Every FAIL / BLOCKED item below must pass first.

PASS = verified here · FAIL = defect or missing work · BLOCKED = needs an
account, approval or tool this machine does not have.

## 1. Verification

| Check | Result | Evidence |
|---|---|---|
| Static analysis | PASS — 0 errors; `lib/bm`, `test`, `tool` clean (remaining notes are style hints in the unused FlutterFlow pages in `lib/pages`) | `flutter analyze` |
| Flutter tests | PASS — all pass (see the commit message for the count) | `flutter test` |
| Functions unit tests (race engine, RevenueCat, AdMob) | PASS — 20 / 20 | `cd functions && npm run test:unit` |
| Functions on the Firestore emulator (API + security rules) | PASS — 19 / 19, incl. six simultaneous answers and a finish ticked by six racers at once | `npm run test:emulator` |
| App view = server view (7 race phases) | PASS | `test/online/room_view_test.dart` |
| Layout, iPhone SE 1st gen (320 pt) → 16 Pro Max (440 pt) | PASS — 68 / 68 screens, no overflow | `test/layout_sizes_test.dart` |
| Web release build | PASS | `flutter build web --release` |
| Real browser journey (release build, live Firebase project) | PASS — welcome → join → settings → leaderboard → how to play → every tab → full practice race → podium → VIP → shop → classic → time trial. Only failed requests: anonymous sign-up (Auth not started) and one function not yet deployed | `screenshots/firebase/` |
| iOS release build | BLOCKED — Xcode not installed (Command Line Tools only) | "Application not configured for iOS" |
| Android release build | BLOCKED — no Android SDK | `flutter build appbundle` |

## 2. Services

| Service | Status | Next action |
|---|---|---|
| GitHub | PASS — `dev` pushed | — |
| Firebase project `buzz-masters-race` | PASS — created; iOS, Android and web apps registered; Firestore (europe-west2) created; security rules deployed | — |
| Cloud Functions, indexes, Storage | BLOCKED — Blaze plan not enabled ("billing disabled") | enable Blaze, then `firebase deploy --only firestore,functions,storage` |
| Firebase Authentication | BLOCKED — not started ("CONFIGURATION_NOT_FOUND") | console → Authentication → Get started; enable Anonymous, Email/Password, Google, Apple |
| Sign in with Apple | BLOCKED — code ready; needs Apple Services ID + key in Firebase | Apple Developer account |
| Google Sign-In | BLOCKED — code ready; one click in Firebase once Auth is started; Android also needs the SHA-1/256 of your signing key | add fingerprints in Firebase project settings |
| App Check | Code PASS (App Attest/DeviceCheck, Play Integrity); enforcement off | register the apps in Firebase → App Check, then `ENFORCE_APP_CHECK=true` |
| Push (FCM) | Code PASS (asked in context, on Friends); delivery NOT TESTED | upload an APNs key (Apple Developer) to Firebase |
| RevenueCat | BLOCKED — no account access, keys or webhook secret | create the app; set the two secrets; webhook URL in `docs/firebase-backend.md` |
| AdMob | FAIL until replaced — native config uses Google's **test** ids | production ids; SSV URL → `admobSsv` |
| Apple signing / App Store Connect | BLOCKED — no team, certificates or API key on this Mac | bundle id, team, App Store Connect record, IAP products |
| Google Play | BLOCKED — no Play Console access or upload key | create the app; `android/key.properties` (git-ignored) |
| FlutterFlow | NOT A SYNC TARGET — project `buzz-masters-9ci2h7` holds an older, different app; API is export-only | build and release from this repository |

## 3. App Store compliance

| Requirement | Status |
|---|---|
| App icon, launch screen | PASS |
| Privacy manifest (`PrivacyInfo.xcprivacy`) | PASS — no tracking; user id, email, gameplay, purchases, other user content (reports) |
| Privacy policy in app | PASS; public URL BLOCKED (host it; set `BM_SUPPORT_EMAIL`) |
| Account deletion (5.1.1(v)) | PASS in code and on the emulator (`deleteAccount`); live once Functions deploy |
| Sign in with Apple alongside Google (4.8) | PASS in UI; BLOCKED on keys |
| Email + password, password reset | PASS in code (Firebase Auth); live once Auth is started |
| Report / block for user content (1.2) | PASS |
| In-app purchases and restore | PASS in code (server-verified); BLOCKED on RevenueCat / App Store Connect |
| Rewarded ads | PASS in code (server SSV); FAIL until production AdMob ids |
| App Tracking Transparency | PASS — not needed (no tracking) |
| Export compliance | PASS — `ITSAppUsesNonExemptEncryption = false` |
| Bundle id | FAIL — `com.mycompany.buzzmasters` is a placeholder (Firebase apps are registered with it; add the real one when chosen) |
| Signing | BLOCKED |

## 4. Next actions, in order

1. Firebase console → **Usage and billing → Blaze** (with a budget alert).
2. Firebase console → **Authentication → Get started**; enable Anonymous,
   Email/Password, Google; Apple once you have its keys.
3. `firebase deploy --only firestore,functions,storage --project buzz-masters-race`
   (see `docs/firebase-backend.md` for secrets and webhook URLs).
4. Choose the real bundle id; Apple team, App Store Connect record, IAP
   products; RevenueCat; production AdMob ids.
5. On a Mac with Xcode: set the team, `flutter build ipa --release`, upload to
   TestFlight — only after your approval.
