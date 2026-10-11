# simplemotion/sm-install

Installer scripts for [SimpleMotion](https://simplemotion.com) binary products. One command installs the SimpleMotion CLIs.

This is the public bootstrap entry point served at **`install.simplemotion.dev`**, in two copies:

| URL | Audience | Channels |
|---|---|---|
| `https://install.simplemotion.dev/internal` | Executive and employees cohorts | All |
| `https://install.simplemotion.dev/external` | Freelance and customers cohorts | `release` and `preview` |

The two copies come from the same source. The build writes the external copy
with `/external` URLs, and its installer stops when you ask for a channel other
than `release` or `preview`. That stop is guidance only: the channel repos control access.

**Do not copy these URLs into other repos.** Link to this README in docs. Rust
code gets the URL from the `sm-install-url` crate in `3400-0001-SM-Core`.

Binaries themselves live in channel-specific repos:

| Channel | Repo | Visibility | Audience |
|---|---|---|---|
| `release` | [simplemotion/sm-release-external](https://github.com/simplemotion/sm-release-external) | public | All consumers — stable production builds |
| `preview` | [simplemotion/sm-preview-external](https://github.com/simplemotion/sm-preview-external) | public | Early access to the next public GA — all consumers |
| `develop` | [simplemotion/sm-develop-external](https://github.com/simplemotion/sm-develop-external) | staff | Earliest development builds |
| `testing` | [simplemotion/sm-testing-external](https://github.com/simplemotion/sm-testing-external) | staff | In-flight test builds |
| `develop` (internal packages) | `simplemotion/sm-develop-internal` | staff | Earliest builds of internal packages |
| `testing` (internal packages) | `simplemotion/sm-testing-internal` | staff | Test builds of internal packages |
| `preview` (internal packages) | `simplemotion/sm-preview-internal` | staff | The next GA of internal packages |
| `release` (internal packages) | `simplemotion/sm-release-internal` | staff | GA builds of internal packages |

Every channel has two repos: there are **two discrete release paths** (since
2026-10-11). An external package is on `sm-<channel>-external`, and an internal package is
on `sm-<channel>-internal`. On the internal installer copy, every `--channel`
looks in `sm-<channel>-external` first, then in `sm-<channel>-internal`, so staff use
the same channel names for every package. The external copy never looks in an
`-internal` repo.

Each channel repo has its own `releases/latest` namespace, so channel selection is unambiguous and there's no prerelease-flag coordination required.

**`release` and `preview` are public** (`preview` since 2026-10-11). The other
channels are private repos reachable by named teams:

| Channel | Read access |
|---|---|
| `release`, `preview` | Anyone, no account |
| `develop`, `testing`, and all four `-internal` repos | `ent:sm-executive`, `ent:sm-employees` |

`preview` carries external packages only. A staff-only package goes from
stops at `testing` and never goes to `preview`. `3400-9993-SM-Publish`
enforces this, and a promotion to `preview` needs two admin approvals, as a
promotion to `release` does.

`release` stays public on purpose: it is what a fresh machine bootstraps
`sm-welcome` from, before it has `gh` or a token at all.

Every gated channel needs an authenticated `gh` (or `GH_TOKEN`) with read
access. An unauthenticated request to one gets a 404, which is
indistinguishable from "nothing published yet" — the installer says so rather
than guessing.

### Promotion pipeline

The build happens **once**, at `develop`. Every later stage promotes that same
artifact, so its build counter `NNN` is carried unchanged and GA is byte
identical to what was tested. A package has exactly one terminal:

```
develop → testing → preview (GA vX.Y.Z, pre-release) → release   every package
```

Which preview and release repo a package uses is decided by
`channels/external-packages.txt` in `3400-9993-SM-Publish` — **default deny**,
so a package goes to the `-internal` repos until it is explicitly listed as
external. The `private` channel was removed on 2026-10-11.

## Channel pages

Each copy always has one page per channel, and one page per product on each
channel, under `https://install.simplemotion.dev/internal` and `/external`:

- `/<channel>/` lists every product with its install commands.
- `/<channel>/<product>/` gives the commands for one product, for example
  `/release/sm-welcome/` and `/develop/sm-simplicity/`.

The channels are `release`, `preview`, `testing` and `develop`. The products
are `sm-welcome` and `sm-simplicity`. On the external copy, the testing and
develop pages give the commands of the internal copy, because the external
installer refuses those channels. Only staff can read those channels. The build makes
the pages from `sm-channel/index.html` and the `PRODUCTS` list in
`sm-build.ts`.

## Install — sm-welcome (onboarding CLI)

### macOS / Linux

```bash
# release channel (stable)
bash -c "$(curl -fsSL https://install.simplemotion.dev/internal/sm-welcome.sh)" sm-welcome

# preview channel (early access)
bash -c "$(curl -fsSL https://install.simplemotion.dev/internal/sm-welcome.sh)" sm-welcome --channel preview

# develop channel (SimpleMotion internal)
bash -c "$(curl -fsSL https://install.simplemotion.dev/internal/sm-welcome.sh)" sm-welcome --channel develop
```

The `bash -c "$(curl …)"` form (rather than `curl … | bash`) is required so the installer can read interactive prompts from your terminal.

### Windows

```powershell
# release channel (stable)
irm https://install.simplemotion.dev/internal/sm-welcome.ps1 | iex

# preview channel
$env:SM_CHANNEL='preview'; irm https://install.simplemotion.dev/internal/sm-welcome.ps1 | iex
```

Freelance and customers cohorts use the external copy:

```bash
bash -c "$(curl -fsSL https://install.simplemotion.dev/external/sm-welcome.sh)" sm-welcome
```

```powershell
irm https://install.simplemotion.dev/external/sm-welcome.ps1 | iex
```

## Install — sm-simplicity (Simplicity product)

### macOS / Linux

```bash
curl -fsSL https://install.simplemotion.dev/internal/sm-simplicity.sh | bash
```

Customers use `https://install.simplemotion.dev/external/sm-simplicity.sh`.

Installs to `~/.local/bin/sm-simplicity`. Override with `SM_SIMPLICITY_INSTALL_DIR=/some/path`.

## Channels

| Selector | Resolves to |
|---|---|
| `--channel release` (default) or `SM_CHANNEL=release` | newest release on `simplemotion/sm-release-external` |
| `--channel preview` or `SM_CHANNEL=preview` | newest release on `simplemotion/sm-preview-external` (public, no account needed) |
| `--channel develop` or `SM_CHANNEL=develop` | newest release on `simplemotion/sm-develop-external` (not public — requires authed `gh` with read access) |
| `--channel testing` or `SM_CHANNEL=testing` | newest release on `simplemotion/sm-testing-external` (not public — requires authed `gh`) |
`--channel private` is refused: the `private` channel was removed on 2026-10-11, and staff-only packages are on `testing`.

## What the installers do

Each installer downloads the matching platform binary plus its `.sha256` and `.sigstore.jsonl` sidecars, then:

1. Verifies SHA256 (mandatory).
2. Verifies sigstore build-provenance attestation against the source repo (offline-only path uses the bundled `.sigstore.jsonl`; no GitHub API or auth required).
3. Installs the binary (or execs it directly in `install-and-run` mode).

If `gh` is missing, the installer bootstraps it from `cli/cli` releases into `~/.local/bin/gh` so attestation verification works on fresh machines.

## Where binaries are stored

The verified binary is kept in a per-channel store, **channel first**:

```
~/.simplemotion/share/<channel>/<package>/<tag>
~/.simplemotion/bin/<package>          → symlink to the active version
```

```
~/.simplemotion/share/
├── release/
│  └── sm-welcome/  v0.1.0  v0.0.9     ← every version ever installed
├── preview/
│  └── sm-mcp/      sm-mcp-v0.1.0-preview-249
├── develop/
└── testing/                           ← staff only
   └── sm-mcp/      v0.1.0-testing-249
```

**Nothing is pruned.** The leaf is the release tag, so rolling back is
re-pointing the symlink rather than a re-download:

```bash
ln -sfn ~/.simplemotion/share/release/sm-welcome/v0.0.9 ~/.simplemotion/bin/sm-welcome
```

Deleting a version directory by hand is safe as long as it is not the
symlink's current target.

The store is the source of truth; `~/.simplemotion/bin` holds only symlinks, so
re-installing from a different channel just re-points the link. `--install-dir`
and `SM_INSTALL_DIR` choose where the symlinks live — the store path is fixed.

**Grouping by channel makes the staff binaries separable.** Everything from
one staff channel lives under one tree, so removing all of it is one command:

```bash
rm -rf ~/.simplemotion/share/testing
```

Re-run the installer for anything you still want, and it will come back from a
channel you can reach.

Someone without access to a staff channel **never creates that directory**,
because they can never download from it. There is no empty `testing/` to
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
