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
# Fast path: if ~/.simplemotion/bin/sm-welcome already exists, the
# script consults the GitHub Releases API for the latest tag on the
# selected channel:
#   - match    → exec the local binary directly (no download)
#   - mismatch → invoke `sm-welcome update`, then exec the refreshed
#                local binary (recursion is broken by
#                SM_WELCOME_SKIP_FAST_PATH=1 set on the update child)
#   - missing  → fall through to the sm-install.sh download flow

set -euo pipefail

printf '\n  SimpleMotion — Development Environment Onboarding\n  ══════════════════════════════════════════════════\n\n'

# sm-welcome's step-counter UI accounts for the bootstrap's pre-binary
# steps via env vars the binary reads (banner suppression + offset).
export SM_WELCOME_NO_BANNER=1
export SM_WELCOME_STEPS_OFFSET=5
# Binary has 15 internal steps (00-preflight through 14-reload-shell);
# bootstrap contributes 5 silent steps. 5 + 15 = 20.
# Update if the binary's step count changes.
export SM_WELCOME_STEPS_TOTAL=20

# Pre-parse our own flags: --channel goes to sm-install.sh; --quiet /
# -q is captured so sm-install.sh can show the quiet-mode notice inside
# its Download-phase output (still forwarded to the binary so it knows
# to suppress its own subprocesses); everything else forwards to the
# binary verbatim. SM_CHANNEL env var also still works (sm-install.sh
# respects it as a default).
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
        -q|--quiet)
            # Signal sm-install.sh; binary still sees the flag (forwarded
            # below) and toggles its own quiet behaviour.
            export SM_WELCOME_QUIET=1
            BIN_ARGS+=("$1"); shift
            ;;
        *)
            BIN_ARGS+=("$1"); shift
            ;;
    esac
done

# Fast path: skip the sm-install.sh download if ~/.simplemotion/bin/sm-welcome
# is already on disk at the latest tag for the selected channel.
INSTALL_DIR="${SM_INSTALL_DIR:-$HOME/.simplemotion/bin}"
LOCAL_BIN="${INSTALL_DIR}/sm-welcome"
exec_local() {
    if (: </dev/tty) 2>/dev/null; then
        exec "$LOCAL_BIN" ${BIN_ARGS[@]+"${BIN_ARGS[@]}"} </dev/tty
    else
        exec "$LOCAL_BIN" ${BIN_ARGS[@]+"${BIN_ARGS[@]}"}
    fi
}
if [[ -z "${SM_WELCOME_SKIP_FAST_PATH:-}" && -x "$LOCAL_BIN" ]]; then
    # `sm-welcome -V` prints "sm-welcome X.Y.Z"; strip the program name
    # and any leading "v".
    LOCAL_VER=$("$LOCAL_BIN" -V 2>/dev/null | awk '{print $2}' | sed 's/^v//')
    # Resolve the latest tag on the selected channel via the channel's
    # GitHub Releases API. Each channel repo has its own releases/latest.
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
    if [[ -n "$LOCAL_VER" && -n "$LATEST_VER" ]]; then
        if [[ "$LOCAL_VER" == "$LATEST_VER" ]]; then
            printf '  [✓] sm-welcome %s already installed (channel=%s) — skipping download\n' "$LOCAL_VER" "$CHANNEL_VAL"
            exec_local
        else
            # Mismatch: fall through to the full install below. The local
            # binary's `sm-welcome update` historically defaulted to the
            # `release` channel regardless of the user's `--channel` ask,
            # so calling it here led to cross-channel downgrades (and a
            # cross-version step-name mismatch on the rebooted binary).
            # The full-install path below is already channel-aware via
            # CHANNEL_ARG, so a plain fall-through is both simpler and
            # correct. Install-receipt-driven channel pinning is the
            # follow-up that lets `sm-welcome update` stand on its own.
            printf '  [↑] sm-welcome %s installed; %s available on channel=%s — re-installing\n' "$LOCAL_VER" "$LATEST_VER" "$CHANNEL_VAL"
        fi
    fi
fi

# Buffer sm-install.sh into a variable (curl finishes BEFORE bash starts),
# then exec bash -c on the captured script. No FIFO, no race with the
# trailing exec inside sm-install.sh — no curl (56) warning.
INSTALL_SH=$(curl -fsSL "https://install.simplemotion.com/sm-install.sh")
exec bash -c "$INSTALL_SH" sm-install \
    --package sm-welcome \
    --source-repo 3400-0000-SM-Software/3400-0009-SM-Welcome \
    --mode install-and-run \
    ${CHANNEL_ARG[@]+"${CHANNEL_ARG[@]}"} \
    -- ${BIN_ARGS[@]+"${BIN_ARGS[@]}"}
