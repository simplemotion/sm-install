# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this repo is

`simplemotion/sm-install-int` is the **public** installer-script home for SimpleMotion binary distribution. It hosts the shell installers that consumers fetch with `curl | bash` or `irm | iex`, and the landing pages on `install.simplemotion.dev` (internal) and `install.simplemotion.com` (external).

This repo contains **no binaries**. It is the routing layer between consumers and the four channel repos that host actual release assets.

## Channel repos

| Repo | Visibility | Role |
|---|---|---|
| `simplemotion/sm-install-int` (this) | public | Installer source; deploys both installer sites |
| `simplemotion/sm-install-ext` | public, archived | The external Pages site until 2026-10-12 |
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

## Hosting and DNS

Each copy is its own Azure Static Web App (Greg, 2026-10-12). Both are in `rg-sm-portal-se` (subscription SimpleMotion.Entertainment), beside the sm-website SWAs.

| Domain | Copy | SWA | Default host |
|---|---|---|---|
| `install.simplemotion.dev` | Internal: executive and employees, every channel | `sm-portal-install-int` | `gray-island-0ee6aea00.5.azurestaticapps.net` |
| `install.simplemotion.com` | External: freelance and customers, `release` and `preview` only | `sm-portal-install-ext` | `lively-water-02e6ddc00.5.azurestaticapps.net` |

- One SWA cannot serve different content for each host name, so each copy needs its own SWA.
- `sm-pages.yml` builds both copies from `main`. Its `deploy-swa` job logs in with OIDC as the `sm-deploy-portal` app, fetches each SWA's deploy token, and deploys. It then fails if the SWA does not serve this build's `sm-install.sh`.
- **The OIDC subject uses immutable IDs.** This repo sends `repo:simplemotion@278089773/sm-install-int@1240545778:ref:refs/heads/main`, not the name form that sm-website sends. The federated credential `sm-install-int-main-immutable` matches it, and it still matches after a rename.
- **The internal copy needs staff sign-in (Greg, 2026-10-13).** Its pages need an account in the simplemotion.com tenant. Its `.sh` and `.ps1` files stay open, because `curl` and `irm` cannot sign in. The external copy stays open.
  - Both SWAs are on the Standard plan, because custom sign-in and managed identity need it. Each has its own user-assigned identity: `id-sm-portal-install-int` and `id-sm-portal-install-ext`.
  - The single-tenant app registration `sm-install-dev-signin` trusts `id-sm-portal-install-int` with a federated credential, so there is no secret to expire. The SWA app settings `AZURE_CLIENT_ID` and `OVERRIDE_USE_MI_FIC_ASSERTION_CLIENTID` hold the app's client ID and the identity's client ID.
  - A visitor who is not signed in gets `/sm-signin.html`. It sends the visitor to the Microsoft sign-in, then back to the same address with its query. The activation email's `?email=` link continues to work.
  - After each deploy, `sm-pages.yml` checks that the pages need sign-in and that the scripts stay open.
  - This controls who can see the pages. It does not keep anything secret: this repo is public, and internal binaries need GitHub access.
- **The pages gray out the staff channels until a staff member signs in (Greg, 2026-10-14).** Release and Preview are open to everyone on both domains. The channel nav and the welcome and Simplicity pages gray out Testing and Develop.
  - `sm-channel/sm-staff.ts` asks `/.auth/me` which account has signed in. It accepts only a `simplemotion.com` or `simplemotion.global` account. Each page script bundles it.
  - The external copy uses the same single-tenant registration, so a staff member can sign in there. Its pages stay open. Without a custom registration, a SWA accepts any Microsoft account.
  - The external SWA signs in with `id-sm-portal-install-ext`. The app registration must trust that identity, and must list the `install.simplemotion.com` callback.
  - On the external copy, a signed-in staff member gets the internal commands for Testing and Develop, because the external installer refuses those channels.
  - A grayed-out link is only a display. The pages stay public, and GitHub controls access to the staff channels.
- Each install command on a channel page has a green copy button on its right. The build fails if a command has no copy button.
- `sm-build.ts` writes `staticwebapp.config.json` and a root `index.html` into each copy. The config sets the MIME types (`.ps1` and `.html` with a charset) and redirects `/` to `/release/`. The SWA deploy refuses a site with no root `index.html`.
- DNS: each domain is a CNAME to its SWA's default host in its Azure DNS zone (`simplemotion.dev`, `simplemotion.com`; resource group `sm-dns`). Each SWA validated its domain with a `_dnsauth.install` TXT record. The certificates come from DigiCert (GeoTrust), so a CAA record on either zone must permit `digicert.com`.
- History: GitHub Pages served both domains until 2026-10-12. The external copy was the `gh-pages` branch of `simplemotion/sm-install-ext`, because Pages gives each repo one custom domain.
- The source is the internal copy. `sm-build.ts` writes the external copy: it changes each `install.simplemotion.dev` URL to `install.simplemotion.com`, and each audience marker (`SM_INSTALL_AUDIENCE='internal'`, `$SmInstallAudience = 'internal'`) to external. The build fails if a marker or an internal URL stays, or if the internal copy has an external URL.
- To show a staff URL in a script, split the string (for example `"%s.dev"` with `https://install.simplemotion` as the argument). If you do not, the build changes it to `.com`.
- **Both copies always have a page for every channel, and for every product on every channel**: `<domain>/<channel>/` and `<domain>/<channel>/<product>/` on both domains, for `release`, `preview`, `testing` and `develop`. These URLs are permanent. To add a product, add it to `PRODUCTS` in `sm-build.ts`; list only products that the public can know about, because this repo and `install.simplemotion.com` are public. `sm-build.ts` makes them from `sm-channel/index.html` and fails if one is missing. On the external copy, the testing and develop pages give the commands of the internal copy, because the external installer refuses those channels. The build fails if any page has no commands, or if a page mixes the two copies. Do not remove a page to restrict a channel: change what it shows. The template is not served.
- These URLs are permanent. Do not move them again. If the host changes, change DNS only.
- **Simplicity left the channel pages on 2026-10-12 (Greg).** No channel holds a `sm-simplicity` build. `RETIRED_PRODUCT_PAGES` in `sm-build.ts` redirects each old `/<channel>/sm-simplicity/` URL to its channel page with HTTP 301. Keep `/sm-simplicity/` and `sm-simplicity.{sh,ps1}`: the SM-Activate email links to that page. Both domains serve that page. The SM-Activate email selects the domain by recipient (`sm_install_url::Audience::for_email`): a staff address gets `install.simplemotion.dev/sm-simplicity/`, and a customer address gets `install.simplemotion.com/sm-simplicity/`.
- History: `install.simplemotion.com` served one copy until 2026-10-11. From 2026-10-11 to 2026-10-12, both copies were on `install.simplemotion.dev/internal` and `/external`. Greg removed those two paths on 2026-10-12, with no redirect.

## When in doubt, ask

Before adding new top-level files or changing the install-script contract (env vars, channel names, asset naming) — the contract is consumed by every source repo's release workflow.
