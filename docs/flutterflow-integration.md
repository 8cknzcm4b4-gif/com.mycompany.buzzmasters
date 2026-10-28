# FlutterFlow integration status

- **FlutterFlow project ID:** `buzz-masters-9ci2h7`
- **Project URL:** https://app.flutterflow.io/project/buzz-masters-9ci2h7
- **App / bundle ID:** `com.mycompany.buzzmasters`
  (Android `applicationId` + `namespace` and all manifests, iOS `PRODUCT_BUNDLE_IDENTIFIER`)
- **GitHub repository:** not configured in this workspace (no `origin` remote)
- **Branch holding the work:** `freebuff/0e2bd1e80a1fd9d554b98b5d`
- **Race code location:** `lib/bm/race/` (FlutterFlow pages live in `lib/pages/`)

## Verified state

The FlutterFlow API is reachable, but rejects calls without credentials:

```
GET https://api.flutterflow.io/v2/projects/buzz-masters-9ci2h7
401 Unauthorized
```

`gh auth status` reports no GitHub login, and `GITHUB_TOKEN`, `GH_TOKEN`,
`FLUTTERFLOW_API_TOKEN`, `FLUTTERFLOW_TOKEN` are all unset in this workspace.

## What is required to finish

1. Add a GitHub remote with write access to this repository, then push the
   branch above.
2. Connect that repository to the FlutterFlow project in the FlutterFlow UI
   (Settings → Integrations → GitHub). The visual editor only ingests code
   through that connection; a GitHub push alone does not update the editor.
3. Register the race screens as FlutterFlow Custom Widgets/pages so they are
   reachable from the FlutterFlow navigation:
   `TurboRaceLobbyScreen`, `RacePracticeScreen`, `TimeTrialScreen`, plus the
   shared `TreadmillLane`, `RaceCountdown`, `EliminationFlash` and
   `FinishConfetti` widgets and the `BmAudioSettings` helper.

## Not integrated

- Multiplayer: `lib/bm/race/authority/` has the server engine, protocol and
  client session, but no WebSocket transport or host, so it is not wired to the
  lobby.
