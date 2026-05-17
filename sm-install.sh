#!/usr/bin/env bash
# SimpleMotion generic binary installer base (macOS + Linux).
#
# Resolves a SimpleMotion-published binary from a GitHub Releases-hosting
# repo, verifies SHA256 (and attestation if `gh` is authed), and either
# installs it to a PATH directory or execs it from a temp file.
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
#                                (anchors cert-identity in `gh attestation
#                                verify`). Defaults to --repo.
#   --tag-prefix PREFIX          For channel repos that host multiple
#                                packages, filter the releases list to
#                                tags starting with PREFIX (e.g.
#                                `sm-simplicity-v`). Default: no filter
#                                (single-package channel — use
#                                `releases/latest` directly).
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

# Surface the dirs we and the sm-welcome Rust binary install into so
# `command -v` finds our own tools (gh, sm-welcome, future helpers) on
# the *first* run, before any rc-file PATH export has had a chance to
# take effect in a new login shell.
export PATH="$HOME/.simplemotion/bin:$HOME/.local/bin:$PATH"

REPO=""
PACKAGE=""
SOURCE_REPO=""
TAG_PREFIX=""
MODE="install"
INSTALL_DIR=""
VERSION=""
CHANNEL="${SM_CHANNEL:-release}"
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

# Host triple.
OS_KERNEL=$(uname)
case "$OS_KERNEL" in
    Darwin) OS="apple-darwin" ;;
    Linux)  OS="unknown-linux-gnu" ;;
    *) echo "Unsupported OS: $OS_KERNEL (only macOS and Linux; use sm-install.ps1 on Windows)" >&2; exit 1 ;;
esac
ARCH=$(uname -m)
case "$ARCH" in
    arm64|aarch64) ARCH="aarch64" ;;
    x86_64|amd64)  ARCH="x86_64" ;;
    *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac
TARGET="${ARCH}-${OS}"
ASSET="${PACKAGE}-${TARGET}"

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

TMPBIN=$(mktemp)
TMPSUM=$(mktemp)
# `gh attestation verify --bundle` rejects any file whose extension
# isn't `.json` or `.jsonl` (with "Error: bundle file extension not
# supported"), so a bare mktemp path won't work. Append the canonical
# sigstore-bundle suffix; clean up both the suffixed and bare paths.
TMPATT_RAW=$(mktemp)
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
printf '  [%s✓%s] %s Checksum verified\n' "$GREEN" "$RESET" "$(fmt_step 3)"

# Ensure a usable `gh` is on disk before attempting attestation. Runs
# unconditionally so the bootstrap pays the one-time ~10s cost now
# rather than on the next release that ships a bundle. Subsequent runs
# find gh via the prepended `~/.local/bin` on PATH and skip the
# download. Result lands in GH_BIN; empty string = bootstrap failed,
# attestation skips.
ensure_gh() {
    GH_BIN=""
    if command -v gh >/dev/null 2>&1; then
        GH_BIN=$(command -v gh); return 0
    fi
    # Match the Rust sm-welcome step's location (installer.rs:60),
    # so we don't fork a second canonical gh path across the bootstrap.
    local gh_dir="$HOME/.local/bin"
    local local_gh="${gh_dir}/gh"
    printf '  [%s*%s] Bootstrapping gh (kept at %s/gh for future runs)...\n' "$DIM" "$RESET" "$gh_dir"
    local gh_tag gh_ver gh_os gh_arch gh_ext gh_asset gh_url gh_sums_url gh_tmp gh_sums_tmp gh_expected gh_actual
    # Try the live cli/cli releases API first; fall back to a known-good
    # pinned version if it fails (anonymous API rate-limit is 60/hr/IP and
    # easy to hit when this script runs alongside other gh-using tooling).
    # Bump the fallback periodically.
    local GH_PIN="v2.89.0"
    gh_tag=$(curl -fsSL "https://api.github.com/repos/cli/cli/releases/latest" 2>/dev/null \
        | awk -F'"' '/"tag_name":/ {print $4; exit}') || gh_tag=""
    if [[ -z "$gh_tag" ]]; then
        printf '  [%s-%s] cli/cli release lookup failed (rate-limited?); using pinned %s\n' "$DIM" "$RESET" "$GH_PIN"
        gh_tag="$GH_PIN"
    fi
    gh_ver="${gh_tag#v}"
    case "$OS" in
        apple-darwin)      gh_os="macOS"; gh_ext="zip"    ;;
        unknown-linux-gnu) gh_os="linux"; gh_ext="tar.gz" ;;
        *) printf '  [%s-%s] gh bootstrap skipped (unsupported OS)\n' "$DIM" "$RESET"; return 1 ;;
    esac
    case "$ARCH" in
        aarch64) gh_arch="arm64" ;;
        x86_64)  gh_arch="amd64" ;;
        *) printf '  [%s-%s] gh bootstrap skipped (unsupported arch)\n' "$DIM" "$RESET"; return 1 ;;
    esac
    gh_asset="gh_${gh_ver}_${gh_os}_${gh_arch}.${gh_ext}"
    gh_url="https://github.com/cli/cli/releases/download/${gh_tag}/${gh_asset}"
    gh_sums_url="https://github.com/cli/cli/releases/download/${gh_tag}/gh_${gh_ver}_checksums.txt"
    gh_tmp=$(mktemp); gh_sums_tmp=$(mktemp)
    if ! curl -fsSL "$gh_url" -o "$gh_tmp" 2>/dev/null \
       || ! curl -fsSL "$gh_sums_url" -o "$gh_sums_tmp" 2>/dev/null; then
        rm -f "$gh_tmp" "$gh_sums_tmp"
        printf '  [%s-%s] gh bootstrap skipped (download failed)\n' "$DIM" "$RESET"; return 1
    fi
    gh_expected=$(awk -v a="$gh_asset" '$2 == a {print $1; exit}' "$gh_sums_tmp")
    if command -v sha256sum >/dev/null 2>&1; then
        gh_actual=$(sha256sum "$gh_tmp" | awk '{print $1}')
    else
        gh_actual=$(shasum -a 256 "$gh_tmp" | awk '{print $1}')
    fi
    if [[ -z "$gh_expected" || "$gh_expected" != "$gh_actual" ]]; then
        rm -f "$gh_tmp" "$gh_sums_tmp"
        printf '  [%s-%s] gh bootstrap skipped (SHA256 mismatch on cli/cli asset)\n' "$DIM" "$RESET"; return 1
    fi
    mkdir -p "$gh_dir"
    case "$gh_ext" in
        zip)    unzip -p "$gh_tmp" "gh_${gh_ver}_${gh_os}_${gh_arch}/bin/gh" >"$local_gh" 2>/dev/null ;;
        tar.gz) tar  -xzOf "$gh_tmp" "gh_${gh_ver}_${gh_os}_${gh_arch}/bin/gh" >"$local_gh" 2>/dev/null ;;
    esac
    chmod 0755 "$local_gh" 2>/dev/null
    rm -f "$gh_tmp" "$gh_sums_tmp"
    if [[ -x "$local_gh" ]]; then
        GH_BIN="$local_gh"
        printf '  [%s✓%s] Installed gh %s to %s\n' "$GREEN" "$RESET" "$gh_ver" "$local_gh"
        return 0
    fi
    printf '  [%s-%s] gh bootstrap skipped (extraction failed)\n' "$DIM" "$RESET"; return 1
}

# Attestation check, two paths in order of preference:
#   1. Offline bundle (`<asset>.sigstore.jsonl`) — no API, no auth.
#   2. API lookup against the source repo — needs authed gh with read
#      access (SimpleMotion staff only).
# Verification failure on path 1 is fatal; missing bundle plus unauthed
# / unreadable source repo is a skip (SHA256 still anchors integrity).
ensure_gh
if [[ -n "$GH_BIN" ]]; then
    if curl -fsSL "${URL}.sigstore.jsonl" -o "$TMPATT" 2>/dev/null; then
        if "$GH_BIN" attestation verify "$TMPBIN" --bundle "$TMPATT" --repo "$SOURCE_REPO" >/dev/null 2>&1; then
            printf '  [%s✓%s] %s Provenance verified (offline bundle, signed by %s)\n' "$GREEN" "$RESET" "$(fmt_step 4)" "$SOURCE_REPO"
        else
            printf '  [%s✗%s] %s Provenance bundle present but failed verification (signed by %s)\n' "$RED" "$RESET" "$(fmt_step 4)" "$SOURCE_REPO" >&2
            exit 1
        fi
    elif "$GH_BIN" auth status >/dev/null 2>&1 \
         && "$GH_BIN" attestation verify "$TMPBIN" --repo "$SOURCE_REPO" >/dev/null 2>&1; then
        printf '  [%s✓%s] %s Provenance verified (API lookup against %s)\n' "$GREEN" "$RESET" "$(fmt_step 4)" "$SOURCE_REPO"
    else
        printf '  [%s-%s] %s Provenance check skipped (no bundle on release; source repo unauthed or not readable)\n' "$DIM" "$RESET" "$(fmt_step 4)"
    fi
else
    printf '  [%s-%s] %s Provenance check skipped (gh unavailable and bootstrap failed)\n' "$DIM" "$RESET" "$(fmt_step 4)"
fi

chmod +x "$TMPBIN"

install_to_dir() {
    mkdir -p "$INSTALL_DIR"
    install -m 0755 "$TMPBIN" "${INSTALL_DIR}/${PACKAGE}"
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
