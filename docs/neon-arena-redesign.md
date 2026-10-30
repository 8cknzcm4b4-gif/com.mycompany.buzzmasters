# Neon Turbo Quiz Arena — redesign, repair and verification

Branch `dev`, on top of `409b895`. Backup of the pre-change state: branch
`backup/pre-repair-20261029` (= `409b895`).

## Why earlier updates never appeared in the app

1. **`main()` does not run the FlutterFlow screens.** `lib/main.dart` calls
   `runApp(const BuzzMastersApp())` (`lib/bm/`). The welcome screen with
   "Join Game / Get Started / Resume Last Session / ROOM #882-104" is
   FlutterFlow's `lib/pages/landing_screen`, which this source never routes
   to, and its room number is hard-coded text.
2. **FlutterFlow is not connected to this repository.** The FlutterFlow API
   returns `401 Unauthorized` (no token in this workspace), and
   `docs/flutterflow-integration.md` records that the GitHub integration was
   never switched on. A build made from FlutterFlow (Test Mode, Run, or its
   App Store deploy) compiles FlutterFlow's own copy of the project, so it
   shows the old FlutterFlow pages and none of the work in `lib/bm/`.
3. Local `dev`, `origin/dev` and `origin/main` were identical (`409b895`), so
   GitHub already had every earlier change. No iOS or Android build had ever
   been produced from this source on this machine (`build/` held only test
   caches).
4. **Every release build of this source was failing.** `shop_screen.dart`
   built `IconData` at runtime, which breaks icon tree-shaking, so
   `flutter build web|ios|apk --release` stopped with "Avoid non-constant
   invocations of IconData". Fixed in this change.

**To see this work you must build from this repository** (instructions
below), or connect FlutterFlow to GitHub (FlutterFlow → Settings →
Integrations → GitHub) and pull `dev`. Note that FlutterFlow's visual editor
does not display hand-written code under `lib/bm/`.

## What changed

- **Design system** (`lib/bm/design`, `lib/bm/widgets`): midnight-navy,
  ultraviolet, neon-cyan and gold palette; bundled Rajdhani display face
  (SIL OFL); glass panels; pressable buttons with haptics; an animated arena
  backdrop (gold lighting halo, crowd tiers, spotlights, perspective runway).
  Every screen, including VIP / Shop / Rewards / Tournaments / Admin,
  inherits it.
- **Race presentation** (`lib/bm/race/race_arena.dart`): six-lane
  perspective neon track; original painted racing pods positioned by
  confirmed race progress; exhaust trails that scale with speed; scrolling
  lane markings that accelerate in the final stretch; a chequered finish
  arch; danger-zone pulses; +/− score pops; "▲ P2" overtakes; a live
  position board whose rows slide on every overtake; start-light countdown;
  FINISH flash; animated podium ceremony (`widgets/race_podium.dart`).
- **Screens**: new animated splash, welcome, dashboard with five working
  tabs, race lobby with six lit podiums, Join Game, joined-lobby view,
  leaderboard, player profile with achievements, friends, How to Play, and
  settings (sound, music, haptics).
- **Gameplay fixes**: every racer used to start inside the ≤10 danger zone,
  so most of the field was eliminated by question 2–3. The shipped config
  `kTurboRaceConfig` now has a 3-question safe start; the engine default is
  unchanged, so the authoritative server and its tests behave as before.
  Answers give instant correct/incorrect feedback (glow / shake + sound).
  Finished races are recorded to a persistent on-device player profile.
  Rematch was added.
- **Sound**: original synthesised cues plus a looping arena track
  (`assets/audios/sfx/`), all following the Sound and Music toggles.
- **Navigation repairs**: the welcome icons (info, leaderboard, settings),
  Get Started, Resume, every dashboard tab, and the Join / Practice / Time
  Trial entry points all lead to real screens. Removed the "not implemented
  yet" snackbar tiles (Daily Quiz, Themed Quizzes, Ranked Play, which had no
  screen). Added a quit control to the Classic Show match (previously a dead
  end) and accessible "Back" labels on the monetisation screens.
- **Web fixes**: AdMob is reported as unavailable on web, where it has no SDK
  (it was throwing `MissingPluginException`); added the missing
  `web/manifest.json`.

## Honest limits (need you, not code)

| Blocked | Exact reason | What unblocks it |
|---|---|---|
| Online races, Join by code, Resume, friends, global leaderboard | Built on Firebase (`buzz-masters-race`); see `docs/firebase-backend.md`. Live once the Blaze plan is enabled and the Cloud Functions are deployed. | Enable Blaze; deploy Functions. |
| Apple / Google / email sign-in | Built on Firebase Authentication; not started in the console yet | Start Authentication; enable providers; Apple Services ID / key |
| Real purchases | No RevenueCat public key | `--dart-define=REVENUECAT_PUBLIC_API_KEY=…` |
| iOS / Android builds, simulator screenshots | This Mac has only Command Line Tools (no Xcode) and no Android SDK | Build on a machine with Xcode / Android Studio |
| FlutterFlow sync | API returns 401; GitHub integration not enabled | Connect FlutterFlow to GitHub, or build from this repo |

The Join Game screen validates codes locally, then asks the service; with no
server it says so plainly. Resume appears only after a server-confirmed join
in the last 2 hours. Nothing fabricates rooms, players or rankings.

## Verification (this machine, Flutter 3.35.7)

- `flutter pub get` ✓ · `dart format` ✓
- `flutter analyze`: 0 errors; `lib/bm` and `test` have no issues. The
  remaining 641 infos/warnings are in the unrouted FlutterFlow scaffold
  (baseline was 648).
- `flutter test`: **164 passed, 0 failed** (baseline 141). New tests include
  `navigation_journeys_test.dart`, which covers Welcome → Join → Lobby →
  Resume, Welcome → Practice → Results → Home, Settings → Music saved →
  Home, and Leaderboard → Profile → Back.
- `flutter build web --release` ✓ (it failed before this change).
- The release web build was driven in headless Chrome with real clicks and
  typing: `screenshots/redesign/browser-journey-log.txt` (journey complete,
  0 console errors). Before/after captures are in `screenshots/redesign/`.

## Build the updated version

```sh
git checkout dev && git pull
flutter pub get
flutter run -d chrome                 # quick web preview
flutter build ios --release           # needs Xcode
flutter build appbundle --release     # needs Android SDK
# QA deep links on web: ?screen=welcome|menu|lobby|race|ranks|classic
```
