# Buzz Masters — Source Code Audit & Implementation Plan

**Audited commit:** `a70be750f34703d1db05d73f7eede653e9ff3cd3` (`main`)
**Repository:** https://github.com/8cknzcm4b4-gif/com.mycompany.buzzmasters.git
**Method:** read-only inspection of a fresh clone — file/line inventory, targeted source reads, grep sweeps, and a local `flutter test` run. No source file was modified by the audit itself.
**Date:** October 2026

---

## 1. Executive summary

Buzz Masters is a **Flutter app with two disjoint codebases inside one repository**:

1. **`lib/bm/` — the active app** (6,489 LOC). This is what actually runs: a custom shell, menu, practice match, Turbo Trivia Race with a complete pure-Dart rules engine, a time trial with ghost, and a fully written authoritative multiplayer server **that is not connected to anything**.
2. **`lib/pages/` — the FlutterFlow pages** (4,471 LOC, 8 pages). **Unreachable at runtime.** `main()` runs `BuzzMastersApp`, not the FlutterFlow `MyApp` shell, and no file under `lib/bm/` imports a single FlutterFlow page.

The multiplayer game logic is in much better shape than the UI suggests — the hard part (authoritative server rules, protocol, timing) is written and unit-tested. What is missing is **transport, identity, lobby wiring, and a persistent leaderboard**, plus every backend: there is **no network dependency in `pubspec.yaml` beyond `http`**, and **no Supabase/Firestore/API call anywhere in `lib/`**.

---

## 2. Repository state

| Check | Value |
|---|---|
| Branch | `main` |
| HEAD | `a70be750f34703d1db05d73f7eede653e9ff3cd3` |
| Remote | `origin/main`, identical to HEAD at audit time |
| Working tree | clean — 0 modified, 0 untracked, 0 staged |
| Tracked files | 181 |
| FlutterFlow linkage | recorded in `docs/flutterflow-integration.md`; **not independently verifiable** (`GET api.flutterflow.io/v2/projects/buzz-masters-9ci2h7` → `401 Unauthorized`, no `FLUTTERFLOW_API_TOKEN`) |

---

## 3. Code inventory

79 Dart files, **16,009 lines** in `lib/`:

| Area | LOC | Files | Role |
|---|---:|---:|---|
| `lib/bm/` | 6,489 | — | **Active custom app** (design, game, race, screens, settings, widgets) |
| `lib/pages/` | 4,471 | 8 pages | FlutterFlow-generated, **not routed** |
| `lib/flutter_flow/`, `lib/components/`, `main.dart`, `index.dart` | 5,049 | — | FlutterFlow runtime scaffold, retained shell |

FlutterFlow page sizes: `game_lobby` 768 · `question_screen` 645 · `buzzer_round` 581 · `leaderboard` 563 · `final_results` 495 · `settings` 495 · `landing_screen` 487 · `category_selection` 437.

`lib/bm/` structure: `design/` `game/` `race/` (+ `race/authority/`) `screens/` `settings/` `widgets/`.

`lib/bm/race/` totals **3,089 lines across 14 files**.

---

## 4. The architectural split (most important finding)

`lib/main.dart` does:

```dart
runApp(const BuzzMastersApp());   // lib/bm/bm_app.dart
```

The original FlutterFlow shell (`MyApp` + `createRouter` GoRouter + `index.dart` route exports) is **still in the file but never instantiated**, with a comment saying it is retained "so the imported screens and navigation can still be restored by changing the app passed to runApp."

Consequences:

- The 8 FlutterFlow pages — `game_lobby`, `question_screen`, `buzzer_round`, `leaderboard`, `final_results`, `category_selection`, `landing_screen`, `settings` — **cannot be navigated to** in the shipped app.
- `grep` finds **zero** imports of `pages/` from anywhere outside `lib/index.dart`.
- Those pages contain **no backend calls at all**: no `ApiCall`, no Supabase, no Firestore, no `http.` usage. They are static UI.
- The FlutterFlow navigation therefore cannot lead anywhere useful even if re-enabled.

This is not necessarily a defect — it looks deliberate (a custom "reference-matched presentation" replaced the generated UI). But it means **4,471 lines of FlutterFlow work are dead code today**, and any plan must decide whether to revive or retire them.

---

## 5. Active application flow

```
BmWelcomeScreen
  └─ BmMainMenuScreen
       ├─ PLAY NOW / PRACTICE → BmMatchmakingScreen → BmGameplayScreen
       ├─ TURBO RACE         → TurboRaceLobbyScreen
       │     ├─ PRACTICE RACE → RacePracticeScreen   ✅
       │     ├─ TIME TRIAL    → TimeTrialScreen      ✅
       │     ├─ PLAY RACE (ONLINE UNAVAILABLE)       ⛔ disabled
       │     └─ RACE WITH FRIENDS (UNAVAILABLE)      ⛔ disabled
       ├─ PLAY WITH FRIENDS  → snackbar "not implemented yet in this build"
       └─ other menu tiles + bottom tabs (except Settings) → same snackbar
```

Deep-link QA entry: `?screen=menu|lobby|game` (`bm_app.dart`).

`BmMatchmakingScreen` shows a **hardcoded roster** — `['Alex', 'Sophie', 'Jordan', 'Emma', 'Liam', 'Chloe']` — and then pushes the gameplay screen. It is a mock lobby, not matchmaking.

---

## 6. Feature-by-feature status

| Feature | Status | Evidence |
|---|---|---|
| **Six-player race lobby** | ⛔ Shell only | `turbo_race_lobby_screen.dart` renders 6 seat cards, all labelled "Open seat"; both networked buttons have `onPressed: null` |
| **Practice mode** | ✅ Implemented | `race_practice_screen.dart` (590 LOC) drives `RaceModel` locally with the 32-question bank |
| **Time trial (solo + ghost)** | ✅ Implemented | `time_trial_screen.dart` (549), `time_trial.dart` (119), `time_trial_store.dart` persists best ghost per distance in `shared_preferences` |
| **Countdown** | ✅ Implemented | `countdown_badge.dart` (70), `RaceConfig.countdownSeconds = 3`, phases `waiting → countdown → racing` |
| **Questions** | ✅ Implemented (local) | 32 `QuizQuestion(...)` entries in `lib/bm/game/practice_match.dart` (859 LOC); option shuffling in `RaceServer` |
| **Buzzer mechanics** | ✅ in `lib/bm`, ⛔ in pages | `practice_match.dart` has buzzer logic (tap to buzz, re-open on wrong answer); the FlutterFlow `buzzer_round` page is unreachable |
| **Race rules / scoring** | ✅ Implemented + pure | `race_model.dart` (335 LOC): distance 100, +10 correct / +15 fast (≤3000 ms), −5 wrong, −3 timeout, danger zone ≤10, 1 grace question, 30-question cap, deterministic rankings with id tie-break |
| **Authoritative race server** | ✅ Written + tested, ⛔ unwired | `authority/race_server.dart` (327), `race_protocol.dart` (262), `race_session.dart` (142). Intent-only wire protocol (no client-trusted progress), injectable clock. **Imported by `test/` only — no production import, no transport** |
| **Leaderboard** | ⚠️ Local only | `results_screen.dart` ranks the current match's contestants (`correct ✓ / wrong ✗`); the FlutterFlow `leaderboard` page is unreachable and there is no persistence beyond time-trial ghosts |
| **Persistent leaderboard** | ⛔ Missing | no backend, no DB writes (only `shared_preferences` for ghosts) |
| **Matchmaking / friends** | ⛔ Missing | hardcoded names; `Private friend lobbies` shows the "not implemented" snackbar |
| **Accounts / auth** | ⛔ Missing | `welcome_screen.dart` tells the user email accounts "need the Buzz Masters backend (Supabase auth)" — an honest placeholder, not an integration |

### Menu items that are stubs

`main_menu_screen.dart` routes every tile other than `PRACTICE` and `TURBO RACE`, and every bottom tab other than Settings, to `_notBuilt(...)` — a snackbar reading *"<feature> is not implemented yet in this build."* Also `PLAY WITH FRIENDS`.

---

## 7. Backend & real-time readiness

| Check | Result |
|---|---|
| `pubspec.yaml` networking deps | `http: 1.4.0` (via `dependency_overrides`) only |
| WebSocket / socket / realtime package | **none** |
| Supabase / Firebase package | **none** |
| API/DB calls in `lib/` | **zero matches** for `ApiCall`, `supabase`, `firestore`, `BackendApi`, `http.` |
| Local persistence | `shared_preferences` (time-trial ghosts), `sqflite` (declared, no evidence of race use) |
| What a real-time race needs | authenticated transport (WebSocket), server-hosted session, question bank + answers held server-side, seat/lobby state, reconnect + spectate, persistent leaderboard |

**Required for real-time multiplayer:**

1. **Transport** — a WebSocket (or HTTP long-poll) client in Flutter, plus a server that hosts `RaceServer`.
2. **Identity** — the protocol already states "the transport is responsible for authenticating that identity"; that does not exist yet.
3. **Lobby** — replace the hardcoded roster with live seats; wire the six seat cards to join/leave events.
4. **Question authority** — questions and correct options must leave the client. Today `RaceServer` is constructed with the client's own question list.
5. **Reconnect / spectate** — `RaceModel.spectating()` exists; reconnection after transport loss does not.
6. **Persistent leaderboard** — a table keyed by player, written at `results`.

---

## 8. Assets & dependencies

`assets/` contains **11 files**:

- Real: `images/bm_logo.png`, `images/bm_hero.png`, `fonts/Poppins-Bold.ttf`, `fonts/Poppins-SemiBold.ttf`
- Placeholder: a `favicon.png` sitting in `audios/`, `jsons/`, `rive_animations/`, `videos/`, `pdfs/`, `fonts/`
- **No audio files** — consistent with `race_sound.dart`, which deliberately uses platform system sounds ("the app needs no audio plugin")
- `assets/videos/`, `pdfs/`, `jsons/`, `rive_animations/` folders are declared in `pubspec.yaml` but hold nothing meaningful

**Dependencies:** FlutterFlow's standard set (`go_router`, `google_fonts`, `lottie`, `flutter_animate`, `provider`, `shared_preferences`, `sqflite`, `url_launcher`, `cached_network_image`, …). No game-net library, no Supabase, no Firebase. `dependency_overrides` pins `font_awesome_flutter`, `http`, `intl`, `page_transition`, `uuid`, `webview_flutter`.

`pubspec.yaml` carries a Firebase/GenUI-related `flutter.config` comment, but there is no Firebase dependency — that block is inherited template configuration, not an integration.

---

## 9. Test suite

13 files in `test/`: `race_model_test`, `race_server_test`, `race_session_test`, `race_practice_screen_test`, `race_settings_pause_test`, `race_effects_test`, `practice_match_test`, `time_trial_test`, `time_trial_screen_test`, `turbo_race_lobby_test`, `settings_screen_test`, `bm_audio_settings_test`, `widget_test`.

The presence of `race_server_test` and `race_session_test` is the strongest signal in the repo: **the authoritative server is exercised by tests but not by the app.**

**Result (run on this audit): `flutter test` → exit 0, 58/58 passed, 0 failures, 00:02:04.**

| | |
|---|---|
| `flutter pub get` | exit 0 (`Got dependencies!`, 53 outdated-but-compatible packages) |
| `flutter test` | **exit 0 — `+58: All tests passed!`** |
| Tests run | 58 across the 13 files above |
| Failures / errors | 0 |
| Wall time | ~2 min 4 s of test time (plus a one-off ~2 GB Flutter engine cache re-download after the disk cleanup) |

This is the first green run recorded on this machine: the two earlier attempts died on `No space left on device` while the disk was at 100%. After the Tier A cleanup (11 GiB free) the suite compiles and passes as-is, with **no source change required** — the code was never broken, only unverifiable.

---

## 10. Can Floot support this game?

**Honest answer: Floot cannot reuse the Flutter code, and a Floot version would be a rebuild of the UI and a port of the logic.**

Evidence-based comparison (Floot overview guide fetched live during this audit):

| Dimension | Buzz Masters today (Flutter) | Floot |
|---|---|---|
| Language / UI | Dart + Flutter widgets | **TypeScript + React 19** (native builds via Capacitor) |
| Code reuse | — | **0% of the Dart UI is reusable.** React Native/Expo packages explicitly cannot run in Floot |
| Rules engine | `RaceModel` + `RaceServer` + protocol, pure Dart, unit-tested | Would be **re-written in TypeScript** — mechanical but non-trivial (335 + 327 + 262 + 142 = **1,066 lines** of tested logic) |
| Real-time | **Missing** — no transport at all | **Built in**: `@floot/realtime` (broadcast + presence), plus Postgres, auth, storage, scheduled jobs |
| Backend | Missing entirely | Provisioned: Postgres (postgres-js + kysely), endpoints (GET/POST only, 15-min limit), `queueTask`, cron |
| Hosting / builds | Manual Flutter build, TestFlight/Play toolchain | Hosting, publishing, iOS/Android builds handled |
| Fit for 6-player race | Needs everything from scratch | Needs everything from scratch too — realtime is *room broadcast*, not a game server; authoritative tick logic still has to be written |

**Implication:** the choice is not "reuse vs rebuild" — it is *where to write the missing backend*.

- **Supabase (stays in Flutter):** keeps the existing 16k LOC, the tested race server, and the FlutterFlow repo. Adds Postgres + Realtime + Auth via `supabase_flutter`; `RaceServer` can be hosted in a Supabase Edge Function or kept client-hosted with server validation. **Least new code, preserves GitHub as source of truth.**
- **Floot (rebuild in React):** gains hosting/auth/realtime/leaderboard immediately, but discards the Flutter UI and requires porting the 1,066-line rules/authority core to TypeScript. Buzz Masters would become a web app (optionally wrapped for app stores).

**Recommendation: stay on Flutter + Supabase for Phase 1–3.** The expensive asset is the tested pure-Dart race core, and Supabase lets you keep it. Floot becomes attractive only if you decide the Flutter app itself is a dead end — and §4 (4,471 unreachable FlutterFlow lines) is worth resolving before making a platform bet in either direction.

---

## 11. Prioritised implementation plan

### Phase 0 — Decide the split (do first, cheap)
1. **Resolve the FlutterFlow pages**: retire them, or rewire `runApp` to the FlutterFlow shell. Leaving 4,471 unreachable lines in the source of truth costs review effort and confuses every future audit.
2. ~~Re-run `flutter test`~~ — **done, 58/58 green** (see §9). Treat that as the regression baseline for every later phase.

### Phase 1 — Make one player's race trustworthy
3. Wire `RacePracticeScreen` and `TimeTrialScreen` to the **same `RaceServer` path** the networked game will use, so the single-player code and multiplayer code cannot diverge.
4. Move the question bank out of the client for the networked path (server-held options/answers).

### Phase 2 — Platform & backend (Supabase recommended, see §10)
5. Provision Supabase: `profiles`, `matches`, `match_players`, `leaderboard` tables + RLS.
6. Auth (email/OTP) — replaces the placeholder string in `welcome_screen.dart`.
7. Host `RaceServer` server-side (Edge Function or a small authoritative service) with WebSocket transport.

### Phase 3 — Multiplayer
8. Transport + identity → 9. Lobby seats replace the hardcoded `['Alex', 'Sophie', …]` roster → 10. Reconnect + spectate → 11. Persistent leaderboard → 12. Enable the two disabled lobby buttons and `Private friend lobbies`.

### Phase 4 — Content & polish
13. Expand beyond the 32-question bank.
14. Populate or drop the empty `videos/`, `pdfs/`, `jsons/`, `rive_animations/` asset folders and their stray `favicon.png` placeholders.

---

## 12. What is missing (consolidated)

- Any network transport or backend (no WebSocket, no Supabase, no API calls)
- Identity / authentication
- Live lobby and matchmaking (hardcoded bot names)
- Persistent leaderboard
- Server-held question bank for networked play
- Reconnection after transport loss
- Wiring of the tested `authority/` server into any screen
- Reachability of all 8 FlutterFlow pages
- Audio assets (deliberate — system sounds are used), plus 4 empty declared asset folders
