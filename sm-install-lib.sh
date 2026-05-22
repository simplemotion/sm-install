#!/usr/bin/env bash
# SimpleMotion install-toolchain library (macOS + Linux).
#
# Pure function definitions, no top-level code. Sourced by:
#   - sm-install.sh   (the generic SimpleMotion binary installer)
#   - sm-welcome.sh   (the onboarding bootstrap)
#
# Usage (from a `bash -c` curl|bash entrypoint where the lib needs to be
# eval'd into the current shell so the functions are available):
#   eval "$(curl -fsSL https://install.simplemotion.com/sm-install-lib.sh)"
#
# Functions:
#   confirm_section          Section-gated Y/n prompt with framed header.
#                            SM_WELCOME_ASSUME_YES=1 bypasses the prompt.
#   find_cosign              Probe ~/.local/bin/cosign and nothing else
#                            (100%-local toolchain rule — system-wide
#                            cosigns from Homebrew / apt / dnf are
#                            deliberately ignored). Sets COSIGN_BIN.
#   ensure_cosign            Download cosign-{darwin,linux}-{amd64,arm64}
#                            from sigstore/cosign /releases/latest/,
#                            SHA256-verify against cosign_checksums.txt,
#                            install to ~/.local/bin/cosign. Sets COSIGN_BIN.
#   initialize_cosign_tuf    `cosign initialize` against tuf-repo.github.com
#                            so cosign can verify GitHub-issued attestations
#                            natively. Cache lands in $TUF_ROOT
#                            (~/.simplemotion/sigstore by default).
#   sm_route_tmpdir          Route TMPDIR to ~/SimpleMotion/.tmpdir so
#                            mktemp + curl-to-tempfile writes land on
#                            a SimpleMotion-controlled path, not the
#                            macOS /var/folders/.../T/ default. Each
#                            entrypoint that sources this lib should
#                            call it before the first sm_mktemp.
#   sm_mktemp                Portable wrapper for `mktemp -p "$TMPDIR"`.
#                            Required because macOS BSD mktemp (no args)
#                            ignores TMPDIR and goes to
#                            /var/folders/.../T/ via the confstr libc
#                            call. All bootstrap mktemp call sites
#                            should use sm_mktemp.

# Best-effort TMPDIR redirect. macOS' /var/folders/.../T/ occasionally
# hits transient write failures under EDR scanning, sandbox boundaries,
# or periodic cleanup — curl-to-tempfile then bails with `curl: (56)
# Failure writing output to destination, passed N returned 0`. Routing
# under ~/SimpleMotion/.tmpdir puts tempfiles on the same APFS volume
# as the install destination (~/.simplemotion/bin/) and under user-
# controlled state — same surface clean-all wipes.
#
# Falls back silently to system default if HOME isn't usable. Idempotent
# — safe to call multiple times.
sm_route_tmpdir() {
    if [[ -n "${HOME:-}" ]] && mkdir -p "$HOME/SimpleMotion/.tmpdir" 2>/dev/null; then
        export TMPDIR="$HOME/SimpleMotion/.tmpdir"
    fi
}

# macOS BSD mktemp (no args) calls confstr(_CS_DARWIN_USER_TEMP_DIR)
# and goes to /var/folders/.../T/ — IGNORING $TMPDIR. The man page
# claims otherwise but the implementation overrides at the libc level.
# `mktemp -p <dir>` is the portable knob that actually routes both BSD
# and GNU mktemp to the requested directory.
#
# All bootstrap mktemp calls go through this helper. Falls back to bare
# `mktemp` when TMPDIR is unset / unusable so we don't hard-fail if
# sm_route_tmpdir was skipped.
sm_mktemp() {
    if [[ -n "${TMPDIR:-}" && -d "$TMPDIR" ]]; then
        mktemp -p "$TMPDIR"
    else
        mktemp
    fi
}

confirm_section() {
    local title="$1"
    local pad
    pad=$(( 56 - ${#title} ))
    if (( pad < 0 )); then pad=0; fi
    printf '\n  ── %s ' "$title"
    printf -- '─%.0s' $(seq 1 "$pad")
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

find_cosign() {
    COSIGN_BIN=""
    if [[ -x "$HOME/.local/bin/cosign" ]]; then
        COSIGN_BIN="$HOME/.local/bin/cosign"; return 0
    fi
    return 1
}

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
    tmp_bin=$(sm_mktemp); tmp_sums=$(sm_mktemp)
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

initialize_cosign_tuf() {
    local cosign="$1"
    [[ -n "$cosign" ]] || return 1
    : "${TUF_ROOT:=$HOME/.simplemotion/sigstore}"
    export TUF_ROOT
    mkdir -p "$TUF_ROOT"
    local tmp_root
    tmp_root=$(sm_mktemp)
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
