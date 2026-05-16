# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this repo is

`simplemotion/install` is the **public** installer-script home for SimpleMotion binary distribution. It hosts the shell installers consumers fetch via `curl | bash` or `irm | iex`, plus the landing page served at `install.simplemotion.com`.

This repo contains **no binaries**. It is the routing layer between consumers and the four channel repos that host actual release assets.

## Four-repo architecture

| Repo | Visibility | Role |
|---|---|---|
| `simplemotion/install` (this) | public | Installer scripts + Pages |
| `simplemotion/release` | public | Production binaries |
| `simplemotion/preview` | public | Preview / beta binaries |
| `simplemotion/private` | private | Internal-stable binaries |
| `simplemotion/testing` | private | In-flight test builds |

`install.sh` and `install.ps1` map `--channel <name>` to `simplemotion/<name>` and fetch the appropriate `releases/latest`. The channel-repo split avoids the prerelease-flag + latest-flag conflict that the prior `sm-get` single-repo design hit on 2026-05-16.

## What this repo is NOT

- **Not the binaries.** They live in the four channel repos above.
- **Not the source.** Each product has its own source repo (e.g., `3400-0000-SM-Software/3400-0009-SM-Welcome` for `sm-welcome`). Attestations are signed against the source repo; `install.{sh,ps1}` verify with `gh attestation verify --bundle <asset>.sigstore.jsonl --repo <source>`.
- **Not the build pipeline.** Builds run in the source repos and dispatch publish events into the right channel repo based on the tag suffix.

## Working rules

- **Public visibility is load-bearing.** Anything committed here is permanently public; do not paste internal docs, customer info, or credentials.
- **No "Co-Authored-By" trailers** in commits.
- **All IP assigned to SimpleMotion.Global Pty Ltd** per `ASSIGN.md`.
- **Installers must be portable.** `*.sh` runs on bare macOS/Linux before any toolchain is installed — no bash-only constructs that POSIX `sh` can't read, no Homebrew assumptions, no `sudo`. `*.ps1` runs on stock Windows PowerShell.
- **Channel set is closed**: `release`, `preview`, `private`, `testing`. Adding a fifth channel requires creating a new channel repo and updating both `install.{sh,ps1}` and the source-repo dispatch routing.
- **Versioning follows the SimpleMotion enterprise policy** (see appendix in `CHANGE.md`).

## DNS / Pages

`install.simplemotion.com` is served from this repo's **`main`** branch (Pages source = main, path /, HTTPS enforced) via the `CNAME` file at repo root. The `sm-welcome/index.html` landing page lives alongside the installers; there is no `gh-pages` branch.

## When in doubt, ask

Before adding new top-level files or changing the install-script contract (env vars, channel names, asset naming) — the contract is consumed by every source repo's release workflow.
