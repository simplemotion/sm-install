#!/usr/bin/env bash
# SimpleMotion onboarding bootstrap (macOS + Linux).
# Thin wrapper around sm-install.sh — fetches sm-welcome and execs it.
#
# Usage (command substitution buffers the script before bash starts, so
# the trailing `exec` never closes a still-active curl pipe — the (56)
# 'Failure writing output' message that pipe/process-sub forms emit is
# gone):
#   bash -c "$(curl -fsSL https://install.simplemotion.com/sm-welcome.sh)" sm-welcome
#   bash -c "$(curl -fsSL https://install.simplemotion.com/sm-welcome.sh)" sm-welcome --email me@example.com
#   SM_CHANNEL=preview bash -c "$(curl -fsSL https://install.simplemotion.com/sm-welcome.sh)" sm-welcome
#
# Channel selection via SM_CHANNEL (release | preview); default release.
#
# Clean re-install: --clean (or SM_WELCOME_CLEAN=1) deletes ~/.local/bin/
# {cosign,pwsh-7,git}, ~/.simplemotion, and ~/.sm-welcome.toml before
# Section 1 so the bootstrap rebuilds from scratch. ~/.local at large is
# left alone on Unix because it's the XDG user-install root and likely
# contains unrelated packages (pip --user, cargo bin, etc.).
#
# Three interactive sections, each gated by a Y/n prompt and prefaced by
# a splash explaining the section in detail:
#   1. Prerequisites — verify git, curl, bash are present; auto-install
#                      cosign via direct sigstore/cosign release download
#                      + SHA256-verify into ~/.local/bin/cosign (no sudo,
#                      no Homebrew); then run `cosign initialize` against
#                      GitHub's Sigstore TUF so cosign can verify GitHub-
#                      issued attestations natively. Missing git/curl
#                      are flagged but not auto-installed (sudo / Xcode).
#   2. sm-welcome    — download sm-welcome from the selected channel,
#                      verify SHA256 + sigstore build-provenance (cosign,
#                      installed in Section 1). Fast-paths if the local
#                      copy is already at the latest tag.
#   3. Launch        — exec sm-welcome in the current shell.
#
# Non-interactive override: set SM_WELCOME_ASSUME_YES=1 to auto-accept
# every section prompt (used by CI / unattended re-runs).

set -euo pipefail

# Per-SimpleMotion TUF cache so we don't clobber any existing public-good
# Sigstore trust under ~/.sigstore. Exported so sm-install.sh picks it up.
export TUF_ROOT="${TUF_ROOT:-$HOME/.simplemotion/sigstore}"

printf '\n  SimpleMotion — Development Environment Onboarding\n  ══════════════════════════════════════════════════\n'

# Source the shared install-toolchain library. Brings in confirm_section,
# find_cosign, ensure_cosign, initialize_cosign_tuf. sm-install.sh loads
# the same lib when it runs in Section 2.
eval "$(curl -fsSL https://install.simplemotion.com/sm-install-lib.sh)"

# Route tempfiles under ~/SimpleMotion/.tmpdir so curl-to-mktemp writes
# don't hit the macOS /var/folders/.../T/ failure modes (EDR scans,
# sandbox boundaries, periodic cleanup). See sm-install-lib.sh for the
# function body + rationale.
sm_route_tmpdir

# sm-welcome's step-counter UI accounts for the bootstrap's pre-binary
# steps via env vars the binary reads (banner suppression + offset).
export SM_WELCOME_NO_BANNER=1
export SM_WELCOME_STEPS_OFFSET=5
# Binary has 14 internal steps on Unix (Linux + macOS share the same
# step set; the Windows-only 06-shell slot is in STEPS_WIN only).
# Bootstrap contributes 5 silent steps. 5 + 14 = 19.
# Update if the binary's Unix step count changes.
export SM_WELCOME_STEPS_TOTAL=19

# Pre-parse our own flags: --channel goes to sm-install.sh; everything
# else forwards to the sm-welcome binary. SM_CHANNEL env var also
# still works (sm-install.sh respects it as a default).
CHANNEL_ARG=()
CHANNEL_VAL="${SM_CHANNEL:-release}"
BIN_ARGS=()
CLEAN=0
if [[ -n "${SM_WELCOME_CLEAN:-}" ]]; then CLEAN=1; fi
while [[ $# -gt 0 ]]; do
    case "$1" in
        --channel)
            if [[ $# -lt 2 ]]; then
                echo "sm-welcome.sh: --channel requires a value (release|preview)" >&2
                exit 1
            fi
            CHANNEL_ARG=(--channel "$2"); CHANNEL_VAL="$2"; shift 2
            ;;
        --clean)
            CLEAN=1; shift
            ;;
        *)
            BIN_ARGS+=("$1"); shift
            ;;
    esac
done

INSTALL_DIR="${SM_INSTALL_DIR:-$HOME/.simplemotion/bin}"
LOCAL_BIN="${INSTALL_DIR}/sm-welcome"

# Optional clean wipe. --clean (or SM_WELCOME_CLEAN=1) deletes the
# SimpleMotion-owned bootstrap locations on disk so Section 1 rebuilds
# from scratch. We scope to specific paths under ~/.local (rather than
# ~/.local wholesale) because that dir is the XDG user-install root on
# Unix and likely contains unrelated packages (pip --user, cargo, etc.).
if [[ $CLEAN -eq 1 ]]; then
    printf '\n  [!] --clean set — wiping prior bootstrap state\n'
    for p in \
        "$HOME/.local/bin/cosign" \
        "$HOME/.local/bin/pwsh-7" \
        "$HOME/.local/bin/git" \
        "$HOME/.simplemotion" \
        "$HOME/.sm-welcome.toml"; do
        if [[ -e "$p" ]]; then
            rm -rf "$p"
            printf '      removed %s\n' "$p"
        fi
    done
fi

# (ensure_cosign and initialize_cosign_tuf come from sm-install-lib.sh.)

# ── Section 1: Prerequisites ──────────────────────────────────────────
detect_state() {
    if command -v "$1" >/dev/null 2>&1; then
        printf 'present (%s)' "$(command -v "$1")"
    else
        printf 'missing'
    fi
}
GIT_STATE=$(detect_state git)
CURL_STATE=$(detect_state curl)
BASH_STATE=$(detect_state bash)
# cosign is a SimpleMotion-managed tool — we deliberately ignore any
# system-wide cosign (Homebrew / apt / dnf) and use only the one we
# install ourselves at ~/.local/bin/cosign.
if [[ -x "$HOME/.local/bin/cosign" ]]; then
    COSIGN_STATE="present ($HOME/.local/bin/cosign)"
else
    COSIGN_STATE="missing"
fi

confirm_section "Section 1 of 3: Prerequisites"

# Hard-stop only if curl is missing — without it we can't fetch anything.
if [[ "$CURL_STATE" == "missing" ]]; then
    printf '  [x] curl is required to continue. Install it via your package manager.\n' >&2
    exit 1
fi
if [[ "$GIT_STATE" == "missing" ]]; then
    printf '  [!] git not found — sm-welcome will report this in its preflight.\n'
fi
if [[ "$COSIGN_STATE" == "missing" ]]; then
    printf '  [*] Installing cosign (sigstore/cosign latest, SHA256-verified)...\n'
    if ensure_cosign; then
        printf '  [v] cosign installed: %s\n' "$COSIGN_BIN"
    else
        printf '  [!] cosign install failed — Section 2 will skip attestation verification (SHA256 still anchors integrity).\n'
    fi
else
    COSIGN_BIN="$HOME/.local/bin/cosign"
fi
if [[ -n "${COSIGN_BIN:-}" ]]; then
    printf '  [*] Initializing cosign TUF trust (tuf-repo.github.com)...\n'
    if initialize_cosign_tuf "$COSIGN_BIN"; then
        printf '  [v] cosign TUF initialized in %s\n' "$TUF_ROOT"
    else
        printf '  [!] cosign TUF init failed — Section 2 will skip attestation verification.\n'
    fi
fi

# ── Section 2: sm-welcome ─────────────────────────────────────────────
# Fast-path resolution: if the binary is already on disk, ask the channel
# repo for the latest tag. If they match, skip the download entirely.
SKIP_DOWNLOAD=0
LOCAL_VER=""
LATEST_VER=""
if [[ -z "${SM_WELCOME_SKIP_FAST_PATH:-}" && -x "$LOCAL_BIN" ]]; then
    LOCAL_VER=$("$LOCAL_BIN" -V 2>/dev/null | awk '{print $2}' | sed 's/^v//')
    case "$CHANNEL_VAL" in
        release|preview|private|testing) CHANNEL_REPO="simplemotion/${CHANNEL_VAL}" ;;
        *) CHANNEL_REPO="" ;;
    esac
    LATEST_TAG=""
    if [[ -n "$CHANNEL_REPO" ]]; then
        LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/${CHANNEL_REPO}/releases/latest" 2>/dev/null \
            | awk -F'"' '/"tag_name":/ {print $4; exit}' || true)
    fi
    LATEST_VER="${LATEST_TAG#v}"
    if [[ -n "$LOCAL_VER" && -n "$LATEST_VER" && "$LOCAL_VER" == "$LATEST_VER" ]]; then
        SKIP_DOWNLOAD=1
    fi
fi

confirm_section "Section 2 of 3: sm-welcome"

if [[ $SKIP_DOWNLOAD -eq 0 ]]; then
    INSTALL_SH=$(curl -fsSL "https://install.simplemotion.com/sm-install.sh")
    bash -c "$INSTALL_SH" sm-install \
        --package sm-welcome \
        --asset-suffix short \
        --source-repo 3400-0000-SM-Software/3400-0009-SM-Welcome \
        --mode install \
        ${CHANNEL_ARG[@]+"${CHANNEL_ARG[@]}"}
fi

# ── Section 3: Launch ─────────────────────────────────────────────────
confirm_section "Section 3 of 3: Launch"

exec_local() {
    if (: </dev/tty) 2>/dev/null; then
        exec "$LOCAL_BIN" ${BIN_ARGS[@]+"${BIN_ARGS[@]}"} </dev/tty
    else
        exec "$LOCAL_BIN" ${BIN_ARGS[@]+"${BIN_ARGS[@]}"}
    fi
}
exec_local
