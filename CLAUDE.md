# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this repo is

`simplemotion/sm-install` is the **public** installer-script home for SimpleMotion binary distribution. It hosts the shell installers consumers fetch via `curl | bash` or `irm | iex`, plus the landing page served at `install.simplemotion.dev`.

This repo contains **no binaries**. It is the routing layer between consumers and the four channel repos that host actual release assets.

## Four-repo architecture

| Repo | Visibility | Role |
|---|---|---|
| `simplemotion/sm-install` (this) | public | Installer scripts + Pages |
| `simplemotion/sm-release` | public | Production binaries |
| `simplemotion/sm-preview` | public | Preview / beta binaries |
| `simplemotion/sm-develop` | internal | Development — earliest builds |
| `simplemotion/sm-testing` | private | In-flight test builds |

`sm-install.sh` and `sm-install.ps1` map `--channel <name>` to `simplemotion/sm-<name>` and fetch the appropriate `releases/latest`. The channel-repo split avoids the prerelease-flag + latest-flag conflict that the prior `sm-get` single-repo design hit on 2026-05-16.

All SimpleMotion-authored scripts in this repo are `sm-*`-prefixed per the enterprise naming rule (see `9000-0000-SM-Govern/DISTRIBUTE.md`).

## What this repo is NOT

- **Not the binaries.** They live in the four channel repos above.
- **Not the source.** Each product has its own source repo (e.g., `3400-0000-SM-Software/3400-0009-SM-Welcome` for `sm-welcome`). Attestations are signed against the source repo; `install.{sh,ps1}` verify with `gh attestation verify --bundle <asset>.sigstore.jsonl --repo <source>`.
- **Not the build pipeline.** Builds run in the source repos and dispatch publish events into the right channel repo based on the tag suffix.

## Working rules

- **Public visibility is load-bearing.** Anything committed here is permanently public; do not paste internal docs, customer info, or credentials.
- **No "Co-Authored-By" trailers** in commits.
- **All IP assigned to SimpleMotion.Design Pty Ltd (ACN 611 618 770)** per `ASSIGN.md`.
- **Installers must be portable.** `*.sh` runs on bare macOS/Linux before any toolchain is installed — no bash-only constructs that POSIX `sh` can't read, no Homebrew assumptions, no `sudo`. `*.ps1` runs on stock Windows PowerShell.
- **Channel set is closed**: `release`, `preview`, `develop`, `testing`. Adding a fifth channel requires creating a new channel repo and updating both `install.{sh,ps1}` and the source-repo dispatch routing.
- **Versioning follows the SimpleMotion enterprise policy** (see appendix in `CHANGE.md`).

## DNS / Pages

`install.simplemotion.dev` is a GitHub Pages site. The `sm-pages.yml` workflow builds it from `main` and deploys it. The custom domain is set in the repo Pages settings; `CNAME` is a record only. DNS is a CNAME to `simplemotion.github.io` in the Azure DNS zone `simplemotion.dev` (resource group `sm-dns`). The zone CAA must allow `letsencrypt.org`, or Pages cannot issue the certificate.

- The site has two copies: `/internal` (executive and employees) and `/external` (freelance and customers, `release` and `preview` channels only).
- The source is the internal copy. `sm-build.ts` writes the external copy: it changes each `install.simplemotion.dev/internal` URL and each audience marker (`SM_INSTALL_AUDIENCE='internal'`, `$SmInstallAudience = 'internal'`) to external. The build fails if a marker or an internal URL stays.
- To show a staff URL in a script, split the string (for example `"%s/internal"` with the domain as the argument). If you do not, the build changes it to `/external`.
- These URLs are permanent. Do not move them again. If the host changes, change DNS only.
- `install.simplemotion.com` was retired on 2026-10-11, with no redirect.

## When in doubt, ask

Before adding new top-level files or changing the install-script contract (env vars, channel names, asset naming) — the contract is consumed by every source repo's release workflow.
