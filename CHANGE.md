<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/simplemotion/.github/main/assets/banners/SM-White.svg">
    <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/simplemotion/.github/main/assets/banners/SM-Black.svg">
    <img alt="SimpleMotion" src="https://raw.githubusercontent.com/simplemotion/.github/main/assets/banners/SM-Black.svg" width="800">
  </picture>
</p>

<p align="center">
  <em>Engineered for Architecture, Entertainment, Industry and Manufacturing.</em>
</p>

# CHANGE.md

Changelog for this repo (`simplemotion/sm-install`).

Versioning follows the SimpleMotion enterprise policy (SemVer 2.0.0; see the appendix at the end of this file). **`sm-install` is a Pages-only repo — it serves installer scripts and stores no binaries** — so it carries no `-develop-/-testing-/-preview-` channel stream; it is versioned by bare `vX.Y.Z` tags cut by hand at meaningful milestones.

This repo holds the installer scripts served at `install.simplemotion.com`. The scripts route consumers to the appropriate channel repo (`simplemotion/sm-release` / `sm-preview` / `sm-develop` / `sm-testing`) based on `--channel`. Binaries themselves are not stored here.

---

## Changelog

| Version | Hash | Date | Author | Notes |
|---------|------|------|--------|-------|
| (auto) | &mdash; | 2026-08-19 | Greg Gowans | **`preview` is staff-only: `ent:sm-freelance` came off it.** Every channel but `release` now has the same two teams, `ent:sm-executive` and `ent:sm-employees`, so the README names them once instead of maintaining a per-channel table that was already wrong. **Why a candidate channel is staff-only:** the ladders fork at preview, so a staff-only package *transits* it on the way to `private` — reading preview means reading every internal product's candidate builds, not just early access to public ones. That reasoning is now in the README, because otherwise the obvious future change is to widen preview to freelance or customers on the grounds that it only holds candidates. **Nothing here is a code path change** — `preview` was already treated as non-public in the channel case and the credentials branch, and the unauthenticated message already avoided naming cohorts. What changed is a stale comment calling it `staff+freelance` and three README lines that promised access the grants no longer give. Verified the installer still behaves: unauthenticated `--channel preview` gives the credentials message, authenticated resolves. Also backfills the previous merge's changelog placeholder (tag 030). |
| v0.1.2-develop-030 | c62c41d | 2026-08-19 02:21 UTC | Greg Gowans | **Store binaries channel-first, so the private ones are separable.** The per-channel store moves from `share/<package>/sm-<channel>/<package>` to `share/<channel>/<package>`. The old shape scattered each channel's binaries across one directory per package, so there was no single place the private ones lived and no way to remove them without knowing every package name. Now `rm -rf ~/.simplemotion/share/private` removes all of them and nothing else. **A machine without access never creates the directory** — it can never download from the channel — so there is no empty `private/` to explain on a non-staff machine and nothing to tidy up. **Legacy directories retire themselves** rather than needing a migration step: on install, once the new copy and the symlink are in place, the package's old `<package>/sm-<channel>` directory is removed and the parent pruned if empty. Only the channel being installed is touched, so other channels' copies stay put until their own next install. Leaving them would have been the actual bug: a stale private binary outside the channel tree means `rm -rf share/private` no longer removes everything private, which is the whole point of the layout. **The symlink contract is unchanged** — the store stays the source of truth and `~/.simplemotion/bin` holds only symlinks, so switching channels still just re-points a link. **Verified by driving `install_to_dir` directly** across four packages on three channels with a legacy directory seeded: binaries land under `develop/`, `private/` and `release/`, the seeded legacy tree is gone, a different channel's legacy copy is deliberately left alone, the symlink follows to the new path, and `rm -rf private` leaves nothing private behind. |
| v0.1.2-develop-029 | 428bd8b | 2026-08-19 01:52 UTC | Greg Gowans | **`preview` narrows to staff and freelance, and stops being a cohort-wide channel.** `sm-preview` moved from internal to private visibility with read granted to `ent:sm-executive`, `ent:sm-employees` and `ent:sm-freelance`. `ent:sm-customers` is deliberately on none of the channels now: customers get `release`, the finalised public GA, and nothing in flight. That makes `release` the only channel a customer can reach, which is also the only one a fresh machine can bootstrap from — the two facts are consistent rather than coincidental. **Docs said `cohort` and meant all four teams**, which stopped being true the moment customers came off, so the README now names the teams per channel rather than using a word that quietly drifted. The unauthenticated failure message drops the phrase *membership of a SimpleMotion cohort* for the same reason — being in a cohort no longer implies access, and telling someone otherwise sends them to ask for a grant that will not come. **No code path changed:** `preview` was already treated as non-public in the channel case and the credentials branch, so this is the visibility flip plus the wording that follows it. Verified after the flip that an authenticated install from `preview` still resolves `v0.1.0-preview-229`, unauthenticated gets the credentials message, and `release` is untouched. |
| v0.1.2-develop-028 | 11a9534 | 2026-08-19 01:41 UTC | Greg Gowans | **Rename the `staff` channel to `private`.** The channel set is now release, preview, develop, testing and private, with `private` sitting beside `release` as the second terminal — it holds the GAs that never leave SimpleMotion, readable by `ent:sm-executive` and `ent:sm-employees` only. `staff` shipped in no release of this script, so passing it now fails with a message naming the new channel rather than being quietly accepted. **The legacy `private` alias is retired, which is the substance of this change.** `private` meant *develop* in `sm-install.sh`, `sm-install.ps1` and `sm-welcome.sh`, left over from when the `sm-private` channel repo was renamed `sm-develop`. Keeping it would have made `--channel private` silently install a develop build from a different repo than the one the caller named — the exact failure this estate keeps hitting. It was checked rather than assumed safe to drop: no install receipt on the machine inspected records it, all four say develop, and receipts are only ever written, never read back to select a channel. `sm-welcome.sh` loses the alias outright rather than gaining the channel, because sm-welcome is public-eligible and the gate refuses it a private GA, so it can never appear there. **One collision is worth knowing about:** `simplemotion/sm-private` was a live GitHub redirect to `sm-develop`, and reusing the name drops it, so anything still pointing at the old name now reaches the GA channel instead of develop. **Verified against the live repos:** unauthenticated `--channel private` gives the credentials message, authenticated gives *no build published yet* from the real empty `sm-private`, `--channel staff` fails naming the replacement, an unknown channel lists all five, `--channel release` still resolves `v0.1.0` unauthenticated, and `--channel private` for sm-welcome no longer resolves to a develop build. |
| v0.1.2-develop-027 | 835c444 | 2026-08-19 01:33 UTC | Greg Gowans | **Two faults in tag resolution and provenance, both of which fail in ways that read as something else.** **One: `sm-ci` moved and the identity pin did not follow.** Attestations are signed by the reusable workflow, so when `sm-ci` became `3400-0000-SM-Software/3400-9991-SM-CI` the certificate SAN moved with it while `sm-install.sh` and `sm-install.ps1` stayed pinned to `simplemotion/sm-ci`. Every build cut after the migration failed provenance on every channel for every package, reporting `cosign rejected the bundle` after the checksum had already passed. The comment directly above that line already warned that pinning the wrong identity never matched and always rejected the bundle; the migration reintroduced exactly that. **Both identities are accepted, deliberately.** Releases already published were signed under the old one and must stay installable - `sm-mcp-v0.1.0-develop-249` and `-develop-001` carry `simplemotion/sm-ci`, `-develop-006` carries the new one, so the cutover falls between 17 and 18 August. A hard swap would have traded one broken set for another. Drop the old alternative once every published release has been re-cut. Verified with cosign against real bundles of both vintages: `Verified OK` for each, and the unpatched pin still rejects the newer one. **Two: the tag scan asked for 30 releases on a channel that holds 49.** The channel repos are shared - `sm-develop` carries 17 packages - and `/releases` was requested with no `per_page`, so the scan saw the newest 30 and took the first match. Once a package's newest release falls past that boundary the scan finds nothing and the installer exits with `No <channel> build of <package> is published yet`, which reads like it was never released rather than like a page-size bug. Measured rather than predicted: the newest `sm-mcp-v` tag sat at **index 17 of 30** on 2026-08-19. `releases/latest` and `releases/tags/<tag>` are untouched - they return a single object and take no page size. Found while wiring `sm-<binary> --update`, which makes both paths run far more often than a first install ever did. **Also backfills the tag stream**, which the inlined gate blocked on: `-023`, `-024` and `-025` were tagged by earlier merges but left as `(auto)`, so each is keyed to its tag with the hash and UTC date read from the tagged commit. Pre-existing drift, unrelated to either fix. `bash -n` clean, `.ps1` parses under pwsh. |
| v0.1.2-develop-026 | c8c13f1 | 2026-08-19 01:19 UTC | Greg Gowans | **Add the `staff` channel — the GA surface for products that are never published publicly.** The ladder now forks after `testing`: public-eligible packages continue to `preview` and `release`, everything else finalises GA on the new `simplemotion/sm-staff`. Which fork a package takes is decided by `channels/public-packages.txt` in `3400-9993-SM-Publish`, default-deny and enforced in `sm-promote.yml`; the installer only needs to resolve the channel. `sm-staff` is a terminal like `release` and carries finalised `vX.Y.Z` only. **The download path needed no change** — the token-then-API-asset-url route already existed for `develop` and `testing`, so accepting the channel name was the whole of it, plus the `ValidateSet` in the `.ps1` so the two do not disagree. **A 404 on a non-public channel is not a missing release.** An unauthenticated request to `sm-develop`, `sm-testing` or `sm-staff` gets a 404, and GitHub does not distinguish *no such release* from *not visible to you*, so the installer reported the first and sent staff hunting for a build sitting right there. It now says which case it cannot rule out and points at `gh auth login`. Verified against the live repos: unauthenticated `--channel staff` gives the credentials message, authenticated gives *no build published yet* from the real empty `sm-staff`, an unknown channel lists all five, and `--channel release` still resolves `v0.1.0`. **Also corrects the promotion diagram**, which still showed the retired `sm-develop-v0.0.1.#` scheme superseded by `vX.Y.Z-develop-NNN` and described a rebuild at every phase rather than the build-once model. It sat directly above the section this change had to edit. **`preview` is a gated channel too.** Access to early-access builds now requires membership of a SimpleMotion cohort rather than just the URL, so `sm-preview` moves to internal visibility alongside the staff channels, and the installer treats it the same way — an unauthenticated request gets the credentials message rather than a misleading *not published yet*. The failure path also stopped suggesting `--channel preview` as the fallback, which would have sent an unauthenticated caller from one 404 to another; it now suggests `release`. **`release` stays public deliberately** — it is what a fresh machine bootstraps `sm-welcome` from, before it has `gh` or a token at all, so gating it would leave a newly accepted person unable to install the tool that onboards them. **`sm-welcome.sh` is deliberately untouched:** `sm-welcome` is public-eligible, so the gate refuses it a staff GA and the wrapper has no business offering a channel its product can never appear on. |
| v0.1.2-develop-025 | e1968de | 2026-08-17 03:13 UTC | Greg Gowans | **Stop citing `DISTRIBUTE.md`, which exists in no repo and no checkout.** The `sm-` prefix gate pointed developers at *"DISTRIBUTE.md principle 9"* in both its error messages. A fleet search found the document cited in seven places across six repos and present in none of them &mdash; so anyone hitting the error and going looking found nothing, and the rule had no home at all. Both error strings now state the rule and point at `simplemotion/sm-pr`'s README, which documents it as of the companion PR. **This lands first, deliberately.** The strings are compared against the canonical by `sm-inline-drift`, which strips comments but not executable lines, so changing `sm-pr` first would fail the drift job on `sm-pr`'s own pull request &mdash; the same lockstep that PR #74 had to observe a few hours ago. The explanatory comment retains the name once, to record what the citation used to say and why it went. |
| v0.1.2-develop-024 | ecb11ed | 2026-08-17 02:13 UTC | Greg Gowans | **Add `SECURE.md` to the inline fork's required-files list, so the gate change in `sm-pr` can land.** `sm-pr` is tightening its repo-hygiene check to require `SECURE.md` (PR #46), a file 42 of 50 repos already carry. This repo is **public** and cannot call the internal `simplemotion/sm-pr`, so it runs an inlined fork of that gate — and `sm-inline-drift` compares the two step bodies with comments and blank lines stripped. The consequence is easy to miss: the canonical change does not reach here on its own, and until this lands the drift job **fails on `sm-pr`'s own pull request**, not on this repo's. That is the third time this fork has had to be hand-carried after a canonical edit; the previous two are recorded below. Only the executable line changes, since the comparison normalises comments away. This repo already carries a `SECURE.md`, so it passes the tightened rule the moment it applies. |
| v0.1.2-develop-023 | d7958c2 | 2026-08-15 07:12 UTC | Greg Gowans | **Carry the stream check's backtick fix into the inline fork.** A row written as `` `abc1234` `` never matched the tag it named, so the check disagreed with itself depending on which convention a repo had settled on. This fork cannot inherit the fix &#124; a public repo cannot call an internal reusable workflow, so it is copied. |
| v0.1.2-develop-022 | 74848b7 | 2026-08-15 03:02 UTC | Greg Gowans | **Re-sync the inlined gate to canonical `main`, which it had run ahead of.** The previous sync ported the develop-stream step from an **unmerged branch** of `simplemotion/sm-pr`, so this fork gained ten lines canonical never had — code that printed the keyed changelog row on failure, from a design since closed unmerged. The fork was **ahead**, not behind, which is the direction nobody watches for. `sm-pr`'s drift check caught it on the very next PR and failed every run touching `sm-pr.yml` until now — working exactly as intended, on a divergence introduced by the person who built it. The step is back to canonical's 85 lines, with the one `inputs.` reference adapted as before. **The lesson is about where you copy from**: a fork must be synced from the canonical branch, never from a branch proposing to change it, or the fork ships a decision that was never made. |
| `v0.1.2-develop-021` | 655984c | 2026-08-15 01:07 UTC | Greg Gowans | **Carry the stream check's new fix-it output.** Canonical now prints the finished changelog row when it fails on two in-flight `(auto)` placeholders — version, short hash and UTC timestamp, ready to paste over the `(auto)` cells. **The author cannot know the key at PR time**, because the tag is minted on merge, so keying is always retrospective; looking up a hash and a UTC timestamp by hand is exactly the step that gets skipped, and CI already knows both. It cannot write the row itself — the caller stub grants `contents: read`, and widening that fleet-wide to save a paste is the wrong trade. Ported here because the fork must match canonical step for step, which `sm-pr`'s drift check now enforces. |
| v0.1.2-develop-020 | 308bf14 | 2026-08-15 00:53 UTC | Greg Gowans | **Bring the inlined PR gate up to the canonical one (#69)** * Bring the inlined PR gate up to the canonical one This repo runs a fork of simplemotion/sm-pr because a public repo cannot call an internal reusable workflow, and a fix there does not reach here — the same gap that let the CI fork keep stamping tags for CHANGE.md-only merges. Two checks were stale or absent. The 5-column check was the header-only version: it matched &#124; Version &#124; lines and never counted cells on a data row, which is how 17 malformed rows across 8 repos survived it fleet-wide. The develop-stream check was not here at all, so the gate made hard across the fleet today did not apply to the one repo that cannot inherit it. Both lifted from canonical verbatim. Two inputs. references adapted: a fork has no per-caller switches, and require_changelog_stream is the literal true it now defaults to. It found real drift on its first run: -017 and -018 were tagged by today's merges with no row. Backfilled here. * Also sync the sm- prefix step The drift check being built in sm-pr found a third divergence while it was being validated: canonical's error message suggests sm_${base#*_} as well as sm_${base%.py}.py for importable modules, and this copy had only the latter. Cosmetic — an error message, not logic — but it is exactly the class of silent divergence the check exists to surface, so it is corrected rather than excused. * Write the pipes in that row as entities The row describing the column check quoted a table header literally, so the row split into seven cells and the very check it describes failed it. Second time today a row about escaped pipes contained one. |
| v0.1.2-develop-019 | 4a97dbc | 2026-08-15 00:30 UTC | Greg Gowans | **Match the canonical guard wording exactly (#68)** simplemotion/sm-ci is gaining a check that compares its develop-tag logic against this repo's inline fork. The fork cannot inherit fixes — a public repo cannot call an internal reusable workflow — and the changelog-only tag guard proved it by having to be hand-copied a day after it landed upstream. That check compares the run: body with comments stripped, so the two may explain themselves differently while the executable logic must match. One line did not: this copy said "no new artefact" where canonical said "no new binary", a deliberate reword because this repo ships no binaries. Canonical now says "no new build artefact", true of both, and this matches it. Twenty-two lines, byte-identical. |
| v0.1.2-develop-018 | bfbecac | 2026-08-15 00:24 UTC | Greg Gowans | **Name the inlined workflows -inline (#67)** sm-ci.yml and sm-pr.yml here are forks of the shared workflows, not the byte-identical caller stubs every other repo carries: this repo is public and both shared workflows are internal, so GitHub refuses the call before any job exists. They were named identically to the stubs anyway, which is exactly the mistake their own headers had to warn against in capital letters. Renamed to sm-ci-inline.yml and sm-pr-inline.yml. The suffix says what the header had to explain. Nothing else changes. Both keep name: CI and name: PR, and check contexts derive from those and the job names rather than the filename — verified against this repo's actual contexts, and main pins no required status check. Both still satisfy the sm- prefix rule. The drift risk is the point: a fix landing in simplemotion/sm-ci does not reach here, as the changelog-only tag guard proved today. A name that reads as a fork makes that obvious. |
| v0.1.2-develop-017 | 6dd17dd | 2026-08-15 00:18 UTC | Greg Gowans | **Add the changelog row for the newly minted tag (#66)** * Derive the changelog from the develop tag stream CHANGE.md now carries a row for every *-develop-NNN tag, with Version, Hash and Date read from the commit that tag points at, so the three cannot drift. kept 6 corrected 0 generated 1 preserved 7 Additive and lossless: rows that were already correct are untouched, rows with a wrong hash or date have only those two cells corrected, and rows for versions with no tag are preserved below the stream. Generated rows take their Notes from the commit subject and body. * Copy sm-ci's changelog-only tag guard into the inlined CI This repo runs an inlined copy of sm-ci rather than calling it: the repo is public and simplemotion/sm-ci is internal, and GitHub refuses that call at startup. So the guard sm-ci gained on 2026-08-14 does not reach here, and it showed: the backfill merge touched CHANGE.md alone yet still stamped v0.1.2-develop-016, which immediately owed a changelog row it could not have carried. Left as is, every changelog fix mints a tag that needs another fix. Fails open, like the original: an uncomputable range stamps rather than silently stopping. Also adds the row for -016 itself. |
| v0.1.2-develop-016 | b0bfaea | 2026-08-15 00:00 UTC | Greg Gowans | **Derive the changelog from the develop tag stream (#65)** * Derive the changelog from the develop tag stream CHANGE.md now carries a row for every *-develop-NNN tag, with Version, Hash and Date read from the commit that tag points at, so the three cannot drift. kept 0 corrected 1 generated 5 preserved 7 Additive and lossless: rows that were already correct are untouched, rows with a wrong hash or date have only those two cells corrected, and rows for versions with no tag are preserved below the stream. Generated rows take their Notes from the commit subject and body. * Repair changelog rows that were not five cells Two defects, neither caught by the hygiene gate: it matches only lines beginning `&#124; Version &#124;`, so it checks that a table DECLARES five columns and never counts cells on a data row. A pipe inside the Notes prose, sometimes bare and sometimes backslash-escaped. Escaped renders correctly but still splits the row for any counter, which is how these survived. Interior pipes are now the HTML entity, which renders as a pipe and contains none. An extra placeholder before the date — `&#124; ver &#124; — &#124; — &#124; date &#124; ...` — putting the date in position 4. The duplicate em-dash is dropped; no cell carrying content was removed. Row text is otherwise untouched. |
| v0.1.2-develop-015 | 0f7c8ec | 2026-08-11 05:50 UTC | Greg Gowans | **Resolve a release by package prefix before falling back to `releases/latest`, so the installer survives a publishing change instead of needing to be deployed in lockstep with one.** The channel repos are shared: `sm-publish-release.yml` names `sm-welcome`'s releases bare (`vX.Y.Z`) because it is the designated primary product and owns `releases/latest`, and gives every other package a `${package}-` prefix. That is deliberate, not drift. **The hazard is what happens if that special case is ever removed.** A bare `releases/latest` on a shared channel returns whichever package published most recently — so an installer relying on it would silently fetch a *different* product's release and install the wrong asset. `--tag-prefix` already existed for the multi-package case, but nothing passed it for `sm-welcome`, whose public one-liner sends only `--channel`. Now, when no `--tag-prefix` is given, the script probes `${PACKAGE}-v` first and only falls back to the bare pointer. One extra API call; correct under either scheme, in either direction, with no coordinated deploy. **Verified against the live API for both shapes**: `sm-client`, `sm-tender` and `sm-govern` each resolve their own prefixed release, and `sm-welcome` falls through to `v0.1.1-develop-006`. **The first test run appeared to show a bug that was not there** — `sm-client` resolving to `sm-simplicity-…`. That was the harness: it called `gh api`, which returns compact JSON, while this script uses `curl` via `gh_api`, and GitHub pretty-prints for `curl`. The line-based `awk` is correct on the real call path. Recorded because the test had to match the call path, not merely the endpoint. |
| v0.1.2-develop-014 | 53e74cd | 2026-08-09 08:06 UTC | Greg Gowans | **Add a PR gate — inlined, because a public repo cannot call an internal reusable workflow (#63)** * Remove the two Windows smoke-test jobs: there is no sm-welcome.exe to install Companion to 3400-0009-SM-Welcome#176, which drops that repo's two *-pc-windows-msvc triples per the fleet decision of 2026-08-05 — stop testing on Windows and stop shipping Windows binaries, rather than shipping untested ones. windows-pwsh and windows-ps51 both ran sm-install.ps1 to fetch sm-welcome.exe from the release channel and asserted provenance plus -V. With no Windows asset published they fail on a missing file, and because this workflow is also on a Monday cron that is a red run every week testing a platform we no longer ship. The two .ps1 entries in the push.paths filter go with them: no job exercises sm-install.ps1 or sm-install-lib.ps1 now, so triggering on their changes only produced a green tick that proved nothing. Restore paths and jobs together if Windows returns. The unix job (ubuntu + macOS) is untouched. Not changed, and needing a decision: sm-install.ps1 and sm-welcome.ps1 are still served from install.simplemotion.com, so a Windows user following the documented one-liner now hits a missing asset rather than a clear "Windows is not supported". That message is a product call. * Add a PR gate — inlined, because a public repo cannot call an internal workflow This repo had no sm-pr.yml at all: pull requests were validated only by CodeQL, so no enterprise hygiene rule was enforced here. The canonical caller stub would not fix that — it would fail at startup. sm-install is public; simplemotion/sm-pr is internal, and GitHub refuses the call before any job is created. Not a prediction: sm-ci.yml in this repo WAS the canonical stub and failed at startup on every push from 2026-07-22 to 2026-07-31 (five runs, zero jobs, no develop tag), and was inlined on 2026-07-31 for exactly this reason. Scope matches what the shared workflow would actually have run here. sm-pr's Rust job needs Cargo.toml + rust-toolchain.toml and this repo has neither, so only hygiene was ever in play; its blocking checks are reproduced step-for-step. The two advisory checks are deliberately not copied: the action-version reporter exists to flag repos without Dependabot (adopted in #61), and the canonical hash pins would rot silently in a local copy. One rename was required to make the gate pass: install-smoke-test.yml -> sm-install-smoke-test.yml, the repo's only sm- prefix violation. A dry run of all seven blocking checks found nothing else. The root-level public entry points are untouched — their names are part of the published install URLs. |
| v0.1.2-develop-013 | 5c145a7 | 2026-08-05 05:07 UTC | Greg Gowans | **Bump action pins to their current major, and add Dependabot (#61)** * Bump action pins to their current major * Bump action pins to their current major * Add Dependabot for GitHub Actions |
| v0.1.2-develop-012 | 6b305d8 | 2026-08-04 03:33 UTC | Greg Gowans | **Add the SimpleMotion banner to the policy files (#60)** * Add the SimpleMotion banner * Add the SimpleMotion banner |
| v0.1.2-develop-011 | 1dcdd10 | 2026-08-03 09:08 UTC | Greg Gowans | **ASSIGN.md: adopt canonical assignment-and-licence text (#59)** |
| v0.1.2-develop-010 | 1d2ed20 | 2026-07-31 07:04 UTC | Greg Gowans | **Inline the CI: a public repo cannot call an internal reusable workflow (#58)** .github/workflows/sm-ci.yml was the canonical caller stub, byte-identical to every other repo's, and it had failed at STARTUP on every push from 2026-07-22 to 2026-07-31 -- five consecutive runs, zero jobs created, so nothing ran and no develop tag was stamped for nine days. Cause: this repo is public and simplemotion/sm-ci is internal. GitHub refuses that call before any job exists. That is also why the workflow's registered name was stuck as the file path rather than CI -- it was never parsed into a successful run. Not billing, despite matching the signature the enterprise home/CLAUDE.md attributes to billing suspension (zero-job startup_failure across many runs): sm-pages succeeded on the same push at the same second, and every private/internal repo runs the shared stub fine. sm-install has to stay public -- it serves install.simplemotion.com and the bootstrap must be fetchable anonymously -- so the CI is inlined instead. Scope is minimal by design. There is no Cargo.toml here, and for a non-Rust repo the shared workflow only ever stamped a develop tag: no build, no attestation, no channel dispatch. Only that is reproduced, with the identical version derivation. id-token/attestations permissions are dropped with the build they existed for; contents: write is retained for the tag. sm-pr.yml is untouched, and a prominent header warns against restoring the stub. Verified: YAML parses (name: CI, jobs version/develop-tag, neither with a uses:), and the extracted version script dry-run against this repo resolves v0.1.2-develop-009 on a main push, with all three tag-push branches warning as intended. |
| (auto) | — | 2026-08-15 | Greg Gowans | **Bring the inlined PR gate up to the canonical one, which it was two fixes behind.** This repo runs a fork of `simplemotion/sm-pr` because a public repo cannot call an internal reusable workflow, and a fix there does not reach here — the same gap that let the CI fork keep stamping tags for `CHANGE.md`-only merges. **Two checks were stale or absent.** The 5-column check was the header-only version: it matched `&#124; Version &#124;` lines and never counted cells on a data row, which is how 17 malformed rows across 8 repos survived it for months fleet-wide. And the develop-stream check — a row for every `*-develop-NNN` tag, `Hash` and `Date` read from the tagged commit — was **not here at all**, so the gate made hard across the fleet on 2026-08-15 did not apply to the one repo that cannot inherit it. Both are now lifted from canonical verbatim, with the two `inputs.` references adapted: a fork has no per-caller switches, and `require_changelog_stream` is the literal `true` it now defaults to. **It found real drift on its first run**, which is the point: `-017` and `-018` were tagged by today's merges with no row, and are backfilled here. |
| (auto) | — | 2026-08-15 | Greg Gowans | **Match the canonical wording exactly, so drift can be detected by comparison.** `simplemotion/sm-ci` is gaining a check that compares its develop-tag logic against this repo's inline fork — the fork cannot inherit fixes, because a public repo cannot call an internal reusable workflow, and the changelog-only tag guard proved it on 2026-08-15 by having to be hand-copied. That check compares the `run:` body with comments stripped, so the two may explain themselves differently while the executable logic must match. One line did not: this copy said *no new artefact* where canonical said *no new binary*, a deliberate reword because this repo ships no binaries. Canonical now says **no new build artefact**, true of both, and this copy matches it. **Twenty-two lines, byte-identical after this.** |
| (auto) | — | 2026-08-15 | Greg Gowans | **Name the inlined workflows `-inline`, so they stop impersonating the canonical caller stubs.** `sm-ci.yml` and `sm-pr.yml` here are forks of the shared workflows, not the byte-identical stubs every other repo carries — this repo is **public** and both shared workflows are **internal**, so GitHub refuses the call before any job exists. They were named identically to the stubs anyway, which is precisely the mistake their own headers had to warn against in capital letters. Renamed to `sm-ci-inline.yml` and `sm-pr-inline.yml`; the `-inline` suffix says what the header had to explain. **Nothing else changes.** The workflows keep `name: CI` and `name: PR`, and check contexts derive from those and the job names, not the filename — verified against this repo's actual contexts (`Repo hygiene`, `CodeQL`, `Analyze (…)`), and `main` pins no required status check today. Both still satisfy the `sm-` prefix rule. **The drift risk is the point:** a fix landing in `simplemotion/sm-ci` does not reach here, as the changelog-only tag guard proved on 2026-08-15 — it was copied in by hand after this repo minted a tag for a `CHANGE.md`-only merge. A name that reads as a fork makes that obvious to the next person. Historical rows below still name the old files; they describe what happened at the time and are left alone. |
| (auto) | — | 2026-08-05 | Greg Gowans | **Add a PR gate — inlined, because a public repo cannot call an internal reusable workflow.** This repo had **no `sm-pr.yml` at all**: pull requests were validated only by CodeQL, so none of the enterprise hygiene rules were enforced here. **The canonical caller stub would not fix that — it would fail at startup.** `sm-install` is `public`; `simplemotion/sm-pr` is `internal`, and GitHub refuses the call before any job is created. That is not a prediction: `sm-ci.yml` in this very repo *was* the canonical stub and failed at startup on every push from 2026-07-22 to 2026-07-31 — five consecutive runs, zero jobs, no develop tag stamped — and was inlined on 2026-07-31 for exactly this reason. Its header carries the full diagnosis, including why billing was ruled out. So the gate is inlined the same way. **Scope matches what the shared workflow would actually have run here:** sm-pr's Rust job is gated on `Cargo.toml` + `rust-toolchain.toml` and this repo has neither, so only the hygiene job was ever in play — its blocking checks are reproduced step-for-step (required top-level files, ASSIGN.md assignment/licence/copyright, `.gitmodules` keys, CHANGE.md version entry, canonical 5-column table, no rendered artefacts, `sm-` prefix on authored scripts and workflows). **Two advisory checks are deliberately not copied:** the ~100-line action-version reporter, whose purpose is to flag repos lacking Dependabot (adopted here in #61), and the canonical hash pins for `ASSIGN.md` and the versioning appendix, which carry SHAs that must be bumped fleet-wide when canonical moves and would rot silently in a local copy. **One rename was required to make the gate pass:** `install-smoke-test.yml` → **`sm-install-smoke-test.yml`**, since the `sm-` prefix rule (DISTRIBUTE.md principle 9) covers `.github/workflows/*.yml` and that was the repo's only violation — a dry run of all seven blocking checks found nothing else. The workflow's `name:` and its own entry in `push.paths` moved with it; no other file referenced it. **The root-level public entry points are untouched and must stay that way** — `sm-install.sh`, `sm-welcome.ps1`, `sm-simplicity.sh` and friends are already `sm-`prefixed, are out of the check's scope, and their names are part of the published install URLs. **Check-name caveat:** the fleet's context is `pr / Repo hygiene` (lowercase, from the caller's job id); an inlined workflow has no caller wrapper, so this emits `PR / Repo hygiene`. No ruleset on this repo requires a status-check context today — the `main` ruleset has `pull_request`, `deletion` and `non_fast_forward` only — so nothing breaks, but any future requirement must name what this file actually emits. |
| (auto) | — | 2026-08-05 | Greg Gowans | **Remove the two Windows smoke-test jobs — there is no `sm-welcome.exe` to install any more.** Companion to `3400-0000-SM-Software/3400-0009-SM-Welcome#176`, which drops that repo's two `*-pc-windows-msvc` triples per Greg's fleet decision of 2026-08-05 (stop testing on Windows *and* stop shipping Windows binaries, rather than shipping untested ones). `windows-pwsh` and `windows-ps51` both ran `sm-install.ps1` to fetch `sm-welcome.exe` from the `release` channel and asserted provenance plus `-V`; with no Windows asset published they would fail on a missing file — and since this workflow is also on a `cron: '17 6 * * 1'` schedule, that would be a **red run every Monday testing a platform we no longer ship**. The `unix` job (ubuntu + macOS) is untouched and still asserts *"Provenance verified"* plus a working binary. **The two `.ps1` entries in the `push.paths` filter go too:** with no job exercising `sm-install.ps1` or `sm-install-lib.ps1`, a run triggered by changing them produced a green tick that proved nothing — worse than no signal. Restore paths and jobs together if Windows ever returns. **Deliberately NOT changed, and worth a decision:** `sm-install.ps1` and `sm-welcome.ps1` are unchanged and still served from `install.simplemotion.com`, so a Windows user following the documented `iwr … &#124; iex` one-liner now hits a missing release asset instead of being told Windows is unsupported. What that message should say is a product call, not a CI one. Note also that this repo has **no `sm-pr.yml` caller**, so pull requests here get no hygiene or lint gate at all — separate gap, not addressed here. |
| (auto) | — | 2026-07-31 | Greg Gowans | **Inline the CI: a public repo cannot call an internal reusable workflow.** `.github/workflows/sm-ci.yml` was the canonical caller stub, byte-identical to every other repo's, and it had failed at **startup** on every push from 2026-07-22 to 2026-07-31 — five consecutive runs, **zero jobs created**, so nothing ran and no develop tag was stamped for nine days. Cause: **this repo is `public` and `simplemotion/sm-ci` is `internal`**, and GitHub refuses that call before any job exists. That is also why the workflow's registered name was stuck as the file path rather than `CI` — it was never parsed into a successful run. **Not billing**, despite matching the signature the enterprise `home/CLAUDE.md` attributes to billing suspension (zero-job `startup_failure` across many runs): `sm-pages` succeeded on the *same push at the same second*, and every private/internal repo runs the shared stub fine. `sm-install` has to stay public — it serves install.simplemotion.com and the bootstrap must be fetchable anonymously — so the CI is inlined. **Scope is minimal by design:** no `Cargo.toml` here, and for a non-Rust repo the shared workflow only ever stamped a develop tag (no build, attestation or channel dispatch), so only that is reproduced, with the identical version derivation — base is one patch past the newest bare GA tag reachable from HEAD, `NNN` counts commits since it, `.sm-version` supplies the base pre-GA. `id-token`/`attestations` permissions dropped with the build they existed for; `contents: write` retained for the tag. `sm-pr.yml` is untouched. A prominent header warns against 'restoring' the stub. Verified: YAML parses (`name: CI`, jobs `version`/`develop-tag`, neither with a `uses:`), and the extracted version script dry-run against this repo resolves `v0.1.2-develop-009` on a main push, with all three tag-push branches warning as intended. |
| (auto) | — | 2026-07-31 | Greg Gowans | **Install `sm-onboard` beside `sm-welcome` in `~/.simplemotion/bin`.** Both `sm-welcome.sh` and `sm-welcome.ps1` now make a second call to the generic installer with `--package sm-onboard`, same `--source-repo`, same channel, same `--asset-suffix short` — so it reuses the existing SHA-256 + sigstore/cosign verification rather than adding a download path. **Why it was needed:** `sm-onboard` is the admin-run onboarding CLI, and `sm-welcome`'s own home-repo step failure tells the operator to run `sm-onboard <cohort> adduser …` — but nothing had ever installed it. It assumed the binary was on `PATH`, and it was not published at all until `simplemotion/sm-ci#28` (the release build never passed `--workspace`, so member binaries were enumerated, not found, and silently dropped). **Guard is `download-happened OR binary-absent`, not just the former.** `sm-welcome.sh`'s fast path skips the download entirely when `sm-welcome` already matches the channel's latest, so gating solely on that would never deliver `sm-onboard` to anyone already up to date — i.e. every existing install. A version comparison is not usable here: `sm-onboard` reports its own crate version (`0.1.0`), not the workspace release tag. **Non-fatal on failure**, deliberately: releases cut before `sm-ci#28` carry no `sm-onboard` asset, so a hard failure would break every install from an existing release, on every channel, until each is re-cut. The message says so explicitly rather than looking like a broken installer. A workstation without `sm-onboard` is fully functional — only admins invoke it. Validated: `bash -n` on the shell script, PowerShell AST parse on the `.ps1`. |
| v0.1.2 | — | 2026-07-30 | Greg Gowans | **Bump `esbuild` 0.24.2 → 0.28.1, clearing the dev-server request-forgery advisory.** Dependabot flagged a moderate alert against `package-lock.json`: esbuild ≤ 0.24.2 lets any website send requests to the running dev server and read the response, fixed in 0.25.0. **The pinned range could never reach the fix** — `^0.24.2` on a `0.x` version is minor-locked (`>=0.24.2 <0.25.0`), so the spec itself had to be raised and a lockfile refresh alone would have been a no-op. Went to the current release rather than the 0.25.0 minimum: `sm-build.ts` uses only `buildSync`, and both `npm run typecheck` and `npm run build` pass on 0.28.1 (both pages built, JS inlined and minified). Also adds `node_modules/` and `_site/` to `.gitignore` — neither was ignored, and both are produced by the install and build this change requires; `_site/` has never been tracked and is built by `sm-pages.yml` in CI. Version row precedes the tag, which is hand-cut at milestones per this repo's policy. |
| v0.1.1 | dc0dc99 | 2026-07-03 09:20 UTC | Greg Gowans | **Bootstrap section prompts auto-accept by default.** `confirm_section` / `Confirm-Section` no longer stop at `Proceed? [Y/n]` before each of the three sm-welcome bootstrap sections — they print the header and continue (matches sm-welcome `v0.1.10` dropping its per-step Proceed gate). `SM_WELCOME_CONFIRM=1` restores the gate; `SM_WELCOME_ASSUME_YES=1` (the old non-interactive override) still forces auto-accept over it, so existing CI/scripted callers are unaffected. `sm-welcome.ps1` forwards `SM_WELCOME_CONFIRM` across the UAC re-exec like its siblings. |
| v0.1.0 | a88e3d9 | 2026-06-17 07:31 UTC | Greg Gowans | Baseline under the enterprise versioning scheme; retired the legacy flat `v0.0.N` tag stream and refreshed this appendix to the build-once / carried-NNN policy. |

---

## Legacy — flat per-commit `v0.0.N` stream (retired 2026-06-17)

Before this baseline `sm-install` used an undocumented flat `v0.0.N` tag stream (`v0.0.07` … `v0.0.36`), one tag per commit, with **no GitHub Releases attached** — Pages serves from `main`, so the tags marked nothing consumers depended on. Those 30 tags were deleted on 2026-06-17 and superseded by the `vX.Y.Z` scheme starting at `v0.1.0`. No history was rewritten; only the dangling tags were removed.

---

# Appendix — Enterprise versioning policy

Adopted 2026-05-12; revised 2026-06-14 to add the per-commit `-develop-` tag stream and the `-release-` candidate stage (superseding the earlier `-cm-` CI-only label), and to add the monorepo-workspace rule (one repo-wide version + a single bare tag, no per-package prefix); revised 2026-06-15 to record develop builds in `CHANGE.md` (one row per notable change, keyed by the `-develop-NNN` tag), clarifying that "no GitHub Release" governs distribution, not changelog listing; reconciled 2026-06-15 to the live channel architecture — `-develop-` publishes to the internal `sm-develop` channel for distribution-surface products (tag/version-only for internal crates), and all channel/distribution specifics are deferred to the Distribution Standard (`9000-…-SM-Govern/CLAUDE.md`) as the single source of truth; revised 2026-06-17 to the **build-once / carried-NNN** model implemented in `simplemotion/sm-ci` — `develop` is the single build (one artifact per commit on `main`), each later stage **promotes that same artifact** so its `-develop-NNN` number is **carried unchanged** up the ladder, and `-release-NNN` is **restored** as a staging candidate (prerelease) finalised to the bare `vX.Y.Z` GA (the only "latest"); revised 2026-07-03 to require every hand-cut named tag to be an **annotated tag object** (`git tag -a` — lightweight tags lose `git describe` priority to CI's annotated develop tags); revised 2026-07-22 to make version derivation **canonical in `simplemotion/sm-ci`** (inlined in its `version` job) rather than a separately-sourced `sm-version.sh`, and to derive the pre-GA develop base from the **crate manifest's `X.Y.Z`** (falling back to `v0.1.0` for repos with no parseable version) instead of a hardcoded `v0.1.0`. revised 2026-07-29 to allow an **admin-authorised retraction** of the tag anti-patterns, subject to the never-consumed checks and a `CHANGE.md` record. revised 2026-07-29 to fix the changelog table format — `Version | Hash | Date | Author | Notes`, with the commit hash required on every entry, dates carrying UTC time (`YYYY-MM-DD HH:MM UTC`) and never local, and the author always the full `user.name`. Supersedes the 4-component `W.X.Y.Z` scheme used before. This section is reproduced verbatim in every SimpleMotion repo's `CHANGE.md` so each file is self-contained.

## TL;DR

```
vX.Y.Z-develop-NNN   dev build          (per-commit on main, or per-bump in a workspace — the ONE build)
vX.Y.Z-testing-NNN   testing            (promoted from develop — same NNN, same artifact)
vX.Y.Z-preview-NNN   preview            (public candidate — same NNN)
vX.Y.Z-release-NNN   release candidate  (staging — same NNN; prerelease, never "latest")
vX.Y.Z               GA release         (published version — finalised from one -release-NNN; the only "latest")
```

Lifecycle, least → most mature: **develop → testing → preview → release → GA**. The
build happens **once**, at `develop`; every later stage *promotes that same artifact*,
so the build's **`NNN` is carried unchanged** up the ladder (same `NNN` = same bytes).
`-release-NNN` is a staging candidate (a prerelease) living in the release channel;
one chosen candidate is finalised to the bare `vX.Y.Z` **GA**, which is the only tag
GitHub marks "latest" — every `-<stage>-NNN` is a prerelease.

**Distribution is out of scope here.** Which channel/repo each suffix routes to,
its visibility, and how consumers install it are defined by the **Distribution
Standard** (`9000-…-SM-Govern/CLAUDE.md` — the single source of truth for
channels). This appendix governs only the **version/tag semantics**.

- `X.Y.Z` is strict SemVer 2.0.0.
- `NNN` is zero-padded to three digits (`001` … `999`).
- Every prerelease targets the *next* version, so `vX.Y.Z-<stage>-NNN` < `vX.Y.Z` — the GA tag always sorts highest. This is the only load-bearing ordering invariant.
- `-develop-NNN` is stamped automatically on **every commit on `main`** (one tag per commit). It is the **single build**: CI builds the artifact once at this stage. (Whether that artifact becomes a downloadable Release is a distribution concern — see the Distribution Standard.)
- **`NNN` is carried UNCHANGED up the ladder.** `-testing-NNN`, `-preview-NNN` and `-release-NNN` reuse the **same `NNN`** as the `-develop-NNN` they were promoted from — same number means the same bytes. There is no per-stage counter; the develop number *is* the build identity, all the way to the GA it finalises into.
- **Develop builds are recorded in `CHANGE.md`** — one row per notable change (or version bump), keyed by the `-develop-NNN` tag of the commit that shipped it. The changelog tracks the work regardless of distribution. (Named `-testing-`/`-preview-`/`-release-NNN` tags, once cut, are recorded the same way.)
- **Ordering caveat:** the prerelease stage words sort *alphabetically* (`develop` < `preview` < `release` < `testing`), which is NOT the lifecycle order — `testing` sorts highest despite being least mature. Stages are picked by **suffix-string matching**, never by sort order, so this is harmless. Never rely on "highest prerelease = most mature."

**Channel access** is defined by the **Distribution Standard** (`9000-…-SM-Govern/CLAUDE.md` §4–§6), the single source of truth for the channel→repo mapping, visibility, and consumer install access. In brief: `preview` and GA are public; `testing`, `develop` and the `-release-NNN` staging candidates are internal. The tag suffix is the routing key (`-develop-`/`-testing-`/`-preview-`/`-release-`, plus bare `vX.Y.Z` for GA). This appendix does not restate the channel list — that's how the two docs previously drifted.

## Timeline of a release cycle

```
tag                    stage     notes
────────────────────   ───────   ─────────────────
v0.1.0                 GA        latest stable
v0.1.1-develop-001     develop   per-commit (or per-bump) dev build — CI builds the artifact
v0.1.1-develop-002     develop   …
v0.1.1-develop-003     develop   work continues on main
v0.1.1-testing-003     testing   promote develop-003 → testing (SAME NNN, same bytes)
v0.1.1-preview-003     preview   promote testing-003 → preview (public candidate)
v0.1.1-release-003     release   promote preview-003 → release staging candidate (prerelease)
v0.1.1                 GA        finalise release-003 → bare GA (the only "latest")
v0.1.2-develop-001     develop   next dev cycle
```

**Rule:** `-develop-NNN` is stamped per commit on `main` (single-binary repos, CI-owned) or per bump (workspaces, manifest-sourced); its base is *one patch ahead* of the most recent reachable GA release and `NNN` counts commits since that release. The build happens **only** at develop. The later stages are **promotions** of one chosen develop build, each reusing that build's `NNN`: `-testing-NNN` → `-preview-NNN` → `-release-NNN` (a prerelease staging candidate) → bare `vX.Y.Z` GA. **GA reuses no suffix** and is finalised from a chosen `-release-NNN`; it is the only tag marked "latest". (Not every develop build is promoted — you pick which one enters the ladder, but its number rides along unchanged.)

## Why `-develop` / `-testing` / `-preview` / `-release` and not `+`-metadata

Both are valid per SemVer 2.0.0, but they differ in precedence semantics:

| Slot | Sorts? | Example |
|---|---|---|
| Pre-release (`-`) | Yes — affects comparison | `0.1.1-preview-001` < `0.1.1` |
| Build metadata (`+`) | No — ignored by comparators | `0.1.0+preview-001` ≡ `0.1.0` |

The `-` form is the only choice that lets any tool (Cargo, npm, pip, GitHub's "Latest" picker, `semver-cli`) correctly order pre-release tags below their target release. We accept the consequence that **`-develop-NNN`, `-testing-NNN`, `-preview-NNN` and `-release-NNN` all belong to the *next* version**, not the most recent release — they are all prereleases that sort below the bare `vX.Y.Z` GA, which is why GA alone is "latest".

## Tagging commands

The develop build is the only tag pushed in the *source* repo. Everything above
it is a **promotion** that reuses the same `NNN` — the resulting tags (and the
mechanism that creates them) are the Distribution Standard's concern. The tag
*sequence* for one shipped build, end to end:

```
v0.1.1-develop-003     # AUTOMATIC — CI builds + tags this on a commit to main;
                       #             you never tag develop by hand.
v0.1.1-testing-003     # promote develop-003 → testing   (same NNN)
v0.1.1-preview-003     # promote testing-003 → preview   (same NNN)
v0.1.1-release-003     # promote preview-003 → release   (same NNN; prerelease staging)
v0.1.1                 # finalise release-003 → GA       (bare; the only "latest")
```

- **`-develop-NNN` is never tagged by hand** on single-binary repos — CI owns it. (In a workspace it's advanced by the bump helper — see the monorepo rule.)
- **Never invent a new `NNN` for a later stage.** The promotion carries the develop build's number unchanged — `-testing-`/`-preview-`/`-release-` all share the `-develop-NNN` they came from. Same number = same artifact.
- **Three-digit zero-padding** is mandatory. Without it, `-release-10` sorts before `-release-2` lexically.
- **Every hand-cut tag is annotated** — `git tag -a vX.Y.Z -m "…"` (likewise `-testing-`/`-preview-`/`-release-NNN`), never lightweight. Annotated tags carry tagger/date and take `git describe` priority; a lightweight GA on a commit that also bears CI's annotated `-develop-NNN` tag describes as the develop twin instead of the GA. CI's auto-cut develop tags are already annotated.
- **Never move a tag once pushed.** Promote a *new* develop build (new `NNN`) if you need to revise; cut a new patch for GA. Retraction is possible only with admin authorisation and the never-consumed checks — see *Yanking a broken release*.
- **Only the develop tag originates on `main`** (or a `release/v*.x` branch). The cut stages are promotions; they don't add new source-repo tags.

## Version computation in CI

Version derivation is **owned by the canonical reusable workflow `simplemotion/sm-ci`** (inlined in its `version` job); repos consume it via the one-line caller stub, with no separately-sourced script. It computes:

- The current tag verbatim if HEAD is on a `v*` tag (a clean GA tag is preferred over a prerelease pointing at the same commit).
- Otherwise `<base>-develop-<count>` where `<base>` is one patch ahead of the most recent clean GA release reachable from HEAD, and `<count>` is commits since that release.
- Before the first GA release (no reachable `vX.Y.Z` tag), `<base>` is the crate manifest's `X.Y.Z` (the `Cargo.toml` version before any `-develop` suffix), falling back to **`v0.1.0`** only when no version is parseable (e.g. non-Rust / config repos); `<count>` is commits from the root, so the initial dev stream is `<manifest X.Y.Z>-develop-NNN` (never `v0.0.x`).

See the `version` job of the `simplemotion/sm-ci` reusable workflow for the implementation.

## Monorepo workspaces (multiple crates / packages in one repo)

A repo with several packages (a Cargo workspace, an npm monorepo, …) carries
**one repo-wide version**, never a version per package. On the develop stream a
monorepo manages that version **in the manifests** (the manifest is the source
of truth), rather than deriving it in CI as a single-binary repo does:

- **One unified version in every manifest.** Each package's `Cargo.toml` /
  `package.json` carries the **same** `X.Y.Z-develop-NNN`. They move together so
  they promote to GA in lockstep. The manifest version is the source of truth.
- **One bare tag per bump.** A single `vX.Y.Z-develop-NNN` tags the whole repo —
  never per-package prefixes (`<crate>-v…`), and **no package/binary name in the
  tag or the version string**. (A program's `--version` banner naturally prints
  its own name, e.g. `sm-mcp-xero 0.1.0-develop-NNN`; that's the program
  identifier, not part of the version.)
- **A workspace bump helper advances the counter.** One command (e.g.
  `cargo xtask bump-develop`) rewrites every manifest to the next
  `-develop-NNN` (`NNN = max(manifest versions, existing tags) + 1`), refreshes
  the lockfile, commits, and creates the bare tag — keeping manifest ⇿ git tag ⇿
  each binary's `--version` (`CARGO_PKG_VERSION`) in lockstep.

**Why this differs from the single-package default.** For one shipped binary
the develop stream is **CI-owned** — auto-stamped per commit, version derived
by `simplemotion/sm-ci` from the manifest's base `X.Y.Z`. A workspace of
internal, cargo-installed crates instead keeps the unified version **in the
manifests** and advances it with the bump helper: every crate gets one coherent
version that `cargo`, the git tag, and `--version` all agree on, without
per-package CI bookkeeping. Both satisfy the invariant (one repo-wide version,
bare tags, no package name). Pick **one** model per repo and record the choice
in the repo's `CLAUDE.md`. Either way the develop build is the only source-repo
tag; the later stages are promotions of it that carry the same `NNN`.

## CI: version derivation + the develop tag

The canonical implementation is the reusable workflow **`simplemotion/sm-ci`**
(callers add a one-line stub — see its README). Two pieces of it are versioning's
concern; build and promotion are distribution's (below).

1. **Version derivation.** On a `v*` tag the version is the tag verbatim; on an
   untagged commit it is the next develop build:
   - `<base>-develop-<count>`, where `<base>` is one patch ahead of the most
     recent reachable clean GA release and `<count>` counts commits since it;
   - before the first GA (no reachable `vX.Y.Z` tag) `<base>` is the crate
     manifest's `X.Y.Z` (falling back to **`v0.1.0`** when unparseable, e.g.
     non-Rust / config repos) and `<count>` counts commits from the root.
2. **The develop tag.** Every push to `main` stamps `v<next>-develop-NNN` — CI
   owns it (a `GITHUB_TOKEN` push, so it never recursively re-triggers). In a
   workspace the bump helper advances it instead (see the monorepo rule).

The stage classifier (all `-<stage>-NNN` are prereleases; bare `vX.Y.Z` is GA):

```bash
if [[ "$GITHUB_REF" == refs/tags/v* ]]; then
  TAG="${GITHUB_REF#refs/tags/}"; VERSION="$TAG"
  case "$TAG" in
    *-develop-*) STAGE=develop ;;
    *-testing-*) STAGE=testing ;;
    *-preview-*) STAGE=preview ;;
    *-release-*) STAGE=release ;;   # prerelease staging candidate
    *)           STAGE=ga ;;        # bare vX.Y.Z — the only "latest"
  esac
else                                # untagged commit on main → next develop build
  VERSION="$(derive_develop)"; STAGE=develop  # inlined in simplemotion/sm-ci; see "Version computation"
fi
```

**Build & promotion are out of scope here** (they're distribution): `sm-ci`
builds the artifact **once** at the develop stage and dispatches it to the
`sm-develop` channel; each higher stage is a *promotion* run from that channel
repo's `sm-promote.yml`, carrying the same `NNN`, up to the GA finalise. The
retired per-repo `sm-release.yml` and any local `gh release` step are **not**
used — they would bypass the build-once split. See the Distribution Standard and
`sm-ci`'s README for the mechanics.

## Changelog format

One row per **notable change** — keyed by the `-develop-NNN` tag of the commit that shipped it, or by a named GA / release / preview / testing tag once one is cut. Trivial commits (typo- or format-only) need not get a row; the per-commit `-develop-NNN` tag stream plus the commit log remain the full audit trail.

**Table columns**, in this order — the same shape the pre-2026-05-12 tables used:

```
| Version | Hash | Date | Author | Notes |
```

- **Version** — the tag keying the row, or `—` where the change shipped without one.
- **Hash** — the **abbreviated commit hash** (7 chars) of the commit that shipped it. Required for every entry: the tag alone does not identify a commit once tags are re-cut or withdrawn, and rows keyed `—` have no other anchor.
- **Date** — UTC, `YYYY-MM-DD HH:MM UTC`. **Always UTC, never local.** Derive it with `TZ=UTC git log --date=format-local:'%Y-%m-%d %H:%M UTC'`; `--date=format-local` alone renders *local* time and will silently mislabel it (an AEST author is +10, so it lands ten hours off).
- **Author** — **always the full name**, exactly as configured in `user.name` for that repo's identity (e.g. `Greg Gowans`, never `Greg`). The changelog author must match the commit author it describes.
- **Notes** — one line, or a fuller paragraph for a notable change.

**Backfilling older rows.** Where a row predates this format and its commit cannot be identified — the tag was never cut, or the row is keyed by a product version rather than a git tag — put `—` in **Hash** and leave the date at whatever precision is known. **Never guess a hash or a time**: a wrong hash is worse than an absent one, because it points confidently at the wrong commit.

**Edits per change:**

1. **Develop:** land the commit on `main`; CI stamps its `-develop-NNN` tag automatically (never tag develop by hand). Prepend one row to the changelog table with that tag, the abbreviated commit hash, date (UTC `YYYY-MM-DD HH:MM UTC`), author (full name), and a one-line note.
2. **Named stages:** when you cut a testing / preview / release / GA tag by hand, push it and add its row the same way. When a candidate promotes to GA, all rows remain (audit trail of the cycle).
3. **Never edit a row after its tag is published.** Append a new row instead.

## Release branches and hotfixes

Long-lived branch per minor version, created when you commit to LTS for that line:

```
main                ●──●──●──●──●──●──●──●──●──●─────────●──●
                     \                                   /
                      \                            cherry-pick
                       \                                /
release/v0.1.x          ●──●──●─────●────────●─────────────●
                        │            │        │              │
                       v0.1.0       v0.1.1   v0.1.1-preview-1 v0.1.2
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

The one exception: a pre-release tag that **never escaped CI** (no external pull, no registry publish) can be safely deleted. Default to superseding anyway — `-preview-002` costs nothing.

**Admin-authorised retraction.** An organisation admin may explicitly authorise one of the anti-patterns above — most often deleting a tag cut prematurely, or withdrawing a GA that turns out not to be ready to release. This is an *authorisation*, not a safety argument: none of the technical risks above go away, so it is only appropriate where the tag demonstrably has not been consumed.

Before acting, confirm all four:

1. **No GitHub Release** exists for the tag (a tag alone distributes nothing; a Release does).
2. **No registry publish** happened from this repo for that version.
3. **Nothing could have fetched it** — for a private repo, no forks, watchers or network; for a public one, assume it *was* fetched and supersede instead.
4. **It was not promoted** to a later stage (`-testing-`/`-preview-`/`-release-`/GA carrying the same `NNN`).

Then **record the retraction in `CHANGE.md`** — which admin authorised it, the date, and the four checks — so the tag's disappearance is visible in the record instead of looking like it silently vanished. Re-cutting the same version number for different content remains forbidden regardless of authorisation: retract, then move to a *new* number.

If any of the four fails, the admin's authorisation does not make it safe. Supersede.

## Migration from the legacy `W.X.Y.Z` scheme

Each repo's `CHANGE.md` is migrated as follows:

1. Replace the old single-table file with this three-part structure (changelog → legacy → policy appendix).
2. Copy this policy appendix verbatim into every repo's `CHANGE.md` so each file is self-contained.
3. Move all existing entries below the `## Legacy` divider verbatim — no rewriting of historical versions.
4. The first new tag a repo cuts under this scheme is `v0.1.0` (or higher if the repo is past beta and the maintainer chooses an appropriate major). Do **not** continue numbering from the legacy `v0.0.1.NN` sequence.

## Validation

A repo conforms to this policy when:

- Tags matching `v[0-9]+\.[0-9]+\.[0-9]+(-(develop|testing|preview|release)-[0-9]{3})?` are the only version tags — i.e. `-develop-`/`-testing-`/`-preview-`/`-release-` each carry a 3-digit `NNN`, and bare `vX.Y.Z` is GA. (Legacy `-cm-` / `-rc-` / suffixless `-release` trigger tags from before 2026-06-17 remain valid but no new ones are cut.)
- A given `NNN` is shared by the develop build and every stage promoted from it (same `NNN` = same artifact); no stage invents its own counter.
- Every hand-cut named tag (testing / preview / release / GA) is an annotated tag object (`git cat-file -t <tag>` → `tag`), never a lightweight commit ref.
- `CHANGE.md` carries the changelog table at the top and this policy appendix at the bottom, with legacy entries (if any) between them under a divider.
- The changelog table carries the columns `Version | Hash | Date | Author | Notes`; every row has a hash (or an explicit `—`), every date is UTC with time, and every author is a full name.
- The repo's CI is the canonical `simplemotion/sm-ci` (version derivation + develop tag + build-once at develop); promotions up the ladder are each channel repo's `sm-promote.yml`. No local publish/`gh release` step.
- No commit on `main` or a release branch is tagged with the retired `W.X.Y.Z` format.
