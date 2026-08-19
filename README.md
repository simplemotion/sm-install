# simplemotion/sm-install

Installer scripts for [SimpleMotion](https://simplemotion.com) binary products. One command installs the SimpleMotion CLIs.

This is the public bootstrap entry point served at **`install.simplemotion.com`**. Binaries themselves live in channel-specific repos:

| Channel | Repo | Visibility | Audience |
|---|---|---|---|
| `release` | [simplemotion/sm-release](https://github.com/simplemotion/sm-release) | public | All consumers — stable production builds |
| `preview` | [simplemotion/sm-preview](https://github.com/simplemotion/sm-preview) | public | Early-access consumers — features in flight |
| `develop` | [simplemotion/sm-develop](https://github.com/simplemotion/sm-develop) | staff | Earliest development builds |
| `testing` | [simplemotion/sm-testing](https://github.com/simplemotion/sm-testing) | staff | In-flight test builds |
| `staff` | [simplemotion/sm-staff](https://github.com/simplemotion/sm-staff) | staff | **GA** builds of products that are never published publicly |

Each channel repo has its own `releases/latest` namespace, so channel selection is unambiguous and there's no prerelease-flag coordination required.

The staff channels are not public, so they need an authenticated `gh` (or
`GH_TOKEN`) with read access. An unauthenticated request to one gets a 404,
which is indistinguishable from "nothing published yet" — the installer says
so rather than guessing.

### Promotion pipeline

The build happens **once**, at `develop`. Every later stage promotes that same
artifact, so its build counter `NNN` is carried unchanged and GA is byte
identical to what was tested. After `testing` the ladder forks, and a package
has exactly one terminal:

```
                            ┌→ preview → release(-NNN) → GA vX.Y.Z   PUBLIC
develop → testing ──────────┤
                            └→ staff (GA vX.Y.Z)                     STAFF ONLY

v0.1.0-develop-249 → v0.1.0-testing-249 → v0.1.0-preview-249 → v0.1.0-release-249 → v0.1.0
```

Which fork a package takes is decided by `channels/public-packages.txt` in
`3400-9993-SM-Publish` — **default deny**, so a package is staff-only until it
is explicitly listed as public-eligible. `sm-staff` carries finalised
`vX.Y.Z` only; there is no `-staff-NNN` stage, because `testing` is the
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
| `--channel preview` or `SM_CHANNEL=preview` | newest release on `simplemotion/sm-preview` |
| `--channel develop` or `SM_CHANNEL=develop` | newest release on `simplemotion/sm-develop` (not public — requires authed `gh` with read access) |
| `--channel testing` or `SM_CHANNEL=testing` | newest release on `simplemotion/sm-testing` (not public — requires authed `gh`) |
| `--channel staff` or `SM_CHANNEL=staff` | newest GA release on `simplemotion/sm-staff` (not public — requires authed `gh`) |

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
