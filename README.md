# simplemotion/sm-install

Installer scripts for [SimpleMotion](https://simplemotion.com) binary products. One command installs the SimpleMotion CLIs.

This is the public bootstrap entry point served at **`install.simplemotion.com`**. Binaries themselves live in four channel-specific repos:

| Channel | Repo | Visibility | Audience |
|---|---|---|---|
| `release` | [simplemotion/sm-release](https://github.com/simplemotion/sm-release) | public | All consumers — stable production builds |
| `preview` | [simplemotion/sm-preview](https://github.com/simplemotion/sm-preview) | public | Early-access consumers — features in flight |
| `private` | [simplemotion/sm-private](https://github.com/simplemotion/sm-private) | private | SimpleMotion internal — stable internal-only releases |
| `testing` | [simplemotion/sm-testing](https://github.com/simplemotion/sm-testing) | private | SimpleMotion internal — in-flight test builds |

Each channel repo has its own `releases/latest` namespace, so channel selection is unambiguous and there's no prerelease-flag coordination required.

## Install — sm-welcome (onboarding CLI)

### macOS / Linux

```bash
# release channel (stable)
bash -c "$(curl -fsSL https://install.simplemotion.com/sm-welcome.sh)" sm-welcome

# preview channel (early access)
bash -c "$(curl -fsSL https://install.simplemotion.com/sm-welcome.sh)" sm-welcome --channel preview

# private channel (SimpleMotion internal)
bash -c "$(curl -fsSL https://install.simplemotion.com/sm-welcome.sh)" sm-welcome --channel private
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
| `--channel private` or `SM_CHANNEL=private` | newest release on `simplemotion/sm-private` (private repo — requires authed `gh` with read access) |
| `--channel testing` or `SM_CHANNEL=testing` | newest release on `simplemotion/sm-testing` (private repo — internal use) |

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
