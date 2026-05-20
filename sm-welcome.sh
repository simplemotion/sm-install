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

printf '\n  SimpleMotion — Development Environment Onboarding\n  ══════════════════════════════════════════════════\n\n'
cat <<'EOF'
  Welcome. This bootstrap runs in three sections, each gated by a
  Y/n prompt so you can review before anything is changed:

    1. Prerequisites  —  verifies git, curl, bash, and cosign are
                         present. No auto-installs on macOS/Linux —
                         missing tools are flagged so you can install
                         them before continuing.
    2. sm-welcome     —  download, SHA256-check, and attestation-verify
                         sm-welcome, then install.
    3. Launch         —  exec sm-welcome in this shell.

  We'll start with Section 1 next.

EOF

# Per-section gate. Prints a framed header + description, then blocks on
# read until the user confirms. Default = Yes (Enter accepts). Any other
# response aborts the entire bootstrap.
confirm_section() {
    local title="$1"
    shift
    local pad
    pad=$(( 56 - ${#title} ))
    if (( pad < 0 )); then pad=0; fi
    printf '\n  ── %s ' "$title"
    printf -- '─%.0s' $(seq 1 "$pad")
    printf '\n\n'
    while [[ $# -gt 0 ]]; do
        printf '      %s\n' "$1"
        shift
    done
    printf '\n'
    if [[ -n "${SM_WELCOME_ASSUME_YES:-}" ]]; then
        printf '  [+] Proceeding (SM_WELCOME_ASSUME_YES set)\n'
        return 0
    fi
    local resp
    # The curl|bash entrypoint redirects stdin to the script body, so
    # read explicitly from /dev/tty when available to reach the user.
    if (: </dev/tty) 2>/dev/null; then
        read -r -p "  Proceed? [Y/n] " resp </dev/tty || resp=''
    else
        read -r -p "  Proceed? [Y/n] " resp || resp=''
    fi
    resp="$(printf '%s' "$resp" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    case "$resp" in
        ''|y|yes) return 0 ;;
        *) printf '  [!] Aborted by user.\n' >&2; exit 1 ;;
    esac
}

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
while [[ $# -gt 0 ]]; do
    case "$1" in
        --channel)
            if [[ $# -lt 2 ]]; then
                echo "sm-welcome.sh: --channel requires a value (release|preview)" >&2
                exit 1
            fi
            CHANNEL_ARG=(--channel "$2"); CHANNEL_VAL="$2"; shift 2
            ;;
        *)
            BIN_ARGS+=("$1"); shift
            ;;
    esac
done

INSTALL_DIR="${SM_INSTALL_DIR:-$HOME/.simplemotion/bin}"
LOCAL_BIN="${INSTALL_DIR}/sm-welcome"

# Bootstrap a working cosign into ~/.local/bin/cosign without Homebrew or
# sudo. Fetches the binary + checksums via GitHub's /releases/latest/
# download/ redirect (no API call, no rate-limit, no pinned fallback to
# keep current), SHA256-verifies, and chmods. Sets COSIGN_BIN on success.
ensure_cosign() {
    COSIGN_BIN=""
    local cosign_dir="$HOME/.local/bin"
    local local_cosign="${cosign_dir}/cosign"
    if [[ -x "$local_cosign" ]]; then
        COSIGN_BIN="$local_cosign"; return 0
    fi

    local cosign_os cosign_arch
    case "$(uname -s)" in
        Darwin) cosign_os=darwin ;;
        Linux)  cosign_os=linux  ;;
        *) printf '      [-] cosign bootstrap skipped (unsupported OS)\n'; return 1 ;;
    esac
    case "$(uname -m)" in
        x86_64|amd64)  cosign_arch=amd64 ;;
        arm64|aarch64) cosign_arch=arm64 ;;
        *) printf '      [-] cosign bootstrap skipped (unsupported arch)\n'; return 1 ;;
    esac

    local cosign_asset="cosign-${cosign_os}-${cosign_arch}"
    local cosign_url="https://github.com/sigstore/cosign/releases/latest/download/${cosign_asset}"
    local sums_url="https://github.com/sigstore/cosign/releases/latest/download/cosign_checksums.txt"

    local tmp_bin tmp_sums
    tmp_bin=$(mktemp); tmp_sums=$(mktemp)
    if ! curl -fsSL "$cosign_url" -o "$tmp_bin" 2>/dev/null \
       || ! curl -fsSL "$sums_url" -o "$tmp_sums" 2>/dev/null; then
        rm -f "$tmp_bin" "$tmp_sums"
        printf '      [-] cosign bootstrap skipped (download failed)\n'
        return 1
    fi

    local expected actual
    expected=$(awk -v a="$cosign_asset" '$2 == a {print $1; exit}' "$tmp_sums")
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$tmp_bin" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "$tmp_bin" | awk '{print $1}')
    else
        rm -f "$tmp_bin" "$tmp_sums"
        printf '      [-] cosign bootstrap skipped (no sha256 tool)\n'
        return 1
    fi
    if [[ -z "$expected" || "$expected" != "$actual" ]]; then
        rm -f "$tmp_bin" "$tmp_sums"
        printf '      [-] cosign bootstrap skipped (SHA256 mismatch on sigstore/cosign asset)\n'
        return 1
    fi

    mkdir -p "$cosign_dir"
    mv "$tmp_bin" "$local_cosign"
    chmod 0755 "$local_cosign"
    rm -f "$tmp_sums"
    COSIGN_BIN="$local_cosign"
    return 0
}

# Point cosign at GitHub's Sigstore TUF repo so it can verify GitHub-issued
# attestations natively. Cosign walks the TUF chain from 1.root.json,
# fetches the current trusted_root.json (containing GitHub's Fulcio CA +
# TSA pubkeys), and caches everything under $TUF_ROOT. Idempotent.
initialize_cosign_tuf() {
    local cosign="$1"
    [[ -n "$cosign" ]] || return 1
    mkdir -p "$TUF_ROOT"
    local tmp_root
    tmp_root=$(mktemp)
    if ! curl -fsSL "https://tuf-repo.github.com/1.root.json" -o "$tmp_root" 2>/dev/null; then
        rm -f "$tmp_root"
        printf '      [-] cosign TUF init skipped (couldn'\''t fetch 1.root.json)\n'
        return 1
    fi
    if "$cosign" initialize --mirror "https://tuf-repo.github.com" --root "$tmp_root" >/dev/null 2>&1; then
        rm -f "$tmp_root"
        return 0
    fi
    rm -f "$tmp_root"
    printf '      [-] cosign TUF init failed\n'
    return 1
}

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

PREREQ_LINES=(
    "Checks the shell environment and bootstraps cosign as a 100% local"
    "(per-user) install under ~/.local/bin. Any system-wide cosign from"
    "Homebrew / apt / dnf is deliberately ignored — only the copy we"
    "provision here is used by Section 2 and by sm-welcome going forward."
    ""
    "  git     clones the employee repo and most sm-welcome submodule work"
    "          (flagged if missing; not auto-installed — needs sudo / Xcode CLT)"
    "  curl    used to fetch everything else; required to continue"
    "  bash    the script you're reading is bash; sm-welcome assumes 3.2+"
    "  cosign  fetched from sigstore/cosign's /releases/latest/download/"
    "          redirect, SHA256-verified against cosign_checksums.txt,"
    "          installed to ~/.local/bin/cosign (no Homebrew, no sudo)."
    "          After install we run `cosign initialize --mirror"
    "          https://tuf-repo.github.com` so cosign can verify GitHub-"
    "          issued attestations natively (no gh in the chain). The"
    "          TUF cache lands in ~/.simplemotion/sigstore."
    ""
    "Detected state:"
    "  git:    $GIT_STATE"
    "  curl:   $CURL_STATE"
    "  bash:   $BASH_STATE ($BASH_VERSION)"
    "  cosign: $COSIGN_STATE"
)
confirm_section "Section 1 of 3: Prerequisites" "${PREREQ_LINES[@]}"

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

SM_LINES=(
    "Downloads and verifies sm-welcome from simplemotion/$CHANNEL_VAL before"
    "any code from the release channel runs:"
    ""
    "  1. Fetch the binary plus two sidecar files:"
    "       <asset>.sha256             content checksum"
    "       <asset>.sigstore.jsonl     sigstore build-provenance bundle"
    "  2. Hash the binary; compare against the .sha256 file."
    "  3. Verify the sigstore bundle with cosign against GitHub's Sigstore"
    "     TUF (set up in Section 1) — checks the bundle's cert identity"
    "     matches the 3400-0009-SM-Welcome source repo."
    "  4. Move the verified binary to $INSTALL_DIR."
    ""
    "The binary is never installed or invoked until all checks pass."
    ""
)
if [[ $SKIP_DOWNLOAD -eq 1 ]]; then
    SM_LINES+=("Status: fast-path skip — local $LOCAL_VER matches latest on channel=$CHANNEL_VAL.")
elif [[ -n "$LOCAL_VER" && -n "$LATEST_VER" ]]; then
    SM_LINES+=("Status: local $LOCAL_VER → installing $LATEST_VER (channel=$CHANNEL_VAL).")
elif [[ -n "$LATEST_VER" ]]; then
    SM_LINES+=("Status: installing $LATEST_VER (channel=$CHANNEL_VAL).")
else
    SM_LINES+=("Status: installing latest (channel=$CHANNEL_VAL).")
fi
confirm_section "Section 2 of 3: sm-welcome" "${SM_LINES[@]}"

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
LAUNCH_LINES=(
    "Execs sm-welcome in this shell. Forwarded args: ${BIN_ARGS[*]:-(none)}"
    ""
    "  binary: $LOCAL_BIN"
    ""
    "sm-welcome takes over from here — it'll install Claude Code, gh CLI,"
    "Rust, and clone your employee repository as part of its own onboarding"
    "steps (each surfaced with its own step counter)."
)
confirm_section "Section 3 of 3: Launch" "${LAUNCH_LINES[@]}"

exec_local() {
    if (: </dev/tty) 2>/dev/null; then
        exec "$LOCAL_BIN" ${BIN_ARGS[@]+"${BIN_ARGS[@]}"} </dev/tty
    else
        exec "$LOCAL_BIN" ${BIN_ARGS[@]+"${BIN_ARGS[@]}"}
    fi
}
exec_local
