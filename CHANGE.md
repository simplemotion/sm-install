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

Adopted 2026-05-12; revised 2026-06-14 to add the per-commit `-develop-` tag stream and the `-release-` candidate stage (superseding the earlier `-cm-` CI-only label), and to add the monorepo-workspace rule (one repo-wide version + a single bare tag, no per-package prefix). Supersedes the 4-component `W.X.Y.Z` scheme used before. This section is reproduced verbatim in every SimpleMotion repo's `CHANGE.md` so each file is self-contained.

## TL;DR

```
vX.Y.Z                  GA release   (clean tag, public — sm-get)
vX.Y.Z-release-NNN      release RC   (tagged prerelease, public — sm-get)
vX.Y.Z-preview-NNN      preview      (tagged prerelease, public — sm-get)
vX.Y.Z-testing-NNN      testing      (tagged prerelease, internal — sm-int)
vX.Y.Z-develop-NNN      dev build    (tagged on every commit on main; no Release)
```

Lifecycle, least → most mature: **develop → testing → preview → release → GA**.

- `X.Y.Z` is strict SemVer 2.0.0.
- `NNN` is zero-padded to three digits (`001` … `999`).
- Every prerelease targets the *next* version, so `vX.Y.Z-<stage>-NNN` < `vX.Y.Z` — the GA tag always sorts highest. This is the only load-bearing ordering invariant.
- `-develop-NNN` is stamped automatically on **every commit on `main`** (one tag per commit) as the per-commit tracking stream; it is never published as a GitHub Release.
- **Ordering caveat:** the stage words sort *alphabetically* (`develop` < `preview` < `release` < `testing`), which is NOT the lifecycle order — `testing` sorts highest among prereleases despite being least mature. Channels are picked by **suffix-string matching** in `install.sh`, never by sort order, so this is harmless. Never rely on "highest prerelease = most mature."

**Channel access:**

| Channel | Suffix | Distribution | Anonymous access | Audience |
|---|---|---|---|---|
| GA release | none | `simplemotion/sm-get` Releases | Yes | Everyone |
| Release RC | `-release-NNN` | `simplemotion/sm-get` Releases (prerelease) | Yes | Everyone (opt-in) |
| Preview | `-preview-NNN` | `simplemotion/sm-get` Releases (prerelease) | Yes | Everyone (opt-in) |
| Testing | `-testing-NNN` | `simplemotion/sm-int` Releases (prerelease) | **No** — gated on GitHub enterprise membership | SimpleMotion internal staff |
| Develop | `-develop-NNN` | none (git tag + CI artifact only) | — | CI / per-commit tracking |

## Timeline of a release cycle

```
commit   tag                    GitHub Release   Channel  Notes
──────   ────────────────────   ──────────────   ───────  ─────────────────
abc001   v0.1.0                 Release          GA       latest stable
abc002   v0.1.1-develop-001     —                develop  per-commit dev tag (auto)
abc003   v0.1.1-develop-002     —                develop  per-commit dev tag (auto)
abc004   v0.1.1-testing-001     Prerelease       testing  early internal build
abc005   v0.1.1-develop-003     —                develop  work continues on main
abc006   v0.1.1-preview-001     Prerelease       preview  first public candidate
abc007   v0.1.1-release-001     Prerelease       release  final candidate, frozen
abc008   v0.1.1                 Release          GA       cut from the release RC
abc009   v0.1.2-develop-001     —                develop  next dev cycle
```

**Rule:** `-develop-NNN` is auto-stamped on every commit on `main`; its base is *one patch ahead* of the most recent reachable GA release and `NNN` counts commits since that release. The named prerelease stages (`-testing-`, `-preview-`, `-release-`) are cut by hand from a chosen commit; each stage keeps its own `NNN` counter per base version.

## Why `-develop` / `-testing` / `-preview` / `-release` and not `+`-metadata

Both are valid per SemVer 2.0.0, but they differ in precedence semantics:

| Slot | Sorts? | Example |
|---|---|---|
| Pre-release (`-`) | Yes — affects comparison | `0.1.1-preview-001` < `0.1.1` |
| Build metadata (`+`) | No — ignored by comparators | `0.1.0+preview-001` ≡ `0.1.0` |

The `-` form is the only choice that lets any tool (Cargo, npm, pip, GitHub's "Latest" picker, `semver-cli`) correctly order pre-release tags below their target release. We accept the consequence that **`-develop-NNN`, `-testing-NNN`, `-preview-NNN`, and `-release-NNN` belong to the *next* version**, not the most recent release.

## Tagging commands

```bash
# Dev build — AUTOMATIC. CI stamps v<next>-develop-NNN on every commit to
# main; you never tag develop by hand. (See the build workflow below.)

# Testing (internal early build; lands on sm-int)
git tag -a v0.1.1-testing-001 -m "Testing v0.1.1-testing-001"
git push origin v0.1.1-testing-001

# Preview (public candidate; lands on sm-get)
git tag -a v0.1.1-preview-001 -m "Preview v0.1.1-preview-001"
git push origin v0.1.1-preview-001

# Release candidate (final public gate before GA; lands on sm-get)
git tag -a v0.1.1-release-001 -m "Release candidate v0.1.1-release-001"
git push origin v0.1.1-release-001

# GA release
git tag -a v0.1.1 -m "Release v0.1.1"
git push origin v0.1.1
```

- **`-develop-NNN` is never tagged by hand** — CI owns it. The commands above are for the human-cut stages only.
- **Increment NNN manually** for the cut stages (`-testing-002`, `-preview-002`, …). No tooling enforces uniqueness.
- **Three-digit zero-padding** is mandatory. Without it, `-preview-10` sorts before `-preview-2` lexically.
- **Never move a tag once pushed.** Cut a new testing/preview/release if you need to revise.
- **Only tag from `main` or a `release/v*.x` branch.** Other branches must never carry version tags.
- **Testing, preview, and release share the `NNN` counter namespace per base version** — pick the next free number across all three. Cleaner audit trail than parallel counters.

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
in the repo's `CLAUDE.md`. The named prerelease stages (`-testing-`/`-preview-`/
`-release-`) and GA are hand-cut from `main` either way.

## GitHub Actions build workflow

Drop this into every repo at `.github/workflows/build.yml`:

```yaml
name: build

on:
  push:
    branches:
      - main
      - 'release/v[0-9]+.[0-9]+.x'
    tags:
      - 'v[0-9]+.[0-9]+.[0-9]+'              # GA release  v0.1.1
      - 'v[0-9]+.[0-9]+.[0-9]+-release-*'    # release RC  v0.1.1-release-001 (public, sm-get)
      - 'v[0-9]+.[0-9]+.[0-9]+-preview-*'    # preview     v0.1.1-preview-001 (public, sm-get)
      - 'v[0-9]+.[0-9]+.[0-9]+-testing-*'    # testing     v0.1.1-testing-001 (internal, sm-int)
      - 'v[0-9]+.[0-9]+.[0-9]+-develop-*'    # dev build   v0.1.1-develop-001 (tag only, no Release)

jobs:
  version:
    runs-on: ubuntu-latest
    outputs:
      version:       ${{ steps.v.outputs.version }}
      is_tag:        ${{ steps.v.outputs.is_tag }}
      is_ga:         ${{ steps.v.outputs.is_ga }}
      is_prerelease: ${{ steps.v.outputs.is_prerelease }}
      is_develop:    ${{ steps.v.outputs.is_develop }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          fetch-tags: true

      - id: v
        run: |
          IS_TAG=false
          IS_GA=false
          IS_PRERELEASE=false
          IS_DEVELOP=false

          if [[ "$GITHUB_REF" == refs/tags/v* ]]; then
            VERSION="${GITHUB_REF#refs/tags/}"
            IS_TAG=true
            if [[ "$VERSION" == *-develop-* ]]; then
              IS_DEVELOP=true            # dev tag: build only, no GitHub Release
            elif [[ "$VERSION" == *-*-* ]]; then
              IS_PRERELEASE=true         # testing / preview / release RC
            else
              IS_GA=true                 # clean vX.Y.Z
            fi
          else
            # Untagged commit on a branch: derive the next develop build.
            source "$HOME/SimpleMotion/.claude/scripts/sm-version.sh"
            VERSION="$(sm_version)"
          fi

          {
            echo "version=$VERSION"
            echo "is_tag=$IS_TAG"
            echo "is_ga=$IS_GA"
            echo "is_prerelease=$IS_PRERELEASE"
            echo "is_develop=$IS_DEVELOP"
          } >> "$GITHUB_OUTPUT"
          echo "Building $VERSION (tag=$IS_TAG ga=$IS_GA prerelease=$IS_PRERELEASE develop=$IS_DEVELOP)"

  # On every commit to main (no tag yet), stamp the per-commit develop tag.
  develop-tag:
    needs: version
    if: github.ref == 'refs/heads/main' && needs.version.outputs.is_tag == 'false'
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          fetch-tags: true
      - run: |
          V="${{ needs.version.outputs.version }}"
          if git rev-parse -q --verify "refs/tags/$V" >/dev/null; then
            echo "$V already tagged — nothing to do"
          else
            git tag -a "$V" -m "Dev build $V"
            git push origin "$V"
            echo "Tagged $V"
          fi

  # Publish a GitHub Release for GA + testing/preview/release tags (never for develop).
  release:
    needs: version
    if: needs.version.outputs.is_ga == 'true' || needs.version.outputs.is_prerelease == 'true'
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      - uses: softprops/action-gh-release@v2
        with:
          tag_name:               ${{ needs.version.outputs.version }}
          prerelease:             ${{ needs.version.outputs.is_prerelease }}
          generate_release_notes: true
```

Add `build` / `test` jobs as needed per repo; only the `version`, `develop-tag`, and `release` jobs are policy.

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

- Tags matching `v[0-9]+.[0-9]+.[0-9]+(-(develop|testing|preview|release)-[0-9]{3})?` are the only version tags pushed. (Legacy `-cm-` / `-rc-` tags from before 2026-06-14 remain valid but no new ones are cut.)
- `CHANGE.md` carries the changelog table at the top and this policy appendix at the bottom, with legacy entries (if any) between them under a divider.
- `.github/workflows/build.yml` either matches the template above or extends it without removing the `version`, `develop-tag`, and `release` jobs.
- No commit on `main` or a release branch is tagged with the retired `W.X.Y.Z` format.
