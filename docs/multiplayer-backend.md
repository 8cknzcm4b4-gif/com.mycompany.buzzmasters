# Online multiplayer, accounts and leaderboards — setup and status

## Status (2026-10-30)

| Piece | State | Evidence |
|---|---|---|
| Server rules (rooms, 6 seats, server-judged answers, timers, danger zone, results) | **Built and tested on PostgreSQL 16** | `supabase/tests` — 14/14 pass |
| Friends, invites and the global leaderboard (server) | **Built and tested on PostgreSQL 16** | same suite |
| Flutter client (lobby, live race, friends, leaderboard, resume, sign-in) | **Built and tested** | `flutter test` — 166/166 pass |
| Running against a real Buzz Masters Supabase project | **Blocked — no project exists** | see below |
| Apple / Google sign-in | **Code ready; blocked on credentials** | see below |

### Why it is not live yet

The only Supabase project reachable from this workspace
(`azafjqjbvklajsplykyv`) belongs to a **different application** (tables
`wiggles`, `heat_*`, `community_posts`, …). Buzz Masters must not share it,
so nothing was applied there. The connector cannot create a new project.
A branch of that project would copy the other app's schema.

## How it works

- Everything lives in `supabase/migrations/20261030000100_multiplayer.sql`.
  Clients cannot read or write any table (RLS on, no client policies);
  they call `bm_*` RPCs as the `authenticated` role.
- **Server-authoritative:** the database clock times every question. The
  server judges answers against a question bank that clients never see
  (they get only text and options). It applies +15 / +10 / −5 / −3 and the
  danger zone, and ranks the field. One-answer-per-question is enforced by a
  primary key.
- **No game server process is needed:** each state read or answer calls
  `race_tick()`, which applies due transitions (countdown → racing →
  timeout → reveal → next question → finish) under a row lock. Clients poll
  every 0.7 s in a race and every 1 s in a lobby.
- **Disconnects:** a silent racer simply times out on each question.
  Reconnecting resumes from server state ("Resume last session" asks the
  server via `bm_my_live_room`). Leaving mid-race forfeits; if everyone
  leaves, the race is abandoned. Lobbies expire after 30 minutes.
- **Accounts:** players start with an anonymous session, so online play
  needs no sign-up. Apple, Google or email *link* to that same user, so
  races and friends carry over.

## Setup (needs your accounts)

1. **Create a dedicated project** at supabase.com (e.g. "buzz-masters").
2. **Apply migrations**, in order: `supabase/migrations/20261029000100_monetisation.sql`,
   then `20261030000100_multiplayer.sql` (SQL editor, or `supabase db push`).
3. **Authentication → Providers → Anonymous sign-ins: enable.**
   **Authentication → Settings → Allow manual linking: enable** (for
   guest → Apple/Google/email upgrades).
4. **Redirect URLs** (Authentication → URL Configuration):
   add `buzzmasters://buzzmasters.com/login-callback` (already registered
   in `ios/Runner/Info.plist` and `AndroidManifest.xml`) and your web URL.
5. **Apple:** Apple Developer → an App ID with "Sign in with Apple", a
   Services ID, and a key. Enter Team ID, Services ID, Key ID and the .p8
   key in Supabase → Providers → Apple.
6. **Google:** Google Cloud → an OAuth client (Web), with the Supabase
   callback URL as an authorised redirect. Enter the client ID and secret in
   Supabase → Providers → Google.
7. **Build with the project keys** (the public publishable key only):

   ```sh
   flutter run -d chrome \
     --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
     --dart-define=SUPABASE_ANON_KEY=<publishable key>
   ```

   Without these defines the app runs offline and says so on every online
   screen.

## Verify locally

```sh
cd supabase/tests && npm install && npm test   # migrations on real Postgres 16 (PGlite)
flutter test                                   # client, incl. online journeys
```

## Security finding in the earlier monetisation migration (not yet applied)

`monetisation_grant_ad_reward(p_account_id, …, p_signature_valid, …)` and
`monetisation_record_purchase(p_account_id, …)` are `SECURITY DEFINER` and
executable by any signed-in client. They trust the caller's account id and
the caller's claim that an advert reward or purchase is genuine. As written,
**any player could grant coins or VIP to any account**. The fix is to move
those two calls server-side: a RevenueCat webhook and AdMob server-side
reward verification, implemented as Edge Functions using the service role.
Then revoke client execute and add `p_account_id = auth.uid()::text` checks
to the remaining client RPCs. Both webhooks need your RevenueCat webhook
secret and AdMob SSV configuration. Do not enable real purchases or rewards
before this is done.

The client side was aligned in this change: with a server configured, the
monetisation account id is now the signed-in Supabase user, which the RLS
policies (`auth.uid() = account_id`) require. Before, it was a random local id
that the policies would always have rejected.
