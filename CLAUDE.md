# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this repo is

`simplemotion/sm-install-int` is the **public** installer-script home for SimpleMotion binary distribution. It hosts the shell installers that consumers fetch with `curl | bash` or `irm | iex`, and the landing pages on `install.simplemotion.dev` (internal) and `install.simplemotion.com` (external).

This repo contains **no binaries**. It is the routing layer between consumers and the four channel repos that host actual release assets.

## Channel repos

| Repo | Visibility | Role |
|---|---|---|
| `simplemotion/sm-install-int` (this) | public | Installer source + Pages for `install.simplemotion.dev` |
| `simplemotion/sm-install-ext` | public | Pages for `install.simplemotion.com`, deployed from this repo |
| `simplemotion/sm-release-external` | public | Production binaries |
| `simplemotion/sm-preview-external` | public | Preview / beta binaries |
| `simplemotion/sm-develop-external` | private | Development — earliest builds |
| `simplemotion/sm-testing-external` | private | In-flight test builds |
| `simplemotion/sm-develop-internal` | private | Develop builds of internal packages |
| `simplemotion/sm-testing-internal` | private | Test builds of internal packages |
| `simplemotion/sm-preview-internal` | private | Preview of internal packages |
| `simplemotion/sm-release-internal` | private | GA of internal packages |

Every channel has an `-external` repo and a private `-internal` repo (two discrete paths). On the internal copy, `sm-install.sh` tries `sm-<channel>-external` first and then `sm-<channel>-internal`. The external copy never tries an `-internal` repo, and `--repo` turns the fallback off.

`sm-install.sh` and `sm-install.ps1` map `--channel <name>` to `simplemotion/sm-<name>-external` (renamed from `sm-<name>` on 2026-10-11) and fetch the appropriate `releases/latest`. The channel-repo split avoids the prerelease-flag + latest-flag conflict that the prior `sm-get` single-repo design hit on 2026-05-16.

All SimpleMotion-authored scripts in this repo are `sm-*`-prefixed per the enterprise naming rule (see `9000-0000-SM-Govern/DISTRIBUTE.md`).

## What this repo is NOT

- **Not the binaries.** They live in the channel repos above.
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

**Move to Azure Static Web Apps (Greg, 2026-10-12).** Each copy now also deploys to its own SWA in `rg-sm-portal-se` (subscription SimpleMotion.Entertainment), beside the sm-website SWAs:

| Copy | SWA | Default host |
|---|---|---|
| Internal | `sm-portal-install-int` | `gray-island-0ee6aea00.5.azurestaticapps.net` |
| External | `sm-portal-install-ext` | `lively-water-02e6ddc00.5.azurestaticapps.net` |

- The `deploy-swa` job logs in with OIDC as the `sm-deploy-portal` app, which trusts this repo's `main` branch. It fetches each SWA's deploy token, deploys, and then fails if the SWA does not serve this build's `sm-install.sh`.
- One SWA cannot serve different content for each host name, so each copy needs its own SWA.
- `sm-build.ts` writes `staticwebapp.config.json` into each copy. It keeps the MIME types that Pages served, but serves `.ps1` as text.
- The two domains move to the SWAs in DNS. A TXT record validates each domain first, and then the CNAME changes. After that, a second change removes the Pages jobs and archives `sm-install-ext`. Until then, the Pages notes below stay correct.

There are two GitHub Pages sites, one for each domain, because Pages gives each repo one custom domain (Greg, 2026-10-12):

| Domain | Copy | Repo | Deploy |
|---|---|---|---|
| `install.simplemotion.dev` | Internal: executive and employees, every channel | this repo | Actions deploy of `_site/int` |
| `install.simplemotion.com` | External: freelance and customers, `release` and `preview` only | `simplemotion/sm-install-ext` | Branch build of `gh-pages`, which `sm-pages.yml` replaces with `_site/ext` |

- The `sm-pages.yml` workflow builds both copies from `main` and deploys both. The `deploy-ext` job pushes with a `sm-binary-bridge` token, so this repo needs access to the org secret `BRIDGE_APP_PRIVATE_KEY` and the org variable `BRIDGE_APP_CLIENT_ID`.
- For the internal site, the custom domain is in the repo Pages settings, and the root `CNAME` is a record only. For the external site, the build writes `CNAME` and `.nojekyll` into `_site/ext`, because a branch build reads its domain from the branch.
- DNS: each domain is a CNAME to `simplemotion.github.io` in its Azure DNS zone (`simplemotion.dev`, `simplemotion.com`; resource group `sm-dns`). If a zone has a CAA record, it must permit `letsencrypt.org`, or Pages cannot issue the certificate.
- The source is the internal copy. `sm-build.ts` writes the external copy: it changes each `install.simplemotion.dev` URL to `install.simplemotion.com`, and each audience marker (`SM_INSTALL_AUDIENCE='internal'`, `$SmInstallAudience = 'internal'`) to external. The build fails if a marker or an internal URL stays, or if the internal copy has an external URL.
- To show a staff URL in a script, split the string (for example `"%s.dev"` with `https://install.simplemotion` as the argument). If you do not, the build changes it to `.com`.
- **Both copies always have a page for every channel, and for every product on every channel**: `<domain>/<channel>/` and `<domain>/<channel>/<product>/` on both domains, for `release`, `preview`, `testing` and `develop`. These URLs are permanent. To add a product, add it to `PRODUCTS` in `sm-build.ts`; list only products that the public can know about, because `install.simplemotion.dev` is a public URL. `sm-build.ts` makes them from `sm-channel/index.html` and fails if one is missing. On the external copy, the testing and develop pages give the commands of the internal copy, because the external installer refuses those channels. The build fails if any page has no commands, or if a page mixes the two copies. Do not remove a page to restrict a channel: change what it shows. The template is not served.
- These URLs are permanent. Do not move them again. If the host changes, change DNS only.
- History: `install.simplemotion.com` served one copy until 2026-10-11. From 2026-10-11 to 2026-10-12, both copies were on `install.simplemotion.dev/internal` and `/external`. Greg removed those two paths on 2026-10-12, with no redirect.

## When in doubt, ask

Before adding new top-level files or changing the install-script contract (env vars, channel names, asset naming) — the contract is consumed by every source repo's release workflow.
