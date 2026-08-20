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
#   sm_palette, sm_banner,   The shared output format — palette, banner,
#   sm_phase, sm_ok/warn/    phase rule, numbered step lines, continuation
#   fail/act, sm_working,    notes, ~ abbreviation. See the block above
#   sm_note, sm_tilde        confirm_section for the contract; the Rust
#                            side mirrors it in src/sm_prompt.rs.
#   confirm_section          Phase header (via sm_phase); proceeds automatically.
#                            SM_WELCOME_CONFIRM=1 restores the Y/n gate
#                            (SM_WELCOME_ASSUME_YES=1 overrides it back off).
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

# ── One output format for the whole toolchain ─────────────────────────
# A single install is drawn by three programs — sm-welcome.sh, sm-install.sh
# and the sm-welcome binary — and each used to carry its own palette, gutter
# and rule width. Same run, three looks, handing off mid-transcript.
#
# This block is the contract. The Rust side mirrors it in src/sm_prompt.rs
# (markers, counter, gutter) and src/steps/mod.rs (phase rule):
#
#   sm_banner   cleared screen, blank line, bold title, ═ rule sized to
#               the title, dim provenance subtitle lines
#   sm_phase    "\n  ── Title ─────" padded to SM_RULE_W columns total
#   sm_ok/…     "  [G] [NN/TT] message" on an SM_GUTTER-column gutter
#   sm_note     continuation at sm_gutter, dim, no marker — detail about
#               the line above, never a step of its own
#
# The marker set is closed: ✓ green (done), * cyan (in progress), ! yellow
# (warning), ✗ red (failed), > cyan (your turn), - dim (deliberately
# skipped). Anything needing a seventh needs a conversation, not a new
# escape code. `-` earns its place because a skipped provenance check is
# genuinely neither a success nor a warning, and flattening it into either
# is how a run stops saying what it actually did.

SM_RULE_W=36        # total columns of a phase rule, title included
SM_GUTTER_BASE=6    # columns of "  [✓] " — the gutter with no counter

sm_rule() {
    local glyph="$1" n="$2" out='' i=0
    while (( i < n )); do out="${out}${glyph}"; i=$(( i + 1 )); done
    printf '%s' "$out"
}

# Two separate questions, previously answered by one `[[ -t 1 ]]`:
#
#   sm_use_color    may we emit SGR escapes?
#   sm_interactive  may we rewrite a line we already printed?
#
# They are not the same question. A log viewer that renders colour still
# must not receive carriage returns, and NO_COLOR must strip colour without
# turning one progress line into two. Keeping them apart is also what lets
# tests/render-test.sh exercise both paths without allocating a pty.
#
# NO_COLOR is honoured per the no-color.org convention (set, any value).
# SM_FORCE_COLOR / SM_FORCE_TTY override detection the other way, for
# pagers that do render escapes, and for the tests.
sm_use_color() {
    [[ -n "${NO_COLOR:-}" ]] && return 1
    [[ -n "${SM_FORCE_COLOR:-}" ]] && return 0
    [[ -t 1 ]]
}
sm_interactive() {
    [[ -n "${SM_FORCE_TTY:-}" ]] && return 0
    [[ -t 1 ]]
}

# Bright green/red (92/91), plain yellow/cyan (33/96). sm-welcome.sh used
# to set plain green 32 under a comment claiming it matched sm-install.sh's
# 92, so the two halves of one bootstrap ticked in two different greens.
sm_palette() {
    if sm_use_color; then
        C_GREEN=$'\033[92m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[91m'
        C_CYAN=$'\033[96m';  C_DIM=$'\033[2m';     C_BOLD=$'\033[1m'
        C_OFF=$'\033[0m'
    else
        C_GREEN=''; C_YELLOW=''; C_RED=''; C_CYAN=''
        C_DIM='';   C_BOLD='';   C_OFF=''
    fi
    if sm_interactive; then C_ERASE=$'\r\033[K'; else C_ERASE=''; fi
}
sm_palette

# Open the transcript. $1 = mode word ("Install" / "Update"), $2.. = dim
# subtitle lines.
#
# The screen is cleared, the scrollback is NOT. `2J` + `H` blanks the
# viewport and homes the cursor, leaving the buffer intact so whatever the
# user was doing before this ran is still one scroll away. `clear(1)` would
# have sent E3 as well and taken the buffer with it — a fresh view is worth
# a clear, someone's session history is not.
sm_banner() {
    local mode="$1"; shift
    local title="SimpleMotion — Development Environment ${mode}"
    # Width is computed, not measured: ${#title} counts BYTES under LANG=C
    # and would run the rule three columns long on the em dash. The fixed
    # part is 39 columns ("SimpleMotion — Development Environment "), and
    # the mode word is ASCII.
    local width=$(( 39 + ${#mode} ))
    if sm_interactive; then printf '\033[2J\033[H'; fi
    printf '\n  %s%s%s\n  %s%s%s\n' \
        "$C_BOLD" "$title" "$C_OFF" "$C_DIM" "$(sm_rule '═' "$width")" "$C_OFF"
    local line
    for line in "$@"; do
        printf '  %s%s%s\n' "$C_DIM" "$line" "$C_OFF"
    done
}

# A phase rule. Fixed total width, so consecutive phases line up their
# right edges regardless of title length.
sm_phase() {
    local title="$1" pad rule=''
    pad=$(( SM_RULE_W - ${#title} ))
    # A title wider than the rule gets no rule and no separating space —
    # otherwise the line ends in trailing whitespace that only shows up
    # when someone diffs a captured transcript.
    if (( pad > 0 )); then
        rule=" ${C_DIM}$(sm_rule '─' "$pad")${C_OFF}"
    fi
    printf '\n  %s──%s %s%s%s%s\n' \
        "$C_DIM" "$C_OFF" "$C_BOLD" "$title" "$C_OFF" "$rule"
}

# The step cursor. Seeded from the environment so sm-install.sh — which
# runs as its own process, one per package — continues the bootstrap's
# count instead of restarting at 1.
STEP_N="${SM_WELCOME_STEPS_OFFSET:-0}"
STEP_TOTAL="${SM_WELCOME_STEPS_TOTAL:-0}"

# "[NN/TT] ", or nothing at all when no budget has been set. Matches the
# Rust counter(): an unset total prints empty rather than "[03/00]", so a
# line emitted outside any step is simply unnumbered.
sm_counter() {
    (( STEP_TOTAL == 0 )) && return 0
    sm_counter_of "$STEP_N" "$STEP_TOTAL"
}

# The same bracket for a position given explicitly. The binary's step
# listing shows one without having a run position, and renders it from the
# equivalent helper in src/sm_prompt.rs — one spelling of the format on
# each side rather than two per side.
sm_counter_of() {
    printf '%s[%02d/%02d]%s ' "$C_DIM" "$1" "$2" "$C_OFF"
}

# One numbered outcome line. Leads with ERASE so that if an sm_working
# line is sitting unterminated on this row, this line replaces it rather
# than stacking under it.
sm_step() {
    local glyph="$1" colour="$2"; shift 2
    STEP_N=$(( STEP_N + 1 ))
    printf '%s  [%s%s%s] %s%s\n' \
        "$C_ERASE" "$colour" "$glyph" "$C_OFF" "$(sm_counter)" "$*"
}
sm_ok()   { sm_step '✓' "$C_GREEN"  "$@"; }
sm_warn() { sm_step '!' "$C_YELLOW" "$@"; }
sm_fail() { sm_step '✗' "$C_RED"    "$@"; }
sm_act()  { sm_step '>' "$C_CYAN"   "$@"; }
sm_skip() { sm_step '-' "$C_DIM"    "$@"; }

# An in-progress line, carrying the number it is ABOUT to take. Does not
# advance the cursor — the outcome line that replaces it does that, so a
# slow step is one line in the transcript whichever way it ends.
#
# On a TTY it is left unterminated for sm_step's ERASE to overwrite. With
# no TTY there is nothing to overwrite, so it terminates and stands as its
# own record — a piped log keeps the evidence that the step was entered.
sm_working() {
    local nl='\n' c
    if sm_interactive; then nl=''; fi
    STEP_N=$(( STEP_N + 1 )); c="$(sm_counter)"; STEP_N=$(( STEP_N - 1 ))
    printf "  [%s*%s] %s%s${nl}" "$C_CYAN" "$C_OFF" "$c" "$*"
}

# How far in the message text starts on the line above. Not a constant:
# a line printed inside a step carries "[NN/TT] " and one printed outside a
# step does not, so a fixed indent hangs the continuation eight columns off
# the message it belongs to in whichever case it was not tuned for. The
# counter's own width is derived rather than assumed, so a three-digit
# total does not silently break the alignment.
sm_gutter() {
    # Measured off sm_counter's own output rather than re-derived from its
    # format string: a hand-rolled "1 + 2 + 1 + 2 + 2" is a second copy of
    # the format that goes stale the moment the counter changes, and it
    # gets the mixed-width case wrong (STEP_N renders "05" while a total of
    # 120 renders three digits). The only non-printing content is the dim
    # pair, so subtracting it gives the true column count.
    local c w="$SM_GUTTER_BASE"
    c="$(sm_counter)"
    if [[ -n "$c" ]]; then
        w=$(( SM_GUTTER_BASE + ${#c} - ${#C_DIM} - ${#C_OFF} ))
    fi
    printf '%s' "$w"
}

# Continuation under the line above: dim, marker-less, indented to the
# gutter so it sits under the MESSAGE rather than under the counter.
sm_note() { printf '%*s%s%s%s\n' "$(sm_gutter)" '' "$C_DIM" "$*" "$C_OFF"; }

# Abbreviate $HOME to ~ so a path fits the line instead of wrapping to
# column 0 and breaking the gutter for every line after it.
sm_tilde() {
    # The replacement is a variable, not `\~`: a backslash-escaped tilde
    # survives literally in bash 3.2 (macOS' /bin/bash), printing `\~/...`.
    local t='~'
    printf '%s' "${1/#$HOME/$t}"
}

confirm_section() {
    # The rule itself is sm_phase's, so a phase opened by the shell and one
    # opened by the binary are the same object drawn by one formula rather
    # than two copies of it that drifted apart.
    sm_phase "$1"
    # Auto-proceed by default — the section gates made a fresh onboarding
    # three extra Enter presses for no decision the user could make
    # (matches sm-welcome v0.1.10 dropping its per-step Proceed gate).
    # SM_WELCOME_CONFIRM=1 restores the prompt; SM_WELCOME_ASSUME_YES=1
    # (the old non-interactive override) still wins over it for existing
    # CI/scripted callers.
    if [[ -n "${SM_WELCOME_ASSUME_YES:-}" || -z "${SM_WELCOME_CONFIRM:-}" ]]; then
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
        *) sm_warn 'Aborted by user.' >&2; exit 1 ;;
    esac
}

# shellcheck disable=SC2034  # COSIGN_BIN is this function's OUTPUT, read by callers
find_cosign() {
    COSIGN_BIN=""
    if [[ -x "$HOME/.local/bin/cosign" ]]; then
        COSIGN_BIN="$HOME/.local/bin/cosign"; return 0
    fi
    return 1
}

# shellcheck disable=SC2034  # COSIGN_BIN is this function's OUTPUT, read by callers
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

# shellcheck disable=SC2034  # PWSH_BIN is this function's OUTPUT, read by callers
find_pwsh() {
    PWSH_BIN=""
    if [[ -x "$HOME/.local/bin/pwsh-7/pwsh" ]]; then
        PWSH_BIN="$HOME/.local/bin/pwsh-7/pwsh"; return 0
    fi
    return 1
}

# Install PowerShell 7 (portable) into ~/.local/bin/pwsh-7 from the official
# PowerShell/PowerShell GitHub release tarball, SHA256-verified against the
# API's per-asset digest, and symlink ~/.local/bin/pwsh at it. The Unix
# parallel to sm-welcome.ps1's Install-PwshPortable. Self-contained, per-user,
# no Homebrew/apt/sudo. pwsh is the shell the M365 / Exchange Online admin
# scripts (sm-set-*.ps1) target; the SimpleMotion toolchain prefers pwsh 7
# over the in-box shells. Best-effort: degrades to a notice on any failure.
# shellcheck disable=SC2034  # PWSH_BIN is this function's OUTPUT, read by callers
ensure_pwsh() {
    PWSH_BIN=""
    local pwsh_dir="$HOME/.local/bin/pwsh-7"
    local pwsh_exe="${pwsh_dir}/pwsh"
    if [[ -x "$pwsh_exe" ]]; then
        PWSH_BIN="$pwsh_exe"; return 0
    fi

    local ps_os ps_arch
    case "$(uname -s)" in
        Darwin) ps_os=osx ;;
        Linux)  ps_os=linux ;;
        *) printf '      [-] PowerShell bootstrap skipped (unsupported OS)\n'; return 1 ;;
    esac
    case "$(uname -m)" in
        x86_64|amd64)  ps_arch=x64 ;;
        arm64|aarch64) ps_arch=arm64 ;;
        *) printf '      [-] PowerShell bootstrap skipped (unsupported arch)\n'; return 1 ;;
    esac

    # Resolve the latest non-prerelease release metadata once: the tag (→
    # version → deterministic asset name) and the asset's SHA256, taken from
    # the GitHub API's per-asset `digest` field (plain UTF-8 JSON). We
    # deliberately avoid the release's hashes.sha256 file — it ships as
    # UTF-16 + CRLF, which POSIX awk/sha256sum can't parse portably. This is
    # the same digest the Windows installer verifies via Confirm-AssetDigest.
    local rel_json tag version asset
    rel_json=$(sm_mktemp)
    if ! curl -fsSL "https://api.github.com/repos/PowerShell/PowerShell/releases/latest" -o "$rel_json" 2>/dev/null; then
        rm -f "$rel_json"
        printf '      [-] PowerShell bootstrap skipped (release metadata fetch failed)\n'
        return 1
    fi
    tag=$(awk -F'"' '/"tag_name":/ {print $4; exit}' "$rel_json")
    if [[ -z "$tag" ]]; then
        rm -f "$rel_json"
        printf '      [-] PowerShell bootstrap skipped (no tag in release metadata)\n'
        return 1
    fi
    version="${tag#v}"
    asset="powershell-${version}-${ps_os}-${ps_arch}.tar.gz"

    # Each asset object lists "name" before "digest" — capture the digest
    # that follows our asset's name line, then drop the "sha256:" prefix.
    local expected
    expected=$(awk -F'"' -v a="$asset" '$2=="name" && $4==a {f=1} f && $2=="digest" {print $4; exit}' "$rel_json")
    expected="${expected#sha256:}"
    rm -f "$rel_json"
    if [[ -z "$expected" ]]; then
        printf '      [-] PowerShell bootstrap skipped (no SHA256 digest for %s)\n' "$asset"
        return 1
    fi

    local url="https://github.com/PowerShell/PowerShell/releases/download/${tag}/${asset}"
    local tmp_tgz
    tmp_tgz=$(sm_mktemp)
    if ! curl -fsSL "$url" -o "$tmp_tgz" 2>/dev/null; then
        rm -f "$tmp_tgz"
        printf '      [-] PowerShell bootstrap skipped (download failed)\n'
        return 1
    fi

    local actual
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$tmp_tgz" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "$tmp_tgz" | awk '{print $1}')
    else
        rm -f "$tmp_tgz"
        printf '      [-] PowerShell bootstrap skipped (no sha256 tool)\n'
        return 1
    fi
    if [[ "$expected" != "$actual" ]]; then
        rm -f "$tmp_tgz"
        printf '      [-] PowerShell bootstrap skipped (SHA256 mismatch on PowerShell asset)\n'
        return 1
    fi

    # The tarball is flat — pwsh plus its bundled .NET assemblies extract
    # straight into the destination. Wipe-and-extract so re-runs land clean.
    rm -rf "$pwsh_dir"
    mkdir -p "$pwsh_dir"
    if ! tar -xzf "$tmp_tgz" -C "$pwsh_dir" 2>/dev/null; then
        rm -f "$tmp_tgz"
        printf '      [-] PowerShell bootstrap skipped (tar extract failed)\n'
        return 1
    fi
    chmod 0755 "$pwsh_exe" 2>/dev/null || true
    rm -f "$tmp_tgz"

    if [[ ! -x "$pwsh_exe" ]]; then
        printf '      [-] PowerShell bootstrap skipped (pwsh missing after extract)\n'
        return 1
    fi

    # Expose `pwsh` on PATH: ~/.local/bin is already on the user's PATH
    # (.zprofile / .zshenv), so symlink the real binary there. pwsh follows
    # the symlink to resolve its bundled assemblies, so no copy is needed.
    ln -sfn "$pwsh_exe" "$HOME/.local/bin/pwsh"
    PWSH_BIN="$pwsh_exe"
    return 0
}
