# CHANGE.md

Changelog for this repo (`simplemotion/sm-install`).

Versioning follows the SimpleMotion enterprise policy — `vX.Y.Z` releases, `vX.Y.Z-preview-NNN` candidates, `vX.Y.Z-cm-NNN` dev builds. Only releases and RCs are recorded here. **Full policy is in the appendix at the end of this file.**

This repo holds the installer scripts served at `install.simplemotion.com`. The scripts route consumers to the appropriate channel repo (`simplemotion/sm-release` / `sm-preview` / `sm-private` / `sm-testing`) based on `--channel`. Binaries themselves are not stored here.

---

## Changelog

| Version | Date | Author | Notes |
|---------|------|--------|-------|
| _(no releases yet)_ | | | |

The first release tag will be `v0.1.0`.

---

# Appendix — Enterprise versioning policy

Adopted 2026-05-12, superseding the 4-component `W.X.Y.Z` scheme used before. This section is reproduced verbatim in every SimpleMotion repo's `CHANGE.md` so each file is self-contained.

## TL;DR

```
vX.Y.Z            release          (clean tag)
vX.Y.Z-rc-NNN     release candidate (tagged, GitHub prerelease)
vX.Y.Z-cm-NNN     dev build         (CI-derived label, no tag)
```

- `X.Y.Z` is strict SemVer 2.0.0.
- `NNN` is zero-padded to three digits (`001` … `999`).
- Dev builds (`-cm-NNN`) target the *next* version, so `vX.Y.Z-cm-NNN` < `vX.Y.Z`.
- RC builds (`-rc-NNN`) likewise sort below the eventual `vX.Y.Z`.
- Lexically: `cm-NNN` < `rc-NNN`, so `0.1.1-cm-099` < `0.1.1-rc-001` < `0.1.1`.

## Timeline of a release cycle

```
commit   tag              CI version       GitHub Release    Notes
──────   ──────────────   ─────────────    ──────────────    ─────────────────────────────
abc001   v0.1.0           v0.1.0           Release           latest stable
abc002                    v0.1.1-cm-001    —                 dev build, targets 0.1.1
abc003                    v0.1.1-cm-002    —                 dev build
abc004   v0.1.1-rc-001    v0.1.1-rc-001    Prerelease        first candidate
abc005                    v0.1.1-cm-001    —                 commits past the RC, counter resets
abc006   v0.1.1-rc-002    v0.1.1-rc-002    Prerelease        revised candidate
abc007   v0.1.1           v0.1.1           Release           cut from RC
abc008                    v0.1.2-cm-001    —                 next dev cycle
```

**Rule:** the dev counter resets at every version-bearing tag. The base version for `-cm-NNN` is *one patch ahead* of the most recent reachable clean release, or matches the most recent RC.

## Why `-cm` / `-rc` and not `+cm` / `+rc`

Both are valid per SemVer 2.0.0, but they differ in precedence semantics:

| Slot | Sorts? | Example |
|---|---|---|
| Pre-release (`-`) | Yes — affects comparison | `0.1.1-rc-001` < `0.1.1` |
| Build metadata (`+`) | No — ignored by comparators | `0.1.0+rc-001` ≡ `0.1.0` |

The `-` form is the only choice that lets any tool (Cargo, npm, pip, GitHub's "Latest" picker, `semver-cli`) correctly order an RC below its target release. We accept the consequence that **`-cm-NNN` and `-rc-NNN` belong to the *next* version**, not the most recent release.

## Tagging commands

```bash
# Release
git tag -a v0.1.1 -m "Release v0.1.1"
git push origin v0.1.1

# Release candidate
git tag -a v0.1.1-rc-001 -m "Release candidate v0.1.1-rc-001"
git push origin v0.1.1-rc-001
```

- **Increment RC numbers manually** (`-rc-002`, `-rc-003`, …). No tooling enforces uniqueness.
- **Three-digit zero-padding** is mandatory. Without it, `-rc-10` sorts before `-rc-2` lexically.
- **Never move a tag once pushed.** Cut a new RC if you need to revise.
- **Only tag from `main` or a `release/v*.x` branch.** Other branches must never carry version tags.

## Version computation in CI

Every repo's CI workflow sources `scripts/version.sh` from the canonical `.claude` clone:

```bash
source ~/SimpleMotion/.claude/scripts/version.sh
VERSION=$(sm_version)
```

The script returns:
- The current tag verbatim if HEAD is on a `v*` tag.
- Otherwise `<base>-cm-<count>` where `<base>` is one patch ahead of the most recent clean release reachable from HEAD, and `<count>` is commits since that release.

See `scripts/version.sh` in the canonical `.claude` repo for the implementation.

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
      - 'v[0-9]+.[0-9]+.[0-9]+'         # release      v0.1.1
      - 'v[0-9]+.[0-9]+.[0-9]+-rc-*'    # candidate    v0.1.1-rc-001

jobs:
  version:
    runs-on: ubuntu-latest
    outputs:
      version:       ${{ steps.v.outputs.version }}
      is_release:    ${{ steps.v.outputs.is_release }}
      is_prerelease: ${{ steps.v.outputs.is_prerelease }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          fetch-tags: true

      - id: v
        run: |
          IS_RELEASE=false
          IS_PRERELEASE=false

          if [[ "$GITHUB_REF" == refs/tags/v* ]]; then
            VERSION="${GITHUB_REF#refs/tags/}"
            IS_RELEASE=true
            [[ "$VERSION" == *-rc-* ]] && IS_PRERELEASE=true
          else
            # Most recent reachable clean release; base = one patch ahead
            LAST_REL=$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' \
                       --sort=-v:refname --merged HEAD \
                       | grep -v -- '-' | head -1)
            LAST_REL=${LAST_REL:-v0.0.0}
            IFS='.' read -r MAJ MIN PAT <<<"${LAST_REL#v}"
            BASE="v${MAJ}.${MIN}.$((PAT+1))"
            COUNT=$(git rev-list --count "${LAST_REL}..HEAD")
            VERSION="$(printf '%s-cm-%03d' "$BASE" "$COUNT")"
          fi

          echo "version=$VERSION"             >> "$GITHUB_OUTPUT"
          echo "is_release=$IS_RELEASE"       >> "$GITHUB_OUTPUT"
          echo "is_prerelease=$IS_PRERELEASE" >> "$GITHUB_OUTPUT"
          echo "Building $VERSION (release=$IS_RELEASE prerelease=$IS_PRERELEASE)"

  release:
    needs: version
    if: needs.version.outputs.is_release == 'true'
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

Add `build` / `test` jobs as needed per repo; only the `version` and `release` jobs are policy.

## Changelog format

One row per **release or RC tag**. Dev-build labels (`-cm-NNN`) do **not** appear — they're ephemeral CI artifacts. The commit log is the audit trail for unreleased work.

**Edits per release:**

1. Cut the tag and push it.
2. Prepend one row to the changelog table with the tag, date (UTC `YYYY-MM-DD`), author, and a one-line note.
3. For RCs, the same — they're real tags, they get rows. When the RC promotes to a release, both rows remain (audit trail of the RC cycle).
4. **Never edit a row after the tag is published.** Append a new row instead.

## Release branches and hotfixes

Long-lived branch per minor version, created when you commit to LTS for that line:

```
main                ●──●──●──●──●──●──●──●──●──●─────────●──●
                     \                                   /
                      \                            cherry-pick
                       \                                /
release/v0.1.x          ●──●──●─────●──────●──────────●
                        │            │      │           │
                       v0.1.0       v0.1.1 v0.1.1-rc-1 v0.1.2
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

The one exception: a pre-release tag that **never escaped CI** (no external pull, no registry publish) can be safely deleted. Default to superseding anyway — `-rc-002` costs nothing.

## Migration from the legacy `W.X.Y.Z` scheme

Each repo's `CHANGE.md` is migrated as follows:

1. Replace the old single-table file with this three-part structure (changelog → legacy → policy appendix).
2. Copy this policy appendix verbatim into every repo's `CHANGE.md` so each file is self-contained.
3. Move all existing entries below the `## Legacy` divider verbatim — no rewriting of historical versions.
4. The first new tag a repo cuts under this scheme is `v0.1.0` (or higher if the repo is past beta and the maintainer chooses an appropriate major). Do **not** continue numbering from the legacy `v0.0.1.NN` sequence.

## Validation

A repo conforms to this policy when:

- Tags matching `v[0-9]+.[0-9]+.[0-9]+(-rc-[0-9]{3})?` are the only version tags pushed.
- `CHANGE.md` carries the changelog table at the top and this policy appendix at the bottom, with legacy entries (if any) between them under a divider.
- `.github/workflows/build.yml` either matches the template above or extends it without removing the `version` and `release` jobs.
- No commit on `main` or a release branch is tagged with the retired `W.X.Y.Z` format.
