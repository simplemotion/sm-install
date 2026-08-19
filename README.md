# simplemotion/sm-install

Installer scripts for [SimpleMotion](https://simplemotion.com) binary products. One command installs the SimpleMotion CLIs.

This is the public bootstrap entry point served at **`install.simplemotion.com`**. Binaries themselves live in channel-specific repos:

| Channel | Repo | Visibility | Audience |
|---|---|---|---|
| `release` | [simplemotion/sm-release](https://github.com/simplemotion/sm-release) | public | All consumers — stable production builds |
| `preview` | [simplemotion/sm-preview](https://github.com/simplemotion/sm-preview) | private | Early access — staff and freelance, **not** customers |
| `develop` | [simplemotion/sm-develop](https://github.com/simplemotion/sm-develop) | staff | Earliest development builds |
| `testing` | [simplemotion/sm-testing](https://github.com/simplemotion/sm-testing) | staff | In-flight test builds |
| `private` | [simplemotion/sm-private](https://github.com/simplemotion/sm-private) | staff | **GA** builds of products that are never published publicly |

Each channel repo has its own `releases/latest` namespace, so channel selection is unambiguous and there's no prerelease-flag coordination required.

**Only `release` is open.** Every other channel is a private repo reachable by
named teams:

| Channel | Teams with read access |
|---|---|
| `preview` | `ent:sm-executive`, `ent:sm-employees`, `ent:sm-freelance` |
| `develop`, `testing`, `private` | `ent:sm-executive`, `ent:sm-employees` |

`ent:sm-customers` is deliberately on none of them. Customers get
`release` — the finalised, public GA — and nothing in flight.

`release` stays public on purpose: it is what a fresh machine bootstraps
`sm-welcome` from, before it has `gh` or a token at all.

Every gated channel needs an authenticated `gh` (or `GH_TOKEN`) with read
access. An unauthenticated request to one gets a 404, which is
indistinguishable from "nothing published yet" — the installer says so rather
than guessing.

### Promotion pipeline

The build happens **once**, at `develop`. Every later stage promotes that same
artifact, so its build counter `NNN` is carried unchanged and GA is byte
identical to what was tested. After `testing` the ladder forks, and a package
has exactly one terminal:

```
                            ┌→ preview → release(-NNN) → GA vX.Y.Z   PUBLIC
develop → testing ──────────┤
                            └→ private (GA vX.Y.Z)                   STAFF ONLY

v0.1.0-develop-249 → v0.1.0-testing-249 → v0.1.0-preview-249 → v0.1.0-release-249 → v0.1.0
```

Which fork a package takes is decided by `channels/public-packages.txt` in
`3400-9993-SM-Publish` — **default deny**, so a package is staff-only until it
is explicitly listed as public-eligible. `sm-private` carries finalised
`vX.Y.Z` only; there is no `-private-NNN` stage, because `testing` is the
candidate rung for both ladders.

## Install — sm-welcome (onboarding CLI)

### macOS / Linux

```bash
# release channel (stable)
bash -c "$(curl -fsSL https://install.simplemotion.com/sm-welcome.sh)" sm-welcome

# preview channel (early access)
bash -c "$(curl -fsSL https://install.simplemotion.com/sm-welcome.sh)" sm-welcome --channel preview

# develop channel (SimpleMotion internal)
bash -c "$(curl -fsSL https://install.simplemotion.com/sm-welcome.sh)" sm-welcome --channel develop
```

The `bash -c "$(curl …)"` form (rather than `curl … | bash`) is required so the installer can read interactive prompts from your terminal.

### Windows

```powershell
# release channel (stable)
irm https://install.simplemotion.com/sm-welcome.ps1 | iex

# preview channel
$env:SM_CHANNEL='preview'; irm https://install.simplemotion.com/sm-welcome.ps1 | iex
```

## Install — sm-simplicity (Simplicity product)

### macOS / Linux

```bash
curl -fsSL https://install.simplemotion.com/sm-simplicity.sh | bash
```

Installs to `~/.local/bin/sm-simplicity`. Override with `SM_SIMPLICITY_INSTALL_DIR=/some/path`.

## Channels

| Selector | Resolves to |
|---|---|
| `--channel release` (default) or `SM_CHANNEL=release` | newest release on `simplemotion/sm-release` |
| `--channel preview` or `SM_CHANNEL=preview` | newest release on `simplemotion/sm-preview` (not public — requires authed `gh`, and membership of executive, employees or freelance) |
| `--channel develop` or `SM_CHANNEL=develop` | newest release on `simplemotion/sm-develop` (not public — requires authed `gh` with read access) |
| `--channel testing` or `SM_CHANNEL=testing` | newest release on `simplemotion/sm-testing` (not public — requires authed `gh`) |
| `--channel private` or `SM_CHANNEL=private` | newest GA release on `simplemotion/sm-private` (not public — requires authed `gh`) |

`private` was a legacy alias for `develop` until 2026-08-19, from when the `sm-private` channel repo was renamed `sm-develop`. It is now a channel in its own right and no longer redirects.

## What the installers do

Each installer downloads the matching platform binary plus its `.sha256` and `.sigstore.jsonl` sidecars, then:

1. Verifies SHA256 (mandatory).
2. Verifies sigstore build-provenance attestation against the source repo (offline-only path uses the bundled `.sigstore.jsonl`; no GitHub API or auth required).
3. Installs the binary (or execs it directly in `install-and-run` mode).

If `gh` is missing, the installer bootstraps it from `cli/cli` releases into `~/.local/bin/gh` so attestation verification works on fresh machines.

## Where binaries are stored

The verified binary is kept in a per-channel store, **channel first**:

```
~/.simplemotion/share/<channel>/<package>
~/.simplemotion/bin/<package>          → symlink to the active channel's copy
```

```
~/.simplemotion/share/
├── release/     sm-welcome            ← public
├── preview/     sm-welcome  sm-mcp    ← candidates, both ladders
├── develop/     …
├── testing/     …
└── private/     sm-mcp  sm-govern     ← never published publicly
```

The store is the source of truth; `~/.simplemotion/bin` holds only symlinks, so
re-installing from a different channel just re-points the link. `--install-dir`
and `SM_INSTALL_DIR` choose where the symlinks live — the store path is fixed.

**Grouping by channel makes the private binaries separable.** Everything from
the private channel lives under one tree, so removing all of it is one command:

```bash
rm -rf ~/.simplemotion/share/private
```

Re-run the installer for anything you still want, and it will come back from a
channel you can reach.

Someone without access to the private channel **never creates that directory**,
because they can never download from it. There is no empty `private/` to
explain and nothing to tidy up on a non-staff machine.

> Until 2026-08-19 the store was `<package>/sm-<channel>/<package>`, which
> scattered each channel's binaries across one directory per package. The
> installer retires a package's legacy directory for the channel it installs,
> once the new copy and symlink are in place — so the tree converges as things
> are re-installed rather than needing a migration step.

## Verification (consumer-side)

```bash
gh attestation verify <asset> \
  --bundle <asset>.sigstore.jsonl \
  --repo <source-repo-from-readme-or-securemd>
```

This proves the binary was built by the named source repo's GitHub Actions workflow, without requiring access to that (potentially private) source repo. See `SECURE.md` for the full recipe and per-product source-repo identifiers.

## Reporting issues

- Installer bugs: open an issue on this repo.
- Product bugs: per-product issue tracker — see each channel repo's README.
- Security: email **security@simplemotion.com**.
