# simplemotion/sm-install

Installer scripts for [SimpleMotion](https://simplemotion.com) binary products. One command installs the SimpleMotion CLIs.

This is the public bootstrap entry point served at **`install.simplemotion.com`**. Binaries themselves live in four channel-specific repos:

| Channel | Repo | Visibility | Audience |
|---|---|---|---|
| `release` | [simplemotion/sm-release](https://github.com/simplemotion/sm-release) | public | All consumers — stable production builds |
| `preview` | [simplemotion/sm-preview](https://github.com/simplemotion/sm-preview) | public | Early-access consumers — features in flight |
| `develop` | [simplemotion/sm-develop](https://github.com/simplemotion/sm-develop) | internal | SimpleMotion internal — earliest development builds |
| `testing` | [simplemotion/sm-testing](https://github.com/simplemotion/sm-testing) | private | SimpleMotion internal — in-flight test builds |

Each channel repo has its own `releases/latest` namespace, so channel selection is unambiguous and there's no prerelease-flag coordination required.

### Promotion pipeline

A build promotes through the channels in order — `develop` → `testing` → `preview` → `release` — carrying a channel-prefixed tag at each phase until it earns the final clean release tag:

```
sm-develop-v0.0.1.#  →  sm-testing-v0.0.1.#  →  sm-preview-v0.0.1.#  →  sm-release-v0.0.1.#  →  v0.0.1
```

`#` is the build counter within a phase. Each phase's builds are published to its channel repo; the final clean `v0.0.1` tag lands on `sm-release` as the production release.

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
| `--channel preview` or `SM_CHANNEL=preview` | newest release on `simplemotion/sm-preview` |
| `--channel develop` or `SM_CHANNEL=develop` | newest release on `simplemotion/sm-develop` (internal repo — requires authed `gh` with read access) |
| `--channel testing` or `SM_CHANNEL=testing` | newest release on `simplemotion/sm-testing` (private repo — internal use) |

`--channel private` / `SM_CHANNEL=private` is accepted as a legacy alias for `develop` (the `sm-private` channel repo was renamed `sm-develop`).

## What the installers do

Each installer downloads the matching platform binary plus its `.sha256` and `.sigstore.jsonl` sidecars, then:

1. Verifies SHA256 (mandatory).
2. Verifies sigstore build-provenance attestation against the source repo (offline-only path uses the bundled `.sigstore.jsonl`; no GitHub API or auth required).
3. Installs the binary (or execs it directly in `install-and-run` mode).

If `gh` is missing, the installer bootstraps it from `cli/cli` releases into `~/.local/bin/gh` so attestation verification works on fresh machines.

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
