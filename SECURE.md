# SECURE — simplemotion/install

> Security posture, threat model, and consumer verification recipe for `simplemotion/install`.

## What this repo serves

This is the **public** installer-script home for SimpleMotion binary distribution, served at `install.simplemotion.com` (GitHub Pages on `main`). It hosts:

- `sm-install.sh` / `sm-install.ps1` — generic installer base (resolves channel → repo, downloads, verifies, installs).
- `sm-welcome.sh` / `sm-welcome.ps1` — onboarding-CLI wrapper.
- `sm-simplicity.sh` / `sm-simplicity.ps1` — Simplicity-product wrapper.
- `sm-welcome/index.html` — landing page.

Binaries themselves are **not** stored here. They live in `simplemotion/{release,preview,private,testing}`.

## Threat model

- **Adversary substitutes the installer.** GitHub serves `*.sh` / `*.ps1` over TLS; consumers pinned to `install.simplemotion.com` get the CNAME-anchored repo.
- **Adversary substitutes the binary.** Mitigated by SHA verification of the published `.sha256` sidecar and by sigstore build-provenance verification against the per-product source repo (e.g., `3400-0000-SM-Software/3400-0009-SM-Welcome` for `sm-welcome`).
- **Adversary publishes a malicious preview release.** Preview channel is documented as early-access and may regress. `release` channel consumers are unaffected because they pull from a different repo entirely (`simplemotion/release` vs `simplemotion/preview`).
- **Adversary smuggles a binary into a private channel.** Internal channels (`private`, `testing`) require authed `gh` with read access to the relevant private repo; external attackers without SimpleMotion credentials cannot reach those release assets.

## Secrets handling

- No credentials are committed to this repo.
- Release-publishing credentials live in the per-product source repos and their GitHub Actions secrets.
- All SimpleMotion credentials follow the `b64:<base64-payload>` envelope convention.

## Consumer verification

If you've downloaded a SimpleMotion release binary and want to verify its provenance before running it, follow this recipe. Independent verification is the same step SimpleMotion takes during release smoke-tests.

### What we sign

Every release asset published on `simplemotion/release` / `preview` / `private` / `testing` ships with two sidecar files:

- `<asset>.sha256` — SHA256 hash for transport-integrity verification.
- `<asset>.sigstore.jsonl` — sigstore build-provenance bundle, anchoring the binary to a specific GitHub Actions workflow run in the per-product source repo.

The bundle is offline-verifiable: the Sigstore TUF root and Fulcio cert chain travel inside the bundle, so verification works without GitHub API access and without a GitHub account.

### Recipe

Requires `gh` ≥ 2.55 (`brew install gh`, or fetch a static build from <https://github.com/cli/cli/releases>).

```bash
# 1. Pick channel + product + platform.
CHANNEL=release                   # release | preview | private | testing
PRODUCT=sm-welcome                # or sm-simplicity, etc.
TRIPLE=aarch64-apple-darwin       # see asset list for available triples
TAG=v0.1.26                       # see https://github.com/simplemotion/${CHANNEL}/releases
BASE="https://github.com/simplemotion/${CHANNEL}/releases/download/${TAG}"

# Per-product source repo (anchors the attestation's cert-identity).
case "$PRODUCT" in
  sm-welcome)    SOURCE_REPO=3400-0000-SM-Software/3400-0009-SM-Welcome ;;
  sm-simplicity) SOURCE_REPO=3400-0000-SM-Software/3400-0026-SM-Simplicity ;;
esac

# 2. Download all three files for your platform.
curl -fLO "${BASE}/${PRODUCT}-${TRIPLE}"
curl -fLO "${BASE}/${PRODUCT}-${TRIPLE}.sha256"
curl -fLO "${BASE}/${PRODUCT}-${TRIPLE}.sigstore.jsonl"

# 3. Verify SHA256 (transport integrity).
shasum -a 256 -c "${PRODUCT}-${TRIPLE}.sha256"
#   expected: <triple>: OK

# 4. Verify sigstore attestation (build provenance).
gh attestation verify "${PRODUCT}-${TRIPLE}" \
    --bundle "${PRODUCT}-${TRIPLE}.sigstore.jsonl" \
    --repo "${SOURCE_REPO}"
#   expected: ✓ Verification succeeded!
```

### What verification proves

A successful `gh attestation verify` proves:

- The binary was built by a GitHub Actions workflow in the named source repo.
- The workflow ran on a specific commit, tag, and run ID — visible in the verbose output (`--format json`).
- The binary has not been modified since signing.

### What it does not prove

- It does not prove the source code is itself benign — that is transitively trusted via SimpleMotion's source-repo access controls (2FA-required org policy, branch protection).
- It does not defend against a compromise of GitHub itself, Sigstore's Fulcio CA, or Sigstore's Rekor transparency log.
- It does not detect tampering after install. Once a binary is on your machine, your OS's security model owns it.

### Failure modes

| Symptom | Likely cause |
|---|---|
| `cosign signature not found` | Bundle file is corrupt; re-download. |
| `certificate identity does not match` | You're verifying against the wrong `--repo`. Use the value listed for your product. |
| `transparency log entry not found` | Bundle is too old (>3 months from a retired Rekor shard) or never made it to Rekor. File an issue. |
| `gh: command not found` | Install `gh` first: `brew install gh` on macOS, or download from <https://github.com/cli/cli/releases>. |
| `error creating Sigstore verifier` | gh's TUF cache is corrupt. Fix: `rm -rf ~/.sigstore` and retry. |

## Reporting issues

Email **security@simplemotion.com** for any vulnerability discovered in this repo or in the installer flow.
