# CHANGE.md

Changelog for this repo (`simplemotion/sm-install`).

Versioning follows the SimpleMotion enterprise policy (SemVer 2.0.0; see the appendix at the end of this file). **`sm-install` is a Pages-only repo — it serves installer scripts and stores no binaries** — so it carries no `-develop-/-testing-/-preview-` channel stream; it is versioned by bare `vX.Y.Z` tags cut by hand at meaningful milestones.

This repo holds the installer scripts served at `install.simplemotion.com`. The scripts route consumers to the appropriate channel repo (`simplemotion/sm-release` / `sm-preview` / `sm-develop` / `sm-testing`) based on `--channel`. Binaries themselves are not stored here.

---

## Changelog

| Version | Date | Author | Notes |
|---------|------|--------|-------|
| v0.1.0 | 2026-06-17 | Greg Gowans | Baseline under the enterprise versioning scheme; retired the legacy flat `v0.0.N` tag stream and refreshed this appendix to the build-once / carried-NNN policy. |

---

## Legacy — flat per-commit `v0.0.N` stream (retired 2026-06-17)

Before this baseline `sm-install` used an undocumented flat `v0.0.N` tag stream (`v0.0.07` … `v0.0.36`), one tag per commit, with **no GitHub Releases attached** — Pages serves from `main`, so the tags marked nothing consumers depended on. Those 30 tags were deleted on 2026-06-17 and superseded by the `vX.Y.Z` scheme starting at `v0.1.0`. No history was rewritten; only the dangling tags were removed.

---

# Appendix — Enterprise versioning policy

Adopted 2026-05-12; revised 2026-06-14 to add the per-commit `-develop-` tag stream and the `-release-` candidate stage (superseding the earlier `-cm-` CI-only label), and to add the monorepo-workspace rule (one repo-wide version + a single bare tag, no per-package prefix); revised 2026-06-15 to record develop builds in `CHANGE.md` (one row per notable change, keyed by the `-develop-NNN` tag), clarifying that "no GitHub Release" governs distribution, not changelog listing; reconciled 2026-06-15 to the live channel architecture — `-develop-` publishes to the internal `sm-develop` channel for distribution-surface products (tag/version-only for internal crates), and all channel/distribution specifics are deferred to the Distribution Standard (`9000-…-SM-Govern/CLAUDE.md`) as the single source of truth; revised 2026-06-17 to the **build-once / carried-NNN** model implemented in `simplemotion/sm-ci` — `develop` is the single build (one artifact per commit on `main`), each later stage **promotes that same artifact** so its `-develop-NNN` number is **carried unchanged** up the ladder, and `-release-NNN` is **restored** as a staging candidate (prerelease) finalised to the bare `vX.Y.Z` GA (the only "latest"). Supersedes the 4-component `W.X.Y.Z` scheme used before. This section is reproduced verbatim in every SimpleMotion repo's `CHANGE.md` so each file is self-contained.

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
- **Never move a tag once pushed.** Promote a *new* develop build (new `NNN`) if you need to revise; cut a new patch for GA.
- **Only the develop tag originates on `main`** (or a `release/v*.x` branch). The cut stages are promotions; they don't add new source-repo tags.

## Version computation in CI

Every repo's CI workflow sources `scripts/sm-version.sh` from the canonical `.claude` clone:

```bash
source ~/SimpleMotion/.claude/scripts/sm-version.sh
VERSION=$(sm_version)
```

The script returns:
- The current tag verbatim if HEAD is on a `v*` tag (a clean GA tag is preferred over a prerelease pointing at the same commit).
- Otherwise `<base>-develop-<count>` where `<base>` is one patch ahead of the most recent clean GA release reachable from HEAD, and `<count>` is commits since that release.
- Before the first GA release (no clean `vX.Y.Z` tag exists yet), `<base>` is **`v0.1.0`** — the policy-mandated first release — and `<count>` is commits from the root, so the initial dev stream is `v0.1.0-develop-NNN` (never `v0.0.x`).

See `scripts/sm-version.sh` in the canonical `.claude` repo for the implementation.

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
the develop stream is **CI-owned** — auto-stamped per commit, version from
`sm-version.sh`, manifest holding only the base `X.Y.Z`. A workspace of
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
   - before the first GA (no clean `vX.Y.Z` tag exists yet) `<base>` is **`v0.1.0`**
     and `<count>` counts commits from the root, so the initial stream is
     `v0.1.0-develop-NNN` (never `v0.0.x`).
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
  VERSION="$(sm_version)"; STAGE=develop   # sm-version.sh; see "Version computation"
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

**Edits per change:**

1. **Develop:** land the commit on `main`; CI stamps its `-develop-NNN` tag automatically (never tag develop by hand). Prepend one row to the changelog table with that tag, date (UTC `YYYY-MM-DD`), author, and a one-line note.
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
- `CHANGE.md` carries the changelog table at the top and this policy appendix at the bottom, with legacy entries (if any) between them under a divider.
- The repo's CI is the canonical `simplemotion/sm-ci` (version derivation + develop tag + build-once at develop); promotions up the ladder are each channel repo's `sm-promote.yml`. No local publish/`gh release` step.
- No commit on `main` or a release branch is tagged with the retired `W.X.Y.Z` format.
