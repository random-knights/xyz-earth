# Contributing to xyz-earth

Thanks for helping build the open, living globe. `xyz-earth` is the **keyless,
open-source** Earth viewer for [rand0m.ai](https://rand0m.ai): the `earth2d`
canvas globe + the Planet Health Score, reading public rand0m.ai Storage with
bundled representative fallbacks. No keys, no auth, no private dependencies.

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to contribute

- **Propose a layer or data source** — open a [Discussion](../../discussions)
  with the dataset, its open license, spatial resolution, and update cadence.
- **Fix a bug or polish the viewer** — open a PR (see the gate below).
- **Improve the score methodology** — the score math is **frozen at v0.7** in
  this repo (the viewer only *reads and displays* the score doc, never
  recomputes it). Methodology proposals go to Discussions; they land upstream.

## The governance bar (non-negotiable)

Every layer and data object must keep the same guardrails the app enforces:

- **Aggregated / identity-stripped only.** No callsigns, vessel names, tail
  numbers, registrations, personal identifiers, or any per-vessel / per-aircraft
  identity. Identity suppression is a property of the *data*, not a display-time
  filter.
- **No precise sensitive locations.** Mobility layers (flights, boats) are
  decimated and rendered non-interactive (ambient flow, not followable targets).
- **Open license, attributed.** Each source carries its provider's license; add
  it to `NOTICE`.
- **Keyless.** The viewer must build and run with public packages only and read
  data over plain public HTTPS GET. Do not add `firebase_*`, auth, `envied`, an
  API key, or a private `git:` dependency. The `test/keyless_guard_test.dart`
  gate enforces this — keep it green.

## Development setup

```bash
flutter pub get
flutter run -d chrome
```

See the README for prerequisites.

## The gate (must pass before a PR is merged)

```bash
flutter analyze   # zero issues
flutter test      # all green (includes the keyless guard)
```

CI runs the same gate. A PR that adds a layer should also bundle a representative
asset so the globe still renders offline/keyless when the live object is absent.

## Code style

- Match the surrounding code; the extracted Earth sources keep their original
  structure under `lib/`.
- Keep the renderer **`earth2d`-only** — no Cesium, no 3D-globe dependency.
- New network reads use the existing live-URL → representative-fallback pattern
  in `lib/services/earth/` (with a request timeout), never a hard dependency on
  the network being reachable.
