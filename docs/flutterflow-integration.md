# FlutterFlow integration status

- **FlutterFlow project ID:** `buzz-masters-9ci2h7`
- **Project URL:** https://app.flutterflow.io/project/buzz-masters-9ci2h7
- **App / bundle ID:** `com.mycompany.buzzmasters`
  (Android `applicationId` + `namespace` and all manifests, iOS `PRODUCT_BUNDLE_IDENTIFIER`)
- **GitHub repository:** https://github.com/8cknzcm4b4-gif/com.mycompany.buzzmasters
- **Branch holding the work:** `main`
- **Race code location:** `lib/bm/race/` (FlutterFlow pages live in `lib/pages/`)

## Why FlutterFlow builds do not show the custom game (checked 2026-10-30)

`lib/main.dart` runs `BuzzMastersApp` from `lib/bm/`; the FlutterFlow pages
in `lib/pages/` (including the "Join Game / Resume Last Session / ROOM
#882-104" landing screen) are not routed. A build produced *by FlutterFlow*
compiles FlutterFlow's own project, which is not linked to this repository,
so it shows those old pages. Build from this repository instead — see
`docs/neon-arena-redesign.md`.

## Verified state

The FlutterFlow API is reachable, but rejects calls without credentials:

```
GET https://api.flutterflow.io/v2/projects/buzz-masters-9ci2h7
401 Unauthorized
```

`FLUTTERFLOW_API_TOKEN`, `FLUTTERFLOW_TOKEN` are unset in this workspace,
so the editor cannot be updated from here; GitHub access now works via the
authenticated `gh` CLI and the source above has been pushed to `main`.

## What is required to finish

1. Connect the pushed repository to the FlutterFlow project in the FlutterFlow
   UI (Settings → Integrations → GitHub). The visual editor only ingests code
   through that connection; a GitHub push alone does not update the editor.
2. Register the race screens as FlutterFlow Custom Widgets/pages so they are
   reachable from the FlutterFlow navigation:
   `TurboRaceLobbyScreen`, `RacePracticeScreen`, `TimeTrialScreen`, plus the
   shared `TreadmillLane`, `RaceCountdown`, `EliminationFlash` and
   `FinishConfetti` widgets and the `BmAudioSettings` helper.

## Not integrated

- Multiplayer: `lib/bm/race/authority/` has the server engine, protocol and
  client session, but no WebSocket transport or host, so it is not wired to the
  lobby.
