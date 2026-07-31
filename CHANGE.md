# CHANGE.md

Changelog for this repo (`simplemotion/sm-install`).

Versioning follows the SimpleMotion enterprise policy (SemVer 2.0.0; see the appendix at the end of this file). **`sm-install` is a Pages-only repo — it serves installer scripts and stores no binaries** — so it carries no `-develop-/-testing-/-preview-` channel stream; it is versioned by bare `vX.Y.Z` tags cut by hand at meaningful milestones.

This repo holds the installer scripts served at `install.simplemotion.com`. The scripts route consumers to the appropriate channel repo (`simplemotion/sm-release` / `sm-preview` / `sm-develop` / `sm-testing`) based on `--channel`. Binaries themselves are not stored here.

---

## Changelog

| Version | Hash | Date | Author | Notes |
|---------|------|------|--------|-------|
| (auto) | — | 2026-07-31 | Greg Gowans | **Install `sm-onboard` beside `sm-welcome` in `~/.simplemotion/bin`.** Both `sm-welcome.sh` and `sm-welcome.ps1` now make a second call to the generic installer with `--package sm-onboard`, same `--source-repo`, same channel, same `--asset-suffix short` — so it reuses the existing SHA-256 + sigstore/cosign verification rather than adding a download path. **Why it was needed:** `sm-onboard` is the admin-run onboarding CLI, and `sm-welcome`'s own home-repo step failure tells the operator to run `sm-onboard <cohort> adduser …` — but nothing had ever installed it. It assumed the binary was on `PATH`, and it was not published at all until `simplemotion/sm-ci#28` (the release build never passed `--workspace`, so member binaries were enumerated, not found, and silently dropped). **Guard is `download-happened OR binary-absent`, not just the former.** `sm-welcome.sh`'s fast path skips the download entirely when `sm-welcome` already matches the channel's latest, so gating solely on that would never deliver `sm-onboard` to anyone already up to date — i.e. every existing install. A version comparison is not usable here: `sm-onboard` reports its own crate version (`0.1.0`), not the workspace release tag. **Non-fatal on failure**, deliberately: releases cut before `sm-ci#28` carry no `sm-onboard` asset, so a hard failure would break every install from an existing release, on every channel, until each is re-cut. The message says so explicitly rather than looking like a broken installer. A workstation without `sm-onboard` is fully functional — only admins invoke it. Validated: `bash -n` on the shell script, PowerShell AST parse on the `.ps1`. |
| v0.1.2 | — | 2026-07-30 | Greg Gowans | **Bump `esbuild` 0.24.2 → 0.28.1, clearing the dev-server request-forgery advisory.** Dependabot flagged a moderate alert against `package-lock.json`: esbuild ≤ 0.24.2 lets any website send requests to the running dev server and read the response, fixed in 0.25.0. **The pinned range could never reach the fix** — `^0.24.2` on a `0.x` version is minor-locked (`>=0.24.2 <0.25.0`), so the spec itself had to be raised and a lockfile refresh alone would have been a no-op. Went to the current release rather than the 0.25.0 minimum: `sm-build.ts` uses only `buildSync`, and both `npm run typecheck` and `npm run build` pass on 0.28.1 (both pages built, JS inlined and minified). Also adds `node_modules/` and `_site/` to `.gitignore` — neither was ignored, and both are produced by the install and build this change requires; `_site/` has never been tracked and is built by `sm-pages.yml` in CI. Version row precedes the tag, which is hand-cut at milestones per this repo's policy. |
| v0.1.1 | dc0dc99 | 2026-07-03 09:20 UTC | Greg Gowans | **Bootstrap section prompts auto-accept by default.** `confirm_section` / `Confirm-Section` no longer stop at `Proceed? [Y/n]` before each of the three sm-welcome bootstrap sections — they print the header and continue (matches sm-welcome `v0.1.10` dropping its per-step Proceed gate). `SM_WELCOME_CONFIRM=1` restores the gate; `SM_WELCOME_ASSUME_YES=1` (the old non-interactive override) still forces auto-accept over it, so existing CI/scripted callers are unaffected. `sm-welcome.ps1` forwards `SM_WELCOME_CONFIRM` across the UAC re-exec like its siblings. |
| v0.1.0 | a88e3d9 | 2026-06-17 07:31 UTC | Greg Gowans | Baseline under the enterprise versioning scheme; retired the legacy flat `v0.0.N` tag stream and refreshed this appendix to the build-once / carried-NNN policy. |

---

## Legacy — flat per-commit `v0.0.N` stream (retired 2026-06-17)

Before this baseline `sm-install` used an undocumented flat `v0.0.N` tag stream (`v0.0.07` … `v0.0.36`), one tag per commit, with **no GitHub Releases attached** — Pages serves from `main`, so the tags marked nothing consumers depended on. Those 30 tags were deleted on 2026-06-17 and superseded by the `vX.Y.Z` scheme starting at `v0.1.0`. No history was rewritten; only the dangling tags were removed.

---

# Appendix — Enterprise versioning policy

Adopted 2026-05-12; revised 2026-06-14 to add the per-commit `-develop-` tag stream and the `-release-` candidate stage (superseding the earlier `-cm-` CI-only label), and to add the monorepo-workspace rule (one repo-wide version + a single bare tag, no per-package prefix); revised 2026-06-15 to record develop builds in `CHANGE.md` (one row per notable change, keyed by the `-develop-NNN` tag), clarifying that "no GitHub Release" governs distribution, not changelog listing; reconciled 2026-06-15 to the live channel architecture — `-develop-` publishes to the internal `sm-develop` channel for distribution-surface products (tag/version-only for internal crates), and all channel/distribution specifics are deferred to the Distribution Standard (`9000-…-SM-Govern/CLAUDE.md`) as the single source of truth; revised 2026-06-17 to the **build-once / carried-NNN** model implemented in `simplemotion/sm-ci` — `develop` is the single build (one artifact per commit on `main`), each later stage **promotes that same artifact** so its `-develop-NNN` number is **carried unchanged** up the ladder, and `-release-NNN` is **restored** as a staging candidate (prerelease) finalised to the bare `vX.Y.Z` GA (the only "latest"); revised 2026-07-03 to require every hand-cut named tag to be an **annotated tag object** (`git tag -a` — lightweight tags lose `git describe` priority to CI's annotated develop tags); revised 2026-07-22 to make version derivation **canonical in `simplemotion/sm-ci`** (inlined in its `version` job) rather than a separately-sourced `sm-version.sh`, and to derive the pre-GA develop base from the **crate manifest's `X.Y.Z`** (falling back to `v0.1.0` for repos with no parseable version) instead of a hardcoded `v0.1.0`. revised 2026-07-29 to allow an **admin-authorised retraction** of the tag anti-patterns, subject to the never-consumed checks and a `CHANGE.md` record. revised 2026-07-29 to fix the changelog table format — `Version | Hash | Date | Author | Notes`, with the commit hash required on every entry, dates carrying UTC time (`YYYY-MM-DD HH:MM UTC`) and never local, and the author always the full `user.name`. Supersedes the 4-component `W.X.Y.Z` scheme used before. This section is reproduced verbatim in every SimpleMotion repo's `CHANGE.md` so each file is self-contained.

## TL;DR

```
vX.Y.Z-develop-NNN   dev build          (per-commit on main, or per-bump in a workspace — the ONE build)
vX.Y.Z-testing-NNN   testing            (promoted from develop — same NNN, same artifact)
vX.Y.Z-preview-NNN   preview            (public candidate — same NNN)
vX.Y.Z-release-NNN   release candidate  (staging — same NNN; prerelease, never "latest")
vX.Y.Z               GA release         (published version — finalised from one -release-NNN; the only "latest")
```

Lifecycle, least → most mature: **develop → testing → preview → release → GA**. The
build happens **once**, at `develop`; every later stage *promotes that same artifact*,
so the build's **`NNN` is carried unchanged** up the ladder (same `NNN` = same bytes).
`-release-NNN` is a staging candidate (a prerelease) living in the release channel;
one chosen candidate is finalised to the bare `vX.Y.Z` **GA**, which is the only tag
GitHub marks "latest" — every `-<stage>-NNN` is a prerelease.

**Distribution is out of scope here.** Which channel/repo each suffix routes to,
its visibility, and how consumers install it are defined by the **Distribution
Standard** (`9000-…-SM-Govern/CLAUDE.md` — the single source of truth for
channels). This appendix governs only the **version/tag semantics**.

- `X.Y.Z` is strict SemVer 2.0.0.
- `NNN` is zero-padded to three digits (`001` … `999`).
- Every prerelease targets the *next* version, so `vX.Y.Z-<stage>-NNN` < `vX.Y.Z` — the GA tag always sorts highest. This is the only load-bearing ordering invariant.
- `-develop-NNN` is stamped automatically on **every commit on `main`** (one tag per commit). It is the **single build**: CI builds the artifact once at this stage. (Whether that artifact becomes a downloadable Release is a distribution concern — see the Distribution Standard.)
- **`NNN` is carried UNCHANGED up the ladder.** `-testing-NNN`, `-preview-NNN` and `-release-NNN` reuse the **same `NNN`** as the `-develop-NNN` they were promoted from — same number means the same bytes. There is no per-stage counter; the develop number *is* the build identity, all the way to the GA it finalises into.
- **Develop builds are recorded in `CHANGE.md`** — one row per notable change (or version bump), keyed by the `-develop-NNN` tag of the commit that shipped it. The changelog tracks the work regardless of distribution. (Named `-testing-`/`-preview-`/`-release-NNN` tags, once cut, are recorded the same way.)
- **Ordering caveat:** the prerelease stage words sort *alphabetically* (`develop` < `preview` < `release` < `testing`), which is NOT the lifecycle order — `testing` sorts highest despite being least mature. Stages are picked by **suffix-string matching**, never by sort order, so this is harmless. Never rely on "highest prerelease = most mature."

**Channel access** is defined by the **Distribution Standard** (`9000-…-SM-Govern/CLAUDE.md` §4–§6), the single source of truth for the channel→repo mapping, visibility, and consumer install access. In brief: `preview` and GA are public; `testing`, `develop` and the `-release-NNN` staging candidates are internal. The tag suffix is the routing key (`-develop-`/`-testing-`/`-preview-`/`-release-`, plus bare `vX.Y.Z` for GA). This appendix does not restate the channel list — that's how the two docs previously drifted.

## Timeline of a release cycle

```
tag                    stage     notes
────────────────────   ───────   ─────────────────
v0.1.0                 GA        latest stable
v0.1.1-develop-001     develop   per-commit (or per-bump) dev build — CI builds the artifact
v0.1.1-develop-002     develop   …
v0.1.1-develop-003     develop   work continues on main
v0.1.1-testing-003     testing   promote develop-003 → testing (SAME NNN, same bytes)
v0.1.1-preview-003     preview   promote testing-003 → preview (public candidate)
v0.1.1-release-003     release   promote preview-003 → release staging candidate (prerelease)
v0.1.1                 GA        finalise release-003 → bare GA (the only "latest")
v0.1.2-develop-001     develop   next dev cycle
```

**Rule:** `-develop-NNN` is stamped per commit on `main` (single-binary repos, CI-owned) or per bump (workspaces, manifest-sourced); its base is *one patch ahead* of the most recent reachable GA release and `NNN` counts commits since that release. The build happens **only** at develop. The later stages are **promotions** of one chosen develop build, each reusing that build's `NNN`: `-testing-NNN` → `-preview-NNN` → `-release-NNN` (a prerelease staging candidate) → bare `vX.Y.Z` GA. **GA reuses no suffix** and is finalised from a chosen `-release-NNN`; it is the only tag marked "latest". (Not every develop build is promoted — you pick which one enters the ladder, but its number rides along unchanged.)

## Why `-develop` / `-testing` / `-preview` / `-release` and not `+`-metadata

Both are valid per SemVer 2.0.0, but they differ in precedence semantics:

| Slot | Sorts? | Example |
|---|---|---|
| Pre-release (`-`) | Yes — affects comparison | `0.1.1-preview-001` < `0.1.1` |
| Build metadata (`+`) | No — ignored by comparators | `0.1.0+preview-001` ≡ `0.1.0` |

The `-` form is the only choice that lets any tool (Cargo, npm, pip, GitHub's "Latest" picker, `semver-cli`) correctly order pre-release tags below their target release. We accept the consequence that **`-develop-NNN`, `-testing-NNN`, `-preview-NNN` and `-release-NNN` all belong to the *next* version**, not the most recent release — they are all prereleases that sort below the bare `vX.Y.Z` GA, which is why GA alone is "latest".

## Tagging commands

The develop build is the only tag pushed in the *source* repo. Everything above
it is a **promotion** that reuses the same `NNN` — the resulting tags (and the
mechanism that creates them) are the Distribution Standard's concern. The tag
*sequence* for one shipped build, end to end:

```
v0.1.1-develop-003     # AUTOMATIC — CI builds + tags this on a commit to main;
                       #             you never tag develop by hand.
v0.1.1-testing-003     # promote develop-003 → testing   (same NNN)
v0.1.1-preview-003     # promote testing-003 → preview   (same NNN)
v0.1.1-release-003     # promote preview-003 → release   (same NNN; prerelease staging)
v0.1.1                 # finalise release-003 → GA       (bare; the only "latest")
```

- **`-develop-NNN` is never tagged by hand** on single-binary repos — CI owns it. (In a workspace it's advanced by the bump helper — see the monorepo rule.)
- **Never invent a new `NNN` for a later stage.** The promotion carries the develop build's number unchanged — `-testing-`/`-preview-`/`-release-` all share the `-develop-NNN` they came from. Same number = same artifact.
- **Three-digit zero-padding** is mandatory. Without it, `-release-10` sorts before `-release-2` lexically.
- **Every hand-cut tag is annotated** — `git tag -a vX.Y.Z -m "…"` (likewise `-testing-`/`-preview-`/`-release-NNN`), never lightweight. Annotated tags carry tagger/date and take `git describe` priority; a lightweight GA on a commit that also bears CI's annotated `-develop-NNN` tag describes as the develop twin instead of the GA. CI's auto-cut develop tags are already annotated.
- **Never move a tag once pushed.** Promote a *new* develop build (new `NNN`) if you need to revise; cut a new patch for GA. Retraction is possible only with admin authorisation and the never-consumed checks — see *Yanking a broken release*.
- **Only the develop tag originates on `main`** (or a `release/v*.x` branch). The cut stages are promotions; they don't add new source-repo tags.

## Version computation in CI

Version derivation is **owned by the canonical reusable workflow `simplemotion/sm-ci`** (inlined in its `version` job); repos consume it via the one-line caller stub, with no separately-sourced script. It computes:

- The current tag verbatim if HEAD is on a `v*` tag (a clean GA tag is preferred over a prerelease pointing at the same commit).
- Otherwise `<base>-develop-<count>` where `<base>` is one patch ahead of the most recent clean GA release reachable from HEAD, and `<count>` is commits since that release.
- Before the first GA release (no reachable `vX.Y.Z` tag), `<base>` is the crate manifest's `X.Y.Z` (the `Cargo.toml` version before any `-develop` suffix), falling back to **`v0.1.0`** only when no version is parseable (e.g. non-Rust / config repos); `<count>` is commits from the root, so the initial dev stream is `<manifest X.Y.Z>-develop-NNN` (never `v0.0.x`).

See the `version` job of the `simplemotion/sm-ci` reusable workflow for the implementation.

## Monorepo workspaces (multiple crates / packages in one repo)

A repo with several packages (a Cargo workspace, an npm monorepo, …) carries
**one repo-wide version**, never a version per package. On the develop stream a
monorepo manages that version **in the manifests** (the manifest is the source
of truth), rather than deriving it in CI as a single-binary repo does:

- **One unified version in every manifest.** Each package's `Cargo.toml` /
  `package.json` carries the **same** `X.Y.Z-develop-NNN`. They move together so
  they promote to GA in lockstep. The manifest version is the source of truth.
- **One bare tag per bump.** A single `vX.Y.Z-develop-NNN` tags the whole repo —
  never per-package prefixes (`<crate>-v…`), and **no package/binary name in the
  tag or the version string**. (A program's `--version` banner naturally prints
  its own name, e.g. `sm-mcp-xero 0.1.0-develop-NNN`; that's the program
  identifier, not part of the version.)
- **A workspace bump helper advances the counter.** One command (e.g.
  `cargo xtask bump-develop`) rewrites every manifest to the next
  `-develop-NNN` (`NNN = max(manifest versions, existing tags) + 1`), refreshes
  the lockfile, commits, and creates the bare tag — keeping manifest ⇿ git tag ⇿
  each binary's `--version` (`CARGO_PKG_VERSION`) in lockstep.

**Why this differs from the single-package default.** For one shipped binary
the develop stream is **CI-owned** — auto-stamped per commit, version derived
by `simplemotion/sm-ci` from the manifest's base `X.Y.Z`. A workspace of
internal, cargo-installed crates instead keeps the unified version **in the
manifests** and advances it with the bump helper: every crate gets one coherent
version that `cargo`, the git tag, and `--version` all agree on, without
per-package CI bookkeeping. Both satisfy the invariant (one repo-wide version,
bare tags, no package name). Pick **one** model per repo and record the choice
in the repo's `CLAUDE.md`. Either way the develop build is the only source-repo
tag; the later stages are promotions of it that carry the same `NNN`.

## CI: version derivation + the develop tag

The canonical implementation is the reusable workflow **`simplemotion/sm-ci`**
(callers add a one-line stub — see its README). Two pieces of it are versioning's
concern; build and promotion are distribution's (below).

1. **Version derivation.** On a `v*` tag the version is the tag verbatim; on an
   untagged commit it is the next develop build:
   - `<base>-develop-<count>`, where `<base>` is one patch ahead of the most
     recent reachable clean GA release and `<count>` counts commits since it;
   - before the first GA (no reachable `vX.Y.Z` tag) `<base>` is the crate
     manifest's `X.Y.Z` (falling back to **`v0.1.0`** when unparseable, e.g.
     non-Rust / config repos) and `<count>` counts commits from the root.
2. **The develop tag.** Every push to `main` stamps `v<next>-develop-NNN` — CI
   owns it (a `GITHUB_TOKEN` push, so it never recursively re-triggers). In a
   workspace the bump helper advances it instead (see the monorepo rule).

The stage classifier (all `-<stage>-NNN` are prereleases; bare `vX.Y.Z` is GA):

```bash
if [[ "$GITHUB_REF" == refs/tags/v* ]]; then
  TAG="${GITHUB_REF#refs/tags/}"; VERSION="$TAG"
  case "$TAG" in
    *-develop-*) STAGE=develop ;;
    *-testing-*) STAGE=testing ;;
    *-preview-*) STAGE=preview ;;
    *-release-*) STAGE=release ;;   # prerelease staging candidate
    *)           STAGE=ga ;;        # bare vX.Y.Z — the only "latest"
  esac
else                                # untagged commit on main → next develop build
  VERSION="$(derive_develop)"; STAGE=develop  # inlined in simplemotion/sm-ci; see "Version computation"
fi
```

**Build & promotion are out of scope here** (they're distribution): `sm-ci`
builds the artifact **once** at the develop stage and dispatches it to the
`sm-develop` channel; each higher stage is a *promotion* run from that channel
repo's `sm-promote.yml`, carrying the same `NNN`, up to the GA finalise. The
retired per-repo `sm-release.yml` and any local `gh release` step are **not**
used — they would bypass the build-once split. See the Distribution Standard and
`sm-ci`'s README for the mechanics.

## Changelog format

One row per **notable change** — keyed by the `-develop-NNN` tag of the commit that shipped it, or by a named GA / release / preview / testing tag once one is cut. Trivial commits (typo- or format-only) need not get a row; the per-commit `-develop-NNN` tag stream plus the commit log remain the full audit trail.

**Table columns**, in this order — the same shape the pre-2026-05-12 tables used:

```
| Version | Hash | Date | Author | Notes |
```

- **Version** — the tag keying the row, or `—` where the change shipped without one.
- **Hash** — the **abbreviated commit hash** (7 chars) of the commit that shipped it. Required for every entry: the tag alone does not identify a commit once tags are re-cut or withdrawn, and rows keyed `—` have no other anchor.
- **Date** — UTC, `YYYY-MM-DD HH:MM UTC`. **Always UTC, never local.** Derive it with `TZ=UTC git log --date=format-local:'%Y-%m-%d %H:%M UTC'`; `--date=format-local` alone renders *local* time and will silently mislabel it (an AEST author is +10, so it lands ten hours off).
- **Author** — **always the full name**, exactly as configured in `user.name` for that repo's identity (e.g. `Greg Gowans`, never `Greg`). The changelog author must match the commit author it describes.
- **Notes** — one line, or a fuller paragraph for a notable change.

**Backfilling older rows.** Where a row predates this format and its commit cannot be identified — the tag was never cut, or the row is keyed by a product version rather than a git tag — put `—` in **Hash** and leave the date at whatever precision is known. **Never guess a hash or a time**: a wrong hash is worse than an absent one, because it points confidently at the wrong commit.

**Edits per change:**

1. **Develop:** land the commit on `main`; CI stamps its `-develop-NNN` tag automatically (never tag develop by hand). Prepend one row to the changelog table with that tag, the abbreviated commit hash, date (UTC `YYYY-MM-DD HH:MM UTC`), author (full name), and a one-line note.
2. **Named stages:** when you cut a testing / preview / release / GA tag by hand, push it and add its row the same way. When a candidate promotes to GA, all rows remain (audit trail of the cycle).
3. **Never edit a row after its tag is published.** Append a new row instead.

## Release branches and hotfixes

Long-lived branch per minor version, created when you commit to LTS for that line:

```
main                ●──●──●──●──●──●──●──●──●──●─────────●──●
                     \                                   /
                      \                            cherry-pick
                       \                                /
release/v0.1.x          ●──●──●─────●────────●─────────────●
                        │            │        │              │
                       v0.1.0       v0.1.1   v0.1.1-preview-1 v0.1.2
```

**Mechanics:**

```bash
# One-time: spawn the branch from the release tag
git switch --detach v0.1.0
git switch -c release/v0.1.x
git push -u origin release/v0.1.x

# Hotfix: land on main first, then cherry-pick
git switch main
# … fix, commit, PR, merge → abc123

git switch release/v0.1.x
git cherry-pick -x abc123
git push origin release/v0.1.x
git tag -a v0.1.1 -m "Patch v0.1.1"
git push origin v0.1.1
```

**Hard rules:**

- **Never merge** between `main` and a release branch. Cherry-pick only.
- **Protect release branches** the same way as `main` (required reviews, tag-push restricted to maintainers).
- **Declare an EOL per release line.** Don't accumulate release branches indefinitely.
- **GitHub's "Latest" picker uses SemVer order, not tag-creation time** — so cutting `v0.1.2` after `v0.2.0` won't dethrone `v0.2.0` as latest. No override needed.

## Yanking a broken release

**Rule: supersede, don't retract.** Deleting a tag doesn't recall anything; it breaks consumers who already pulled.

Steps for a broken `v0.1.1`:

1. **Ship `v0.1.2` immediately** (revert or fix-forward on `release/v0.1.x`, then tag).
2. **Edit the GitHub Release page** for `v0.1.1` — prepend a banner:
   > **⚠ YANKED — do not use.** Contains \<bug>. Upgrade to `v0.1.2` or stay on `v0.1.0`. See #\<issue>.
   Keep the artifacts attached so existing CI doesn't 404.
3. **Yank in any registry the artifact was published to** (`cargo yank`, `npm deprecate`, PyPI yank). Existing lockfiles continue to resolve; new resolves skip.
4. **Append a row to the changelog** with the yank notice and link to the superseding release.
5. **Announce** in the relevant ops channel.

**Anti-patterns** (never do these):
- `git push origin :v0.1.1` (delete remote tag) — cached locally everywhere, can't recall
- `git tag -f v0.1.1 <newsha>` — silent corruption for anyone who fetched the original
- `npm unpublish` — only allowed within 72h, breaks pinned downstreams (use `deprecate`)
- Reusing a version number for different content — violates SemVer's identity guarantee

The one exception: a pre-release tag that **never escaped CI** (no external pull, no registry publish) can be safely deleted. Default to superseding anyway — `-preview-002` costs nothing.

**Admin-authorised retraction.** An organisation admin may explicitly authorise one of the anti-patterns above — most often deleting a tag cut prematurely, or withdrawing a GA that turns out not to be ready to release. This is an *authorisation*, not a safety argument: none of the technical risks above go away, so it is only appropriate where the tag demonstrably has not been consumed.

Before acting, confirm all four:

1. **No GitHub Release** exists for the tag (a tag alone distributes nothing; a Release does).
2. **No registry publish** happened from this repo for that version.
3. **Nothing could have fetched it** — for a private repo, no forks, watchers or network; for a public one, assume it *was* fetched and supersede instead.
4. **It was not promoted** to a later stage (`-testing-`/`-preview-`/`-release-`/GA carrying the same `NNN`).

Then **record the retraction in `CHANGE.md`** — which admin authorised it, the date, and the four checks — so the tag's disappearance is visible in the record instead of looking like it silently vanished. Re-cutting the same version number for different content remains forbidden regardless of authorisation: retract, then move to a *new* number.

If any of the four fails, the admin's authorisation does not make it safe. Supersede.

## Migration from the legacy `W.X.Y.Z` scheme

Each repo's `CHANGE.md` is migrated as follows:

1. Replace the old single-table file with this three-part structure (changelog → legacy → policy appendix).
2. Copy this policy appendix verbatim into every repo's `CHANGE.md` so each file is self-contained.
3. Move all existing entries below the `## Legacy` divider verbatim — no rewriting of historical versions.
4. The first new tag a repo cuts under this scheme is `v0.1.0` (or higher if the repo is past beta and the maintainer chooses an appropriate major). Do **not** continue numbering from the legacy `v0.0.1.NN` sequence.

## Validation

A repo conforms to this policy when:

- Tags matching `v[0-9]+\.[0-9]+\.[0-9]+(-(develop|testing|preview|release)-[0-9]{3})?` are the only version tags — i.e. `-develop-`/`-testing-`/`-preview-`/`-release-` each carry a 3-digit `NNN`, and bare `vX.Y.Z` is GA. (Legacy `-cm-` / `-rc-` / suffixless `-release` trigger tags from before 2026-06-17 remain valid but no new ones are cut.)
- A given `NNN` is shared by the develop build and every stage promoted from it (same `NNN` = same artifact); no stage invents its own counter.
- Every hand-cut named tag (testing / preview / release / GA) is an annotated tag object (`git cat-file -t <tag>` → `tag`), never a lightweight commit ref.
- `CHANGE.md` carries the changelog table at the top and this policy appendix at the bottom, with legacy entries (if any) between them under a divider.
- The changelog table carries the columns `Version | Hash | Date | Author | Notes`; every row has a hash (or an explicit `—`), every date is UTC with time, and every author is a full name.
- The repo's CI is the canonical `simplemotion/sm-ci` (version derivation + develop tag + build-once at develop); promotions up the ladder are each channel repo's `sm-promote.yml`. No local publish/`gh release` step.
- No commit on `main` or a release branch is tagged with the retired `W.X.Y.Z` format.
