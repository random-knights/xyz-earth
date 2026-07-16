# RUNBOOK - xyz-earth (human operator)

For agent rules see `CODEX.md`. `README.md` describes the globe itself; this is
the operator path.

xyz-earth is the standalone, public, extracted globe. Nothing here deploys to a
server: "shipping" means publishing a GitHub Release that open-source app stores
can discover.

## Quick start

Flutter 3.38.3 lives at `C:\flutter` and `C:\flutter\bin` is on PATH.

```powershell
cd C:\rand0m\xyz-earth
flutter pub get
flutter analyze
flutter test
```

That is the same gate CI runs (see `CONTRIBUTING.md`).

## How to deploy

There is no server. `deploy-prod.yml` packages an installable build and
publishes a **GitHub Release**; app stores (e.g. Komi Store) auto-discover repos
that publish installable Release binaries via the GitHub Releases API.

It is OWNER-GATED and fires only on a pushed version tag:

```
git checkout main && git pull
git tag v0.1.0        # pick the next version
git push origin v0.1.0
```

Pushing the first tag, and flipping the repo public, are owner steps.

## How to roll back

- **A bad Release is published:** publish a corrected higher version. You can
  also delete or mark the bad GitHub Release as a pre-release so store discovery
  stops offering it. **Never move or delete the tag itself** - stores and users
  reference it, and a moved tag makes "what shipped" unanswerable.
- **Bad commit on main, not yet tagged:** open a revert PR. Nothing shipped.
  Never force-push main; the org ruleset blocks non-fast-forward and deletion.

## Where secrets live

**Nowhere, and that is enforced.** This repo is keyless by design and CI proves
it: the gate runs a **keyless guard** that fails if a secret, an auth SDK, or a
private dependency creeps in.

`deploy-prod.yml` uses only the built-in `GITHUB_TOKEN` (`contents: write`) to
create the Release. No repo secret is required.

If a change needs a key, it does not belong here - it belongs in `xyz`.

Org-wide: live keys are owner-laptop only at `C:\rand0m\.secrets\`. Never commit
or print one.

## What breaks and how to fix it

| Symptom | Cause | Fix |
|---|---|---|
| CI fails on the keyless guard | a secret, auth SDK, or private `rk_*` dep crept in | Remove it. This repo is public and keyless by design; the guard is the point. Move the change to `xyz` instead. Do NOT weaken the guard. |
| Release published a broken web bundle | this has happened: an invalid base href broke the release web build | The workflow failed loudly rather than shipping it - that is the gate working. Fix the base href (use a relative one), then re-tag forward. |
| A tag was pushed but no Release appeared | `deploy-prod.yml` only fires on `v*` tags | Check the tag matches `v*` and the workflow run log. |
| Local analyze clean, CI red | local Flutter is not 3.38.3, or stale `.dart_tool` | `flutter pub get`. Local Flutter must match CI. |

## Escalation

The app is `xyz`. Architecture and ADRs live in `xyz-docs`.
