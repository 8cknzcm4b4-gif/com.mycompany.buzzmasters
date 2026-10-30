# FlutterFlow integration status

- **FlutterFlow project ID:** `buzz-masters-9ci2h7`
- **Project URL:** https://app.flutterflow.io/project/buzz-masters-9ci2h7
- **App / bundle ID:** `com.mycompany.buzzmasters`
  (Android `applicationId` + `namespace` and all manifests, iOS `PRODUCT_BUNDLE_IDENTIFIER`)
- **GitHub repository:** https://github.com/8cknzcm4b4-gif/com.mycompany.buzzmasters
- **Branch holding the work:** `dev`
- **Race code location:** `lib/bm/race/` (FlutterFlow pages live in `lib/pages/`)

## API access diagnosed (2026-10-30)

The earlier `401 Unauthorized` came from calling the API **without any
token**. The token saved by the FlutterFlow CLI (`~/.flutterflow/
credentials.json`) is valid: `listProjects` → 200, and
`flutterflow export-code -p buzz-masters-9ci2h7` downloads the project.

That export proves FlutterFlow and GitHub hold **different apps**:
FlutterFlow's `lib/main.dart` runs `MyApp` with 8 pages and has no `lib/bm`
(none of the redesign, racing, multiplayer or monetisation code) and no
Supabase, audio or RevenueCat packages. The CLI can only export, so GitHub →
FlutterFlow sync is not possible with this access, and nothing was written to
the FlutterFlow project. Builds must come from this repository.

## Why FlutterFlow builds do not show the custom game (checked 2026-10-30)

`lib/main.dart` runs `BuzzMastersApp` from `lib/bm/`; the FlutterFlow pages
in `lib/pages/` (including the "Join Game / Resume Last Session / ROOM
#882-104" landing screen) are not routed. A build produced *by FlutterFlow*
compiles FlutterFlow's own project, which is not linked to this repository,
so it shows those old pages. Build from this repository instead — see
`docs/neon-arena-redesign.md`.

## Verified state (re-checked 2026-10-30)

With the saved CLI key, `POST https://api.flutterflow.io/v2/l/listProjects`
returns 200 and lists "Buzz Masters" (`buzz-masters-9ci2h7`) alongside the
owner's other projects (not touched). The API exposes project export only:
there is no supported call to import code or change app settings. The
export does not contain this repository's code, so the project is not fed
from it; nothing was written to FlutterFlow, and a GitHub push does not reach
it.

## What is required to finish

1. Connect the pushed repository to the FlutterFlow project in the FlutterFlow
   UI (Settings → Integrations → GitHub). The visual editor only ingests code
   through that connection; a GitHub push alone does not update the editor.
2. Register the race screens as FlutterFlow Custom Widgets/pages so they are
   reachable from the FlutterFlow navigation:
   `TurboRaceLobbyScreen`, `RacePracticeScreen`, `TimeTrialScreen`, plus the
   shared `TreadmillLane`, `RaceCountdown`, `EliminationFlash` and
   `FinishConfetti` widgets and the `BmAudioSettings` helper.

## Multiplayer

Online racing runs on Supabase (`docs/multiplayer-backend.md`), not on the
older in-app engine in `lib/bm/race/authority/`, which remains for offline
tests only.
