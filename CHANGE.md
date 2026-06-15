# CHANGE.md

Changelog for this repo (`simplemotion/sm-install`).

Versioning follows the SimpleMotion enterprise policy — `vX.Y.Z` releases, `vX.Y.Z-preview-NNN` candidates, `vX.Y.Z-cm-NNN` dev builds. Only releases and RCs are recorded here. **Full policy is in the appendix at the end of this file.**

This repo holds the installer scripts served at `install.simplemotion.com`. The scripts route consumers to the appropriate channel repo (`simplemotion/sm-release` / `sm-preview` / `sm-develop` / `sm-testing`) based on `--channel`. Binaries themselves are not stored here.

---

## Changelog

| Version | Date | Author | Notes |
|---------|------|--------|-------|
| _(no releases yet)_ | | | |

The first release tag will be `v0.1.0`.

---

# Appendix — Enterprise versioning policy

Adopted 2026-05-12; revised 2026-06-14 to add the per-commit `-develop-` tag stream and the `-release-` candidate stage (superseding the earlier `-cm-` CI-only label), and to add the monorepo-workspace rule (one repo-wide version + a single bare tag, no per-package prefix); revised 2026-06-15 to record develop builds in `CHANGE.md` (one row per notable change, keyed by the `-develop-NNN` tag), clarifying that "no GitHub Release" governs distribution, not changelog listing; reconciled 2026-06-15 to the live channel architecture — the `-release-NNN` candidate is dropped (`preview` is the public candidate; `vX.Y.Z-release` is the GA-publish trigger), `-develop-` publishes to the internal `sm-develop` channel for distribution-surface products (tag/version-only for internal crates), and all channel/distribution specifics are deferred to the Distribution Standard (`9000-…-SM-Govern/CLAUDE.md`) as the single source of truth. Supersedes the 4-component `W.X.Y.Z` scheme used before. This section is reproduced verbatim in every SimpleMotion repo's `CHANGE.md` so each file is self-contained.

## TL;DR

```
vX.Y.Z-develop-NNN   dev build    (per-commit on main, or per-bump in a workspace)
vX.Y.Z-testing-NNN   testing      (early internal build)
vX.Y.Z-preview-NNN   preview      (public candidate)
vX.Y.Z-release       GA trigger   (publishes the GA release as vX.Y.Z)
vX.Y.Z               GA release   (the published GA version)
```

Lifecycle, least → most mature: **develop → testing → preview → GA**. GA is cut by
pushing the **`vX.Y.Z-release`** trigger tag (published as `vX.Y.Z`); `preview` is
the public candidate — there is no separate `-release-NNN` RC stage.

**Distribution is out of scope here.** Which channel/repo each suffix routes to,
its visibility, and how consumers install it are defined by the **Distribution
Standard** (`9000-…-SM-Govern/CLAUDE.md` — the single source of truth for
channels). This appendix governs only the **version/tag semantics**.

- `X.Y.Z` is strict SemVer 2.0.0.
- `NNN` is zero-padded to three digits (`001` … `999`).
- Every prerelease targets the *next* version, so `vX.Y.Z-<stage>-NNN` < `vX.Y.Z` — the GA tag always sorts highest. This is the only load-bearing ordering invariant.
- `-develop-NNN` is stamped automatically on **every commit on `main`** (one tag per commit) as the per-commit tracking stream; it is never published as a GitHub Release.
- **Develop builds are recorded in `CHANGE.md`** — one row per notable change (or version bump), keyed by the `-develop-NNN` tag of the commit that shipped it. "No GitHub Release" governs *distribution*, not documentation: the changelog still tracks the work. (Named `-testing-`/`-preview-` tags and the `-release` GA trigger, once cut, are recorded the same way.)
- **Ordering caveat:** the prerelease stage words sort *alphabetically* (`develop` < `preview` < `testing`), which is NOT the lifecycle order — `testing` sorts highest despite being least mature. Channels are picked by **suffix-string matching**, never by sort order, so this is harmless. Never rely on "highest prerelease = most mature."

**Channel access** is defined by the **Distribution Standard** (`9000-…-SM-Govern/CLAUDE.md` §4–§6), the single source of truth for the channel→repo mapping, visibility, and consumer install access. In brief: `preview` and GA are public; `testing` and `develop` are internal. The tag suffix is the routing key (`-develop-`/`-testing-`/`-preview-`/`-release`). This appendix does not restate the channel list — that's how the two docs previously drifted.

## Timeline of a release cycle

```
commit   tag                    stage    notes
──────   ────────────────────   ───────  ─────────────────
abc001   v0.1.0                 GA       latest stable
abc002   v0.1.1-develop-001     develop  per-commit (or per-bump) dev tag
abc003   v0.1.1-develop-002     develop  …
abc004   v0.1.1-testing-001     testing  early internal build
abc005   v0.1.1-develop-003     develop  work continues on main
abc006   v0.1.1-preview-001     preview  public candidate
abc007   v0.1.1-release         GA       push the -release trigger → published as v0.1.1
abc008   v0.1.2-develop-001     develop  next dev cycle
```

**Rule:** `-develop-NNN` is stamped per commit on `main` (single-binary repos, CI-owned) or per bump (workspaces, manifest-sourced); its base is *one patch ahead* of the most recent reachable GA release and `NNN` counts commits since that release. The named stages `-testing-` and `-preview-` are cut by hand from a chosen commit, each with its own `NNN` counter per base version. **GA is cut by pushing `vX.Y.Z-release`** (no `NNN`), which publishes as `vX.Y.Z` — there is no `-release-NNN` candidate.

## Why `-develop` / `-testing` / `-preview` / `-release` and not `+`-metadata

Both are valid per SemVer 2.0.0, but they differ in precedence semantics:

| Slot | Sorts? | Example |
|---|---|---|
| Pre-release (`-`) | Yes — affects comparison | `0.1.1-preview-001` < `0.1.1` |
| Build metadata (`+`) | No — ignored by comparators | `0.1.0+preview-001` ≡ `0.1.0` |

The `-` form is the only choice that lets any tool (Cargo, npm, pip, GitHub's "Latest" picker, `semver-cli`) correctly order pre-release tags below their target release. We accept the consequence that **`-develop-NNN`, `-testing-NNN`, and `-preview-NNN` belong to the *next* version**, not the most recent release. (`vX.Y.Z-release` is the GA-publish trigger, not a pre-release — it ships *as* `vX.Y.Z`.)

## Tagging commands

```bash
# Dev build — AUTOMATIC. CI stamps v<next>-develop-NNN on every commit to
# main; you never tag develop by hand. (See the build workflow below.)

# Testing (early internal build)
git tag -a v0.1.1-testing-001 -m "Testing v0.1.1-testing-001"
git push origin v0.1.1-testing-001

# Preview (public candidate)
git tag -a v0.1.1-preview-001 -m "Preview v0.1.1-preview-001"
git push origin v0.1.1-preview-001

# GA release — push the -release TRIGGER tag; CI publishes it as v0.1.1.
git tag -a v0.1.1-release -m "Release v0.1.1"
git push origin v0.1.1-release
```

(Which channel/repo each tag lands on is the Distribution Standard's concern, not this appendix's.)

- **`-develop-NNN` is never tagged by hand** on single-binary repos — CI owns it. (In a workspace it's advanced by the bump helper — see the monorepo rule.) The cut stages below are the human-pushed ones.
- **Increment NNN manually** for the cut stages (`-testing-002`, `-preview-002`, …). No tooling enforces uniqueness.
- **Three-digit zero-padding** is mandatory. Without it, `-preview-10` sorts before `-preview-2` lexically.
- **Never move a tag once pushed.** Cut a new testing/preview if you need to revise; cut a new patch for GA.
- **Only tag from `main` or a `release/v*.x` branch.** Other branches must never carry version tags.
- **Testing and preview share the `NNN` counter namespace per base version** — pick the next free number across both. GA uses the suffixless `-release` trigger (no `NNN`).

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
in the repo's `CLAUDE.md`. The named stages (`-testing-`/`-preview-`) and the
`-release` GA trigger are hand-cut from `main` either way.

## GitHub Actions: version + develop-tag

Versioning contributes two jobs to a repo's build workflow: a `version` job that
computes the version from the tag (or derives the next develop build on an
untagged commit), and a `develop-tag` job that stamps the per-commit develop tag
on `main`. **Publishing and channel routing are out of scope here** — that lives
in the Distribution Standard's release workflow (`sm-release.yml`, which
dispatches each tag to the right `sm-*` channel repo). For a workspace the
develop tag comes from the bump helper, not CI (see the monorepo rule).

```yaml
name: build
on:
  push:
    branches: [main, 'release/v[0-9]+.[0-9]+.x']
    tags:
      - 'v[0-9]+.[0-9]+.[0-9]+-develop-*'   # dev build (tag only)
      - 'v[0-9]+.[0-9]+.[0-9]+-testing-*'   # testing
      - 'v[0-9]+.[0-9]+.[0-9]+-preview-*'   # preview
      - 'v[0-9]+.[0-9]+.[0-9]+-release'     # GA trigger → published as vX.Y.Z

jobs:
  version:
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.v.outputs.version }}
      stage:   ${{ steps.v.outputs.stage }}
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0, fetch-tags: true }
      - id: v
        run: |
          if [[ "$GITHUB_REF" == refs/tags/v* ]]; then
            TAG="${GITHUB_REF#refs/tags/}"
            case "$TAG" in
              *-develop-*) STAGE=develop; VERSION="$TAG" ;;
              *-testing-*) STAGE=testing; VERSION="$TAG" ;;
              *-preview-*) STAGE=preview; VERSION="$TAG" ;;
              *-release)   STAGE=ga;      VERSION="${TAG%-release}" ;;
              *) echo "::error::unrecognized version tag $TAG"; exit 1 ;;
            esac
          else
            source "$HOME/SimpleMotion/.claude/scripts/sm-version.sh"
            VERSION="$(sm_version)"; STAGE=develop
          fi
          { echo "version=$VERSION"; echo "stage=$STAGE"; } >> "$GITHUB_OUTPUT"
          echo "version=$VERSION stage=$STAGE"

  # Per-commit dev tag on main (single-binary repos; workspaces use the bump helper).
  develop-tag:
    needs: version
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    permissions: { contents: write }
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0, fetch-tags: true }
      - run: |
          V="${{ needs.version.outputs.version }}"
          git rev-parse -q --verify "refs/tags/$V" >/dev/null && { echo "$V exists"; exit 0; }
          git tag -a "$V" -m "Dev build $V" && git push origin "$V"
```

Add `build` / `test` jobs per repo. **Publishing is the Distribution Standard's
`sm-release.yml`** — it routes `-develop-`/`-testing-`/`-preview-`/`-release` tags
to the `sm-*` channel repos. Do **not** add a local `gh-release` step here; it
would bypass the channel split.

## Changelog format

One row per **GA, release, preview, or testing tag**. Per-commit `-develop-NNN` tags do **not** appear — there's one per commit, so the commit log is their audit trail.

**Edits per release:**

1. Cut the tag and push it.
2. Prepend one row to the changelog table with the tag, date (UTC `YYYY-MM-DD`), author, and a one-line note.
3. For testing / preview / release tags, the same — they're real tags, they get rows. When a candidate promotes to GA, all rows remain (audit trail of the cycle).
4. **Never edit a row after the tag is published.** Append a new row instead.

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

- Tags matching `v[0-9]+.[0-9]+.[0-9]+(-(develop|testing|preview)-[0-9]{3}|-release)?` are the only version tags pushed — i.e. `-develop-`/`-testing-`/`-preview-` carry a 3-digit `NNN`, and the GA trigger is the suffixless `-release`. (Legacy `-cm-` / `-rc-` / bare-`vX.Y.Z` GA tags from before 2026-06-15 remain valid but no new ones are cut.)
- `CHANGE.md` carries the changelog table at the top and this policy appendix at the bottom, with legacy entries (if any) between them under a divider.
- The repo's build workflow keeps the `version` + `develop-tag` jobs (publishing/channel routing lives in the Distribution Standard's `sm-release.yml`, not here).
- No commit on `main` or a release branch is tagged with the retired `W.X.Y.Z` format.
