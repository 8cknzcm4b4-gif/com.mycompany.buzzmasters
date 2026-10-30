# Buzz Masters backend — Firebase

Project **`buzz-masters-race`** ("Buzz Masters", Google account
wiggle.support@gmail.com). Firestore and Cloud Functions in **London
(europe-west2)**. Supabase is no longer used; its last version is on branch
`backup/pre-firebase-20261030`.

## Status (2026-10-30)

| Piece | State | Evidence |
|---|---|---|
| Firebase project, iOS/Android/web apps registered | **Done** | `firebase.json`, `lib/firebase_options.dart`, `GoogleService-Info.plist`, `google-services.json` |
| Firestore database (europe-west2) | **Created** | `firestore:databases:create` |
| Security rules | **Deployed** (deny-by-default; clients read only their own data) | `firebase deploy --only firestore:rules`; 5 rule tests pass on the emulator |
| Indexes, Cloud Functions, Storage | **Blocked — Blaze plan not enabled yet** | deploy refused: "billing disabled" |
| Firebase Authentication | **Blocked — not started in the console** | Auth config API: `CONFIGURATION_NOT_FOUND` |
| Race engine (server-authoritative) | **Built and tested** | `functions/test/engine.test.ts` (14) |
| API on Firestore transactions | **Built and tested on the emulator** | `functions/test/api.test.ts` (14) |
| RevenueCat + AdMob verification | **Built and tested** | `functions/test/verification.test.ts` (6) |
| App ↔ server view contract | **Tested** (7 race phases match field for field) | `test/online/room_view_test.dart` |

```sh
cd functions && npm install
npm run test:unit       # engine + purchase/ad verification
npm run test:emulator   # API + security rules (needs Java 11+ for the emulator)
```

## Layout

| Path | Who can read | Who writes |
|---|---|---|
| `players/{uid}` (+ `notifications`, `devices`) | the player | Functions |
| `rooms/{id}` — the public race state | its racers | Functions |
| `rooms/{id}/secret/state` — questions with answers, all answers | nobody | Functions |
| `rooms/{id}/mine/{uid}` — the player's own answer | the player | Functions |
| `leaderboards/{all\|m-YYYY-MM\|w-YYYY-MM-DD}/rows/{uid}` | signed-in players | Functions |
| `entitlements`, `wallets` (+ `ledger`), `inventory`, `purchases`, `adRewards` | the player | Functions |
| `tournaments/{id}` (published/live/closed) / `entries/{uid}` | signed-in / the player | Functions |
| `questions`, `friendLinks`, `friendCodes`, `invites`, `blocks`, reports, `raceResults`, `questionHistory`, `rateLimits`, `storeEvents`, `auditLogs` | nobody | Functions |

## Functions (`functions/src`)

| Function | Called by | Does |
|---|---|---|
| `apiCall` | the app (signed in) | rooms, Quick Race, ready, start, answers, friends, invites, block, report, rankings, history, notifications, daily reward, equip, tournaments |
| `syncPurchases` | the app after purchase/restore | asks RevenueCat with the secret key what the player owns; records exactly that |
| `deleteAccount` | the app | erases the player's data, anonymises past races, deletes the auth user |
| `revenuecatWebhook` | RevenueCat | constant-time shared secret; grant / renew / expire / refund, once per event |
| `admobSsv` | Google AdMob | ECDSA signature check against Google's keys; coins once per ad, daily cap |
| `pushNotification` | Firestore trigger | FCM for friend requests, invites and results |
| `adminSummary` | users with the `monetisation_admin` claim | counts only; revenue comes from the store reports |

**Server-authoritative racing:** the engine (`engine.ts`) is a direct port of
the rules proven on PostgreSQL earlier. Each action runs in a Firestore
transaction, so simultaneous answers, joins and ticks never conflict, and a
race finishes — and its rankings are written — exactly once. Questions are
published only once they open and never with their answer. The app watches
`rooms/{id}` live and calls the server only to act, every 5 s as a heartbeat,
and when a timer is due (`lib/bm/online/room_view.dart`).

**Anti-cheat and abuse:** answers are judged on the server clock; one answer
per question; leaving forfeits; rate limits on lobbies (20/h), joins
(60/10 min), friend requests (30/h), invites (60/h) and reports (10/day);
blocking keeps players apart in lobbies, invites and Quick Race.

**App Check:** activated in the app (App Attest / DeviceCheck, Play
Integrity; debug providers in debug builds). Enforcement is off until the apps
are registered in Firebase → App Check; then set `ENFORCE_APP_CHECK=true` in
`functions/.env` and redeploy.

## To go live (needs your console access)

1. **Blaze plan**: Firebase console → Usage and billing → Blaze; add a budget
   alert.
2. **Authentication → Get started**, then enable **Anonymous**,
   **Email/Password**, **Google** (one click) and **Apple** (needs your Apple
   Services ID and key).
3. Secrets (never in git):

   ```sh
   firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET --project buzz-masters-race
   firebase functions:secrets:set REVENUECAT_SECRET_API_KEY --project buzz-masters-race
   ```

4. Deploy and seed:

   ```sh
   firebase deploy --only firestore,functions,storage --project buzz-masters-race
   cd functions && GOOGLE_APPLICATION_CREDENTIALS=… npm run seed   # or rely on the built-in bank
   ```

5. RevenueCat webhook URL:
   `https://europe-west2-buzz-masters-race.cloudfunctions.net/revenuecatWebhook`;
   AdMob SSV URL: `https://europe-west2-buzz-masters-race.cloudfunctions.net/admobSsv`.
6. In Google Cloud → APIs & Services → Credentials, restrict the three
   Firebase API keys to their apps (bundle id / package / web domain).
