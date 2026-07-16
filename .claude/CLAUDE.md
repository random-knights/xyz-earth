# Agent rules (xyz-earth)

**Read `../CODEX.md` in this repo root and follow it. It is the authority for
this repo.** Canonical org rules live in `C:\rand0m\CODEX.md`; the repo CODEX
restates them and adds the local specifics. `RUNBOOK.md` is the human guide.

xyz-earth is the standalone, PUBLIC, extracted globe. The app is `xyz`.

The three that bite hardest here:

1. **This repo is KEYLESS and PUBLIC, and CI proves it.** The gate runs a
   keyless guard that fails if a secret, an auth SDK, or a private `rk_*`
   dependency creeps in. Never add one. Never weaken the guard to make a PR
   pass. If a change needs a key, it belongs in `xyz`, not here.
2. **Shipping is a GitHub Release on a `v*` tag** (`deploy-prod.yml`, renamed
   from `release.yml`). Open-source app stores auto-discover it. Owner-gated.
   Never move or delete a released tag.
3. **ONE write-lane per repo.** Parallelize across repos, never within one.

Before pushing: `flutter pub get`, `flutter analyze`, `flutter test`. Never fake
a green run. Credentials are owner-only.
