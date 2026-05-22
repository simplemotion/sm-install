#!/usr/bin/env bash
# SimpleMotion generic binary installer base (macOS + Linux).
#
# Resolves a SimpleMotion-published binary from a GitHub Releases-hosting
# repo, verifies SHA256 + sigstore attestation via cosign (installed to
# ~/.local/bin by sm-welcome.sh's Section 1, with GitHub's Sigstore TUF
# root initialized in $TUF_ROOT), and either installs it to a PATH
# directory or execs it from a temp file.
#
# Usage (typically called by a thin per-product wrapper):
#   sm-install.sh --package NAME [options] [-- ARGS...]
#
# Required flags:
#   --package NAME               Binary name + asset prefix. The release
#                                asset is `<package>-<host-triple>` (no
#                                .exe on this script; .ps1 adds it).
#
# Optional flags:
#   --channel release|preview|private|testing
#                                Channel to resolve into a tag. Each
#                                channel maps to its own GitHub repo:
#                                  release → simplemotion/release  (public)
#                                  preview → simplemotion/preview  (public)
#                                  private → simplemotion/private  (private — needs authed gh)
#                                  testing → simplemotion/testing  (private — needs authed gh)
#                                Default: $SM_CHANNEL or 'release'.
#   --repo OWNER/NAME            Override the channel→repo default.
#                                Useful for development or hosting on a
#                                non-SimpleMotion repo.
#   --source-repo OWNER/NAME     Repo the attestation is signed against
#                                (anchors the cosign cert-identity check).
#                                Defaults to --repo.
#   --tag-prefix PREFIX          For channel repos that host multiple
#                                packages, filter the releases list to
#                                tags starting with PREFIX (e.g.
#                                `sm-simplicity-v`). Default: no filter
#                                (single-package channel — use
#                                `releases/latest` directly).
#   --asset-suffix triple|short  Asset-name suffix style:
#                                  triple = `<package>-<arch>-<os>` (default;
#                                           e.g. `sm-x-aarch64-apple-darwin`)
#                                  short  = `<package>-<os>-<arch>` with the
#                                           short OS/arch codes — `mac`/`lin`
#                                           and `arm64`/`x64` (e.g.
#                                           `sm-x-mac-arm64`).
#                                Each style needs the publisher to ship
#                                matching asset names; ARM64 + x86_64 are
#                                expected for all three OSes under `short`.
#   --mode install|run|install-and-run
#                                install         = drop in install dir, exit.
#                                run             = exec from temp file
#                                                  (no persistent install).
#                                install-and-run = install AND exec from
#                                                  the install path; args
#                                                  after `--` are forwarded
#                                                  to the binary.
#                                Default: install.
#   --install-dir PATH           install mode only. Resolution order:
#                                --install-dir > $SM_INSTALL_DIR >
#                                ~/.simplemotion/bin (if --package starts
#                                with "sm-") or ~/.local/bin (otherwise).
#                                SimpleMotion CLIs share a dedicated dir;
#                                third-party packages use the XDG default.
#   --version TAG                Pin a specific tag, skipping channel
#                                resolution.
#   --                           End of flag parsing; remaining args are
#                                passed through to the binary in run mode.

set -euo pipefail

# Source the shared install-toolchain library (confirm_section,
# find_cosign, ensure_cosign, initialize_cosign_tuf). sm-welcome.sh
# loads the same lib at startup, so functions are consistent across
# the bootstrap and standalone-install code paths.
eval "$(curl -fsSL https://install.simplemotion.com/sm-install-lib.sh)"

# Route tempfiles under ~/SimpleMotion/.tmpdir before the first mktemp.
# Standalone invocations (sm-welcome.sh has already set this, but
# sm-install.sh is also invoked from other entrypoints — sm-simplicity,
# future tools — and must self-route. Idempotent.) See sm-install-lib.sh.
sm_route_tmpdir

# Surface the dirs we and the sm-welcome Rust binary install into so
# `command -v` finds our own tools (cosign, sm-welcome, future helpers)
# on the *first* run, before any rc-file PATH export has had a chance
# to take effect in a new login shell.
export PATH="$HOME/.simplemotion/bin:$HOME/.local/bin:$PATH"

REPO=""
PACKAGE=""
SOURCE_REPO=""
TAG_PREFIX=""
MODE="install"
INSTALL_DIR=""
VERSION=""
CHANNEL="${SM_CHANNEL:-release}"
ASSET_SUFFIX="triple"
BIN_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)         REPO="$2"; shift 2 ;;
        --package)      PACKAGE="$2"; shift 2 ;;
        --source-repo)  SOURCE_REPO="$2"; shift 2 ;;
        --tag-prefix)   TAG_PREFIX="$2"; shift 2 ;;
        --mode)         MODE="$2"; shift 2 ;;
        --install-dir)  INSTALL_DIR="$2"; shift 2 ;;
        --version)      VERSION="$2"; shift 2 ;;
        --channel)      CHANNEL="$2"; shift 2 ;;
        --asset-suffix) ASSET_SUFFIX="$2"; shift 2 ;;
        --)             shift; BIN_ARGS=("$@"); break ;;
        -h|--help)
            sed -n '2,/^set -euo pipefail$/p' "$0" | sed -n 's/^# \{0,1\}//p' >&2
            exit 0
            ;;
        *) echo "Unknown flag: $1 (try --help)" >&2; exit 1 ;;
    esac
done

if [[ -z "$PACKAGE" ]]; then
    echo "sm-install.sh: --package is required (try --help)" >&2
    exit 1
fi
# --repo is optional: defaults from --channel below.
case "$MODE" in
    install|run|install-and-run) ;;
    *) echo "sm-install.sh: --mode must be 'install', 'run', or 'install-and-run' (got: $MODE)" >&2; exit 1 ;;
esac

# Channel → repo defaulting. Four channels each get their own repo, so
# `releases/latest` on each is unambiguous and there's no prerelease
# flag dance. `--repo` overrides for development / external use.
case "$CHANNEL" in
    release|preview|private|testing) ;;
    *) echo "sm-install.sh: unknown --channel: $CHANNEL (use release|preview|private|testing)" >&2; exit 1 ;;
esac
if [[ -z "$REPO" ]]; then
    REPO="simplemotion/${CHANNEL}"
fi

SOURCE_REPO="${SOURCE_REPO:-$REPO}"
# Default install dir varies by package: sm-* products share
# ~/.simplemotion/bin; everything else falls back to the XDG default.
if [[ -z "$INSTALL_DIR" ]]; then
    if [[ -n "${SM_INSTALL_DIR:-}" ]]; then
        INSTALL_DIR="$SM_INSTALL_DIR"
    elif [[ "$PACKAGE" == sm-* ]]; then
        INSTALL_DIR="$HOME/.simplemotion/bin"
    else
        INSTALL_DIR="$HOME/.local/bin"
    fi
fi

# Host triple + short OS/arch codes (used by --asset-suffix=short).
OS_KERNEL=$(uname)
case "$OS_KERNEL" in
    Darwin) OS="apple-darwin";      OS_SHORT="mac" ;;
    Linux)  OS="unknown-linux-gnu"; OS_SHORT="lin" ;;
    *) echo "Unsupported OS: $OS_KERNEL (only macOS and Linux; use sm-install.ps1 on Windows)" >&2; exit 1 ;;
esac
ARCH=$(uname -m)
case "$ARCH" in
    arm64|aarch64) ARCH="aarch64"; ARCH_SHORT="arm64" ;;
    x86_64|amd64)  ARCH="x86_64";  ARCH_SHORT="x64" ;;
    *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac
TARGET="${ARCH}-${OS}"
case "$ASSET_SUFFIX" in
    triple) SUFFIX="${TARGET}" ;;
    short)  SUFFIX="${OS_SHORT}-${ARCH_SHORT}" ;;
    *) echo "sm-install.sh: --asset-suffix must be 'triple' or 'short' (got: $ASSET_SUFFIX)" >&2; exit 1 ;;
esac
ASSET="${PACKAGE}-${SUFFIX}"

# Resolve tag. With channel-per-repo, each repo has its own
# `releases/latest` and we never use the prerelease flag, so:
#   - Single-package channel repos: hit /releases/latest directly.
#   - Multi-package channel repos (--tag-prefix set): scan the releases
#     list and pick the newest tag matching the prefix; releases/latest
#     may belong to a different package in the same repo.
if [[ -z "$VERSION" ]]; then
    if [[ -n "$TAG_PREFIX" ]]; then
        RELEASES_JSON=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases")
        TAG=$(awk -v prefix="$TAG_PREFIX" '
                  /"tag_name":/ {
                      if ($0 ~ ("\"" prefix)) { print $0; exit }
                  }' <<<"$RELEASES_JSON" \
              | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
    else
        TAG=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
              | awk -F'"' '/"tag_name":/ {print $4; exit}')
    fi
    if [[ -z "${TAG:-}" ]]; then
        echo "No release available for $PACKAGE in $REPO (channel=$CHANNEL)" >&2
        exit 1
    fi
else
    TAG="$VERSION"
fi

URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"

# TTY-aware colours.
if [[ -t 1 ]]; then
    GREEN=$'\e[92m'; RED=$'\e[91m'; DIM=$'\e[38;5;244m'; BOLD=$'\e[1m'; RESET=$'\e[0m'; ERASE=$'\r\e[K'
else
    GREEN=''; RED=''; DIM=''; BOLD=''; RESET=''; ERASE=''
fi

TMPBIN=$(sm_mktemp)
TMPSUM=$(sm_mktemp)
# Use the canonical sigstore-bundle suffix on the temp file (cosign and
# gh both reject paths without `.json`/`.jsonl`). Clean up both the
# suffixed and bare mktemp paths.
TMPATT_RAW=$(sm_mktemp)
TMPATT="${TMPATT_RAW}.sigstore.jsonl"
trap 'rm -f "$TMPBIN" "$TMPSUM" "$TMPATT" "$TMPATT_RAW"' EXIT

# Step numbering — matches sm-welcome's `[NN/TOTAL]` counter so the
# Download phase and the binary's onboarding steps read as one
# continuous numbered sequence (01..TOTAL). Defaults to 20 (= 5
# download-phase steps + 15 onboarding steps); the wrapper script
# (sm-welcome.sh) exports SM_WELCOME_STEPS_TOTAL to keep these in lock-step.
STEPS_TOTAL="${SM_WELCOME_STEPS_TOTAL:-20}"
fmt_step() {
    # $1 = 1-based step index, $2 = width-zero-padded
    printf '[%02d/%s]' "$1" "$STEPS_TOTAL"
}

# Phase header — matches sm-welcome's `phase_header` formatting so the
# download output frames as one continuous workflow. Rule width is
# 36 - len("Download") = 28 dashes (same formula as the Rust side).
printf '\n  %s──%s %sDownload%s %s────────────────────────────%s\n' \
    "$DIM" "$RESET" "$BOLD" "$RESET" "$DIM" "$RESET"

printf '  [%s✓%s] %s Platform: %s (channel=%s, tag=%s)\n' \
    "$GREEN" "$RESET" "$(fmt_step 1)" "$TARGET" "$CHANNEL" "$TAG"

# Download binary.
if [[ -t 1 ]]; then
    printf '  [*] %s Downloading %s...' "$(fmt_step 2)" "$PACKAGE"
else
    printf '  [*] %s Downloading %s...\n' "$(fmt_step 2)" "$PACKAGE"
fi
if ! curl -fsSL "$URL" -o "$TMPBIN"; then
    printf '%s  [%s✗%s] Failed to download %s\n' "$ERASE" "$RED" "$RESET" "$URL" >&2
    exit 1
fi
printf '%s  [%s✓%s] %s Downloaded %s\n' "$ERASE" "$GREEN" "$RESET" "$(fmt_step 2)" "$ASSET"

# Download + verify SHA256.
if ! curl -fsSL "${URL}.sha256" -o "$TMPSUM"; then
    printf '  [%s✗%s] Failed to download %s.sha256\n' "$RED" "$RESET" "$URL" >&2
    exit 1
fi
expected=$(awk 'NR==1 {print $1}' "$TMPSUM")
if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$TMPBIN" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
    actual=$(shasum -a 256 "$TMPBIN" | awk '{print $1}')
else
    echo "  [${RED}✗${RESET}] Neither sha256sum nor shasum available — cannot verify download" >&2
    exit 1
fi
if [[ "$expected" != "$actual" ]]; then
    printf '  [%s✗%s] SHA256 mismatch for %s: expected %s, got %s\n' "$RED" "$RESET" "$ASSET" "$expected" "$actual" >&2
    exit 1
fi
printf '  [%s✓%s] %s Checksum verified %s(SHA256: %s)%s\n' "$GREEN" "$RESET" "$(fmt_step 3)" "$DIM" "$actual" "$RESET"

# Default TUF_ROOT if Section 1 hasn't been through (e.g., sm-install.sh
# invoked standalone).
: "${TUF_ROOT:=$HOME/.simplemotion/sigstore}"
export TUF_ROOT

# Attestation check — cosign-only. Verification of GitHub-issued
# attestations needs cosign pointed at GitHub's private Sigstore TUF
# plus the GH-Sigstore-shaped flag set: TSA timestamps instead of Rekor
# inclusion proofs, no SCTs on the leaf cert, SLSA-v1 predicate type.
# Bundle present + cosign rejects is fatal. Bundle present + cosign
# missing skips (SHA256 above still anchors integrity).
#
# Self-bootstrap cosign if it's missing (sm-install.sh may be called
# directly without sm-welcome.sh's Section 1 having provisioned it).
# Both ensure_cosign and initialize_cosign_tuf come from sm-install-lib.sh.
find_cosign || true
if curl -fsSL "${URL}.sigstore.jsonl" -o "$TMPATT" 2>/dev/null; then
    if [[ -z "$COSIGN_BIN" ]]; then
        printf '      [*] cosign not on disk — bootstrapping...\n'
        if ensure_cosign; then
            initialize_cosign_tuf "$COSIGN_BIN" >/dev/null 2>&1 || true
        fi
    fi
fi
if [[ -s "$TMPATT" ]] && [[ -n "$COSIGN_BIN" ]]; then
    cert_id_regex="https://github.com/${SOURCE_REPO}/\.github/workflows/.*"
    if "$COSIGN_BIN" verify-blob-attestation \
        --bundle "$TMPATT" \
        --new-bundle-format \
        --use-signed-timestamps \
        --insecure-ignore-tlog \
        --insecure-ignore-sct \
        --type slsaprovenance1 \
        --certificate-identity-regexp "$cert_id_regex" \
        --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
        "$TMPBIN" >/dev/null 2>&1; then
        printf '  [%s✓%s] %s Provenance verified (cosign, signed by %s)\n' "$GREEN" "$RESET" "$(fmt_step 4)" "$SOURCE_REPO"
    else
        printf '  [%s✗%s] %s Provenance verification failed (cosign rejected the bundle)\n' "$RED" "$RESET" "$(fmt_step 4)" >&2
        exit 1
    fi
elif [[ -z "$COSIGN_BIN" ]]; then
    printf '  [%s-%s] %s Provenance check skipped (cosign not installed)\n' "$DIM" "$RESET" "$(fmt_step 4)"
else
    printf '  [%s-%s] %s Provenance check skipped (no sigstore bundle on release)\n' "$DIM" "$RESET" "$(fmt_step 4)"
fi

chmod +x "$TMPBIN"

# Install-receipt: a per-package TOML at `~/.simplemotion/install-receipt/<package>.toml`
# recording the channel, tag, source-repo, asset SHA, and timestamp of
# this install. Consumed by the binary's own `update` subcommand so
# subsequent refreshes target the channel the user actually installed
# from (instead of defaulting to `release` and downgrading users on
# `preview`/`private`/`testing`). Written best-effort: failure to create
# the receipt is logged but does not abort the install.
write_receipt() {
    local pkg="$1" channel="$2" tag="$3" source_repo="$4" sha="$5"
    local dir="$HOME/.simplemotion/install-receipt"
    local file="$dir/$pkg.toml"
    local ts
    # ISO-8601 UTC; portable across BSD `date` (macOS) and GNU `date` (Linux).
    ts=$(date -u +'%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) || ts="unknown"
    if ! mkdir -p "$dir" 2>/dev/null; then
        printf '  [%s!%s] could not create %s — receipt skipped\n' "$DIM" "$RESET" "$dir" >&2
        return 0
    fi
    if ! cat > "$file" <<EOF
schema       = 1
package      = "$pkg"
channel      = "$channel"
tag          = "$tag"
source_repo  = "$source_repo"
asset_sha256 = "$sha"
installed_at = "$ts"
installer    = "sm-install.sh"
EOF
    then
        printf '  [%s!%s] could not write %s — receipt skipped\n' "$DIM" "$RESET" "$file" >&2
    fi
}

install_to_dir() {
    mkdir -p "$INSTALL_DIR"
    install -m 0755 "$TMPBIN" "${INSTALL_DIR}/${PACKAGE}"
    write_receipt "$PACKAGE" "$CHANNEL" "$TAG" "$SOURCE_REPO" "$actual"
    printf '  [%s✓%s] %s Installed %s to %s/%s\n' "$GREEN" "$RESET" "$(fmt_step 5)" "$PACKAGE" "$INSTALL_DIR" "$PACKAGE"
    case ":$PATH:" in
        *":$INSTALL_DIR:"*) ;;
        *) printf '  [%s!%s] %s is not on $PATH — add it to your shell init to run %s directly\n' "$DIM" "$RESET" "$INSTALL_DIR" "$PACKAGE" ;;
    esac
}

exec_binary() {
    local bin="$1"
    # Hand off /dev/tty if available so the binary can prompt interactively
    # even when this script was started via `curl | bash`.
    if (: </dev/tty) 2>/dev/null; then
        exec "$bin" ${BIN_ARGS[@]+"${BIN_ARGS[@]}"} < /dev/tty
    else
        exec "$bin" ${BIN_ARGS[@]+"${BIN_ARGS[@]}"}
    fi
}

case "$MODE" in
    install)
        install_to_dir
        ;;
    run)
        exec_binary "$TMPBIN"
        ;;
    install-and-run)
        install_to_dir
        exec_binary "${INSTALL_DIR}/${PACKAGE}"
        ;;
esac
