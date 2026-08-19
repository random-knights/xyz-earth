# AGENTS - agent rules for xyz-earth

Canonical rules live in `C:\rand0m\AGENTS.md` (the working-root standard). This
file restates what an agent MUST follow here and adds the xyz-earth specifics.
If the two ever disagree, the working-root standard wins.

xyz-earth is the standalone, PUBLIC, extracted globe. It is not the app; the app
is `ruok` (rand0m.ai).

## Owner ethos

- The owner approves; agents execute end to end (implement, commit, push, PR,
  green CI). Never fake a green run.
- Credentials are owner-only. Never create, read into chat, print, or commit a
  secret. This repo must need none - see below.
- Reversible cleanup: park or quarantine, never hard-delete.
- ASCII, no em dashes, in committed text.
- Repo changes ship via PR. The default branch is protected by the org ruleset
  `default-branch-protection` (PR required, 0 required reviewers).

## Concurrency - IMPORTANT

Follow the canonical root rule. Parallel write-lanes in one repository are
allowed only when each lane uses its own full clone, claimed file paths do not
overlap, and each lane rebases onto origin/main before pushing. Shared
worktrees still permit only one write-lane because they share one `.git`
directory. Read-only lanes may run alongside write work.

If you hit a shared-worktree conflict, stop and verify that `git status` and
`git diff` contain only your changes and HEAD is on your branch before
committing. `xyz-docs` remains the highest-risk repo org-wide, so serialize
writes there.

## Toolchain

Flutter 3.38.3 / Dart 3.10.1 at `C:\flutter`, with `C:\flutter\bin` on the USER
PATH. Never use `setx` to edit that PATH: it is over the 1024-char setx cap and
truncates silently.

    flutter pub get
    flutter analyze
    flutter test

That is the gate, and it mirrors the local gate in `CONTRIBUTING.md`.

## THE RULE THAT MATTERS HERE: this repo is KEYLESS and PUBLIC

This is an extracted, standalone, open-source globe. CI runs a **keyless guard**
that proves no secrets, no auth SDKs, and no private dependencies crept in. That
guard is the point of the repo, not red tape:

- **Never add a secret**, an auth SDK, or a private `rk_*` git dependency here.
  If a change needs one, it does not belong in xyz-earth - it belongs in `ruok`.
- The guard failing is a real finding. Do not weaken it to make a PR pass.
- Everything here is world-readable. Nothing internal, private, or unreleased.

## Workflows

  ci.yml           `CI` (job: `CI Gate`) - the contributor gate: analyze + tests
                   + build + the keyless guard. Required by the org ruleset.
  deploy-prod.yml  Packages an installable build and publishes a GitHub Release
                   so open-source app stores (e.g. Komi Store, which
                   auto-discovers repos publishing installable Release binaries
                   via the GitHub Releases API) can pick it up.

`deploy-prod.yml` was renamed from `release.yml` on 2026-07-16 to match the org
standard (`deploy-prod.yml` = ships on a `v*` tag). Nothing referenced it by
filename, so the rename was safe. It is OWNER-GATED: it only fires when a
maintainer pushes a `v*` tag. Pushing the first tag, and flipping the repo
public, are owner steps.

It has caught a real failure: the release web build broke on an invalid base
href and the workflow failed loudly rather than publishing a broken bundle to an
app store. Keep it.
