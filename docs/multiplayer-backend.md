# Online multiplayer, accounts and leaderboards — setup and status

## Status (2026-10-30)

| Piece | State | Evidence |
|---|---|---|
| Server rules (rooms, 6 seats, server-judged answers, timers, danger zone, results) | **Built and tested on PostgreSQL 16** | `supabase/tests` |
| Friends, invites, blocking, reports, question moderation | **Built and tested on PostgreSQL 16** | `community.test.mjs` |
| Readiness, public lobbies / Quick Race, question rotation | **Built and tested on PostgreSQL 16** | `community.test.mjs` |
| All-time, monthly and weekly rankings; race history; notifications | **Built and tested on PostgreSQL 16** | `community.test.mjs` |
| Rate limits (lobbies, joins, friend requests, invites, reports) | **Built and tested on PostgreSQL 16** | `community.test.mjs` |
| Realtime room signals (RLS: members only) | **Built; SQL side tested** — the Supabase Realtime server itself is not available offline | `community.test.mjs` |
| Flutter client (lobby, ready-up, Quick Race, live race, report question, friends with block/report, ranking periods) | **Built and tested** against an in-memory server with the same rules | `flutter test` |
| Running against a real Buzz Masters Supabase project | **Blocked — the Supabase CLI is not logged in and the connector here is bound to another app** | see below |
| Apple / Google sign-in | **Code ready; blocked on credentials** | see below |

All migrations run in order in every suite (`npm test`: 39 tests).

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

1. **Create a dedicated project** in the BUZZ MASTERS organisation
   (e.g. "buzz-masters", London region).
2. **Log in and deploy** (one guarded script: it refuses the other app's
   project, runs the tests, shows the pending migrations and asks before
   applying, pushes the auth settings in `supabase/config.toml`, and
   deploys the four Edge Functions):

   ```sh
   npx supabase@2.54.11 login
   tool/supabase/deploy.sh <project-ref>
   ```

   `supabase/config.toml` enables anonymous sign-ins and manual linking
   (guest → Apple/Google/email upgrades) and sets the redirect URL
   `buzzmasters://buzzmasters.com/login-callback` (already registered in
   `ios/Runner/Info.plist` and `AndroidManifest.xml`). Add your web URL too
   if you host the web build.
3. Run **Advisors → Security / Performance** in the dashboard and review.
4. **Apple:** Apple Developer → an App ID with "Sign in with Apple", a
   Services ID, and a key. Enter Team ID, Services ID, Key ID and the .p8
   key in Supabase → Providers → Apple.
5. **Google:** Google Cloud → an OAuth client (Web), with the Supabase
   callback URL as an authorised redirect. Enter the client ID and secret in
   Supabase → Providers → Google.
6. **Build with the project keys** (the public publishable key only):

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

## Community and moderation (20261030000400)

| RPC | What it does | Limits |
|---|---|---|
| `bm_create_room(p_public)` / `bm_create_room()` | private by default; public lobbies are listed for Quick Race | 20 per hour |
| `bm_join_room(code)` | refuses a lobby containing someone who blocked you, or whom you blocked | 60 per 10 min |
| `bm_quick_join()` | resumes your live room, else the fullest open public lobby without blocked players, else opens one | — |
| `bm_set_ready(room, ready)` | lobby readiness; the host counts as ready; `all_ready` in the state | lobby only |
| `bm_block_player` / `bm_unblock_player` / `bm_blocked_players` | blocking ends the friendship and pending invites; friend requests to a blocker look like an unknown code | — |
| `bm_report_player(target, reason, details, room)` | `offensive_name`, `cheating`, `harassment`, `other`; one open report per pair | 10 reports per day |
| `bm_report_question(room, index, reason, details)` | by question number in a race you are in; question ids never reach clients; 3 reporters flag it `needs_review` | same daily cap |
| `bm_leaderboard_period('all'\|'month'\|'week', limit)` | rankings for the UTC period (weeks start Monday) | — |
| `bm_race_history(limit)`, `bm_notifications(limit)`, `bm_mark_notifications_read()` | your own results and notifications (friend requests, acceptances, invites, results) | 30-day retention |

**Question rotation:** a race takes the questions its racers have seen least
in the last 14 days. The bank now has 60 questions, so two races in a row
share none.

**Realtime:** `race_room_signals` (one row per room, a version number) and
`player_notifications` are in the `supabase_realtime` publication. RLS lets
only room members / the owner read them. The app subscribes and refetches the
server-built state on each change; polling stays as the fallback and drives
the timers. Polls only touch `last_seen`, which deliberately does **not**
signal, or every client would refetch in a loop (tested).

**Account deletion** removes all of the above through `ON DELETE CASCADE`
(tested).

**Not stored on the server:** avatars or profile images (the app uses a
racing colour, so no storage bucket is needed) and achievements, which the
app derives on the device from the player's own stats.

## Edge Functions (purchases, ads, account deletion)

| Function | Called by | Verifies | JWT |
|---|---|---|---|
| `revenuecat-webhook` | RevenueCat | `Authorization` = `REVENUECAT_WEBHOOK_SECRET` (constant-time) | `--no-verify-jwt` |
| `revenuecat-sync` | the app after purchase/restore | the player's JWT; asks RevenueCat with `REVENUECAT_SECRET_API_KEY` | default |
| `admob-ssv` | Google AdMob | ECDSA signature against Google's published keys | `--no-verify-jwt` |
| `delete-account` | the app | the player's JWT, then purges and deletes the auth user | default |

```sh
supabase functions deploy revenuecat-webhook --no-verify-jwt
supabase functions deploy admob-ssv --no-verify-jwt
supabase functions deploy revenuecat-sync
supabase functions deploy delete-account
supabase secrets set REVENUECAT_WEBHOOK_SECRET=… REVENUECAT_SECRET_API_KEY=… \
  AD_REWARD_COINS=50 AD_REWARD_MAX_PER_DAY=5
```

Their logic lives in `supabase/functions/_shared/*.ts` and is tested in
`supabase/tests/functions.test.mjs` (including a real ECDSA signature in
Google's format and webhook → Postgres → VIP end to end).

## Security finding in the earlier monetisation migration — FIXED

`monetisation_grant_ad_reward(p_account_id, …, p_signature_valid, …)` and
`monetisation_record_purchase(p_account_id, …)` are `SECURITY DEFINER` and
executable by any signed-in client. They trust the caller's account id and
the caller's claim that an advert reward or purchase is genuine. As written,
**any player could grant coins or VIP to any account**. The fix is to move
those two calls server-side: a RevenueCat webhook and AdMob server-side
reward verification, implemented as Edge Functions using the service role.
Then revoke client execute and add `p_account_id = auth.uid()::text` checks
to the remaining client RPCs. **Fixed in `20261030000200_monetisation_security.sql`** and proven on
Postgres: `monetisation.test.mjs` first reproduces the exploit against the
original migration, then shows it closed. The same migration fixes the bundle
grant loop, which failed every bundle purchase (`column "g" does not exist`).

The client side was aligned in this change: with a server configured, the
monetisation account id is now the signed-in Supabase user, which the RLS
policies (`auth.uid() = account_id`) require. Before, it was a random local id
that the policies would always have rejected.
