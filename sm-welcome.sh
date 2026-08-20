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
#                      PowerShell 7 (portable, SHA256-verified) into
#                      ~/.local/bin/pwsh-7 for the M365/Exchange admin
#                      scripts; auto-install cosign via direct
#                      sigstore/cosign release download + SHA256-verify into
#                      ~/.local/bin/cosign (no sudo, no Homebrew); then run
#                      `cosign initialize` against GitHub's Sigstore TUF so
#                      cosign can verify GitHub-issued attestations natively.
#                      Missing git/curl are flagged but not auto-installed
#                      (sudo / Xcode).
#   2. sm-welcome    — download sm-welcome from the selected channel,
#                      verify SHA256 + sigstore build-provenance (cosign,
#                      installed in Section 1). Fast-paths if the local
#                      copy is already at the latest tag.
#   3. Launch        — exec sm-welcome in the current shell.
#
# Section prompts auto-accept by default. Set SM_WELCOME_CONFIRM=1 to gate
# each section behind Proceed? [Y/n]; SM_WELCOME_ASSUME_YES=1 (the old
# non-interactive override) still forces auto-accept over it.

set -euo pipefail

# Match the Windows TLS pin (sm-*.ps1's SecurityProtocol): force a TLS 1.2
# floor on every curl in this process — including the lib sourced below.
# curl on macOS/Linux already negotiates 1.2/1.3, so this is defensive
# (rejects ancient TLS / downgrade). `command` avoids recursing into itself.
curl() { command curl --tlsv1.2 "$@"; }

# Authenticate api.github.com requests when a token is present (GH_TOKEN or
# GITHUB_TOKEN). Lifts the 60/hr unauthenticated rate limit on shared CI /
# corporate-NAT IPs. curl strips the Authorization header on a cross-host
# redirect, so it's safe. Use ONLY for api.github.com calls.
SM_GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
gh_api() {
    # --retry rides out transient api.github.com failures (5xx/429/connection
    # resets) so a momentary blip isn't misread as "no release published yet".
    if [ -n "$SM_GH_TOKEN" ]; then
        curl -fsSL --retry 3 --retry-delay 2 -H "Authorization: Bearer $SM_GH_TOKEN" -H "X-GitHub-Api-Version: 2022-11-28" "$@"
    else
        curl -fsSL --retry 3 --retry-delay 2 "$@"
    fi
}

# Per-SimpleMotion TUF cache so we don't clobber any existing public-good
# Sigstore trust under ~/.sigstore. Exported so sm-install.sh picks it up.
export TUF_ROOT="${TUF_ROOT:-$HOME/.simplemotion/sigstore}"

# Where the bootstrap fetches its siblings from. Overridable so a branch can
# be exercised end-to-end before it is deployed — `SM_INSTALL_BASE=file://$PWD`
# runs the working tree, which is what tests/render-test.sh does. Defaults to
# production, so every documented one-liner is unaffected.
SM_INSTALL_BASE="${SM_INSTALL_BASE:-https://install.simplemotion.com}"

# Source the shared install-toolchain library. Brings in confirm_section,
# find_cosign, ensure_cosign, initialize_cosign_tuf. sm-install.sh loads
# the same lib when it runs in Section 2.
eval "$(curl -fsSL "${SM_INSTALL_BASE}/sm-install-lib.sh")"

# Route tempfiles under ~/SimpleMotion/.tmpdir so curl-to-mktemp writes
# don't hit the macOS /var/folders/.../T/ failure modes (EDR scans,
# sandbox boundaries, periodic cleanup). See sm-install-lib.sh for the
# function body + rationale.
sm_route_tmpdir

# sm-welcome's step-counter UI accounts for the bootstrap's pre-binary
# steps via env vars the binary reads (banner suppression + offset).
export SM_WELCOME_NO_BANNER=1

# ── Step budget ───────────────────────────────────────────────────────
# One counter runs from the first prerequisite to the last binary step, so
# every phase needs to agree on the total BEFORE the first line is printed.
#
# This used to be two hardcoded numbers (OFFSET=5, TOTAL=23) resting on the
# claim that the binary had 18 steps. It has 19. The last step therefore
# rendered `[24/23]` — a counter past its own total — and the comment
# describing it as "one short" documented a state that had stopped being
# true. Hardcoding a number that lives in another repo is what failed, so
# the constants are at least named and checkable now:
#
#   sm-welcome --list | grep -c '^ '     # the binary's own step count
#
# PREREQ is this script's Prerequisites phase; DL is one sm-install.sh
# invocation, which always prints five numbered steps.
PREREQ_STEPS=3
DL_STEPS=5
# CROSS-REPO CONSTANT. The truth lives in 3400-0009-SM-Welcome's step
# registry, and test_workflow_manifest_parses there pins it and names this
# line when it changes. If you are here because that test failed, this is
# the number it wants.
case "$(uname -s)" in
    Darwin) BIN_STEPS=19 ;;   # includes the macOS-only touchid step
    *)      BIN_STEPS=18 ;;   # Linux omits it
esac

# The palette, banner, phase rule and step renderer all come from
# sm-install-lib.sh, sourced above and by sm-install.sh in its own process.
# They used to be defined here as well, in a second copy that had already
# drifted — a different green, and a continuation indent five columns
# short of the gutter it claimed to match.

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
                echo "sm-welcome.sh: --channel requires a value (release|preview|develop|testing)" >&2
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

# The binary only spends steps when it is going to RUN them. `update`
# reaches us as `bash -s -- list`, which prints the step table and exits —
# so budgeting for 19 unrun steps left the counter stopping dead at 13/32
# and the transcript looking truncated. Any verb that does not run the
# workflow contributes zero.
case "${BIN_ARGS[0]:-run}" in
    list|status|steps|--version|-V|--help|-h) BIN_STEPS=0 ;;
esac

INSTALL_DIR="${SM_INSTALL_DIR:-$HOME/.simplemotion/bin}"
LOCAL_BIN="${INSTALL_DIR}/sm-welcome"

# ── Open the transcript ───────────────────────────────────────────────
# Mode word and channel provenance come from `sm-welcome update` when it
# spawned us (it knows which install receipt it read); a bare curl|bash has
# neither, and says so.
SM_MODE="${SM_WELCOME_MODE:-Install}"
if [[ -n "${SM_WELCOME_CHANNEL_SOURCE:-}" ]]; then
    SM_CHANNEL_SOURCE="$SM_WELCOME_CHANNEL_SOURCE"
elif [[ ${#CHANNEL_ARG[@]} -gt 0 ]]; then
    SM_CHANNEL_SOURCE="--channel override"
elif [[ -n "${SM_CHANNEL:-}" ]]; then
    SM_CHANNEL_SOURCE="SM_CHANNEL environment"
else
    SM_CHANNEL_SOURCE="default"
fi
sm_banner "$SM_MODE" "channel=${CHANNEL_VAL} · ${SM_CHANNEL_SOURCE}"

# Optional clean wipe. --clean (or SM_WELCOME_CLEAN=1) deletes the
# SimpleMotion-owned bootstrap locations on disk so Section 1 rebuilds
# from scratch. We scope to specific paths under ~/.local (rather than
# ~/.local wholesale) because that dir is the XDG user-install root on
# Unix and likely contains unrelated packages (pip --user, cargo, etc.).
if [[ $CLEAN -eq 1 ]]; then
    sm_warn '--clean set — wiping prior bootstrap state'
    for p in \
        "$HOME/.local/bin/cosign" \
        "$HOME/.local/bin/pwsh-7" \
        "$HOME/.local/bin/pwsh" \
        "$HOME/.local/bin/git" \
        "$HOME/.simplemotion" \
        "$HOME/.sm-welcome.toml"; do
        if [[ -e "$p" ]]; then
            rm -rf "$p"
            sm_note "removed $(sm_tilde "$p")"
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
# cosign is a SimpleMotion-managed tool — we deliberately ignore any
# system-wide cosign (Homebrew / apt / dnf) and use only the one we
# install ourselves at ~/.local/bin/cosign.
if [[ -x "$HOME/.local/bin/cosign" ]]; then
    COSIGN_STATE="present ($HOME/.local/bin/cosign)"
else
    COSIGN_STATE="missing"
fi
# pwsh 7 is a SimpleMotion-managed tool too — like cosign, we ignore any
# system-wide PowerShell and use only the portable copy at
# ~/.local/bin/pwsh-7 (symlinked as ~/.local/bin/pwsh).
if [[ -x "$HOME/.local/bin/pwsh-7/pwsh" ]]; then
    PWSH_STATE="present ($HOME/.local/bin/pwsh-7/pwsh)"
else
    PWSH_STATE="missing"
fi

# Hard-stop only if curl is missing — without it we can't fetch anything,
# including the version probe immediately below.
if [[ "$CURL_STATE" == "missing" ]]; then
    sm_fail 'curl is required to continue. Install it via your package manager.' >&2
    exit 1
fi

SKIP_DOWNLOAD=0
LOCAL_VER=""
case "$CHANNEL_VAL" in
    release|preview|develop|testing) CHANNEL_REPO="simplemotion/sm-${CHANNEL_VAL}"; STORE_CHANNEL="$CHANNEL_VAL" ;;
    # 'private' is deliberately absent. It was a legacy alias for develop until
    # 2026-08-19 and is now the GA terminal for products that never leave
    # SimpleMotion — which sm-welcome, being public-eligible, can never be on.
    # Leaving the old alias would have sent --channel private to develop and
    # silently installed a different build than the one named. Falling through
    # to the no-fast-path branch lets sm-install.sh report it accurately.
    *) CHANNEL_REPO=""; STORE_CHANNEL="" ;;
esac
# Ask the store whether it already holds the channel's latest TAG, rather
# than asking the binary what version it thinks it is.
#
# The old check compared `sm-welcome -V` against the channel's tag, and on
# the release channel those can never be equal: the binary stamps itself
# from the develop tag it was built at (0.1.0-develop-229) while the release
# channel's tag is the bare GA (0.1.0). So the fast path never once fired on
# release — every run re-downloaded a binary it already had. Now that the
# store is keyed BY tag, the question is just "is that file there?", which
# cannot drift from what the binary reports because it no longer asks.
STORE_DIR="$HOME/.simplemotion/share/${STORE_CHANNEL}/sm-welcome"
if [[ -z "${SM_WELCOME_SKIP_FAST_PATH:-}" && -n "$STORE_CHANNEL" && -d "$STORE_DIR" ]]; then
    LATEST_TAG=$(gh_api "https://api.github.com/repos/${CHANNEL_REPO}/releases/latest" 2>/dev/null \
        | awk -F'"' '/"tag_name":/ {print $4; exit}' || true)
    if [[ -n "$LATEST_TAG" && -x "${STORE_DIR}/${LATEST_TAG}" ]]; then
        # Already have this channel's latest — re-point the active symlink
        # (cheap) so switching channel or version takes effect without a
        # download.
        mkdir -p "$INSTALL_DIR"
        ln -sfn "${STORE_DIR}/${LATEST_TAG}" "$LOCAL_BIN"
        LOCAL_VER="$LATEST_TAG"
        SKIP_DOWNLOAD=1
    fi
fi


# Whether sm-onboard needs fetching, decided on the same terms Section 2
# uses further down. Resolved HERE, before anything prints, because the
# step total has to include it: a counter that cannot say how many steps
# there are until halfway through is not a counter.
NEED_ONBOARD=0
if [[ $SKIP_DOWNLOAD -eq 0 || ! -x "${INSTALL_DIR}/sm-onboard" ]]; then
    NEED_ONBOARD=1
fi

# Each package costs DL_STEPS if it is fetched and one line if it is not —
# "already at the latest" is still something the run DID, and reporting it
# as a numbered skip keeps the phase from rendering as a header with a
# dangling note under it.
welcome_cost=$(( SKIP_DOWNLOAD == 0 ? DL_STEPS : 1 ))
onboard_cost=$(( NEED_ONBOARD == 1 ? DL_STEPS : 1 ))
STEP_TOTAL=$(( PREREQ_STEPS + welcome_cost + onboard_cost + BIN_STEPS ))

confirm_section "Prerequisites"
# git is not installed here — the binary's preflight reports it — so this is
# a continuation line, not a step. Only things this phase actually DOES get
# a number, otherwise the count would drift with the weather.
if [[ "$GIT_STATE" == "missing" ]]; then
    sm_note "git not found — sm-welcome will report this in its preflight."
fi

# Each of the three below prints exactly ONE numbered line whichever way it
# goes: installed, already present, or failed. That is what keeps the
# counter contiguous — a phase whose step count depends on the outcome
# cannot be numbered against a total computed up front.
if [[ "$PWSH_STATE" == "missing" ]]; then
    sm_working 'Installing PowerShell 7 (PowerShell/PowerShell latest, SHA256-verified)...'
    if ensure_pwsh; then
        sm_ok "PowerShell 7 installed: $(sm_tilde "$PWSH_BIN")"
    else
        sm_warn "PowerShell 7 install failed"
        sm_note "The M365/Exchange admin scripts (sm-set-*.ps1) will need pwsh installed manually."
    fi
else
    sm_ok "PowerShell 7 present: $(sm_tilde "$HOME/.local/bin/pwsh-7/pwsh")"
fi

if [[ "$COSIGN_STATE" == "missing" ]]; then
    sm_working 'Installing cosign (sigstore/cosign latest, SHA256-verified)...'
    if ensure_cosign; then
        sm_ok "cosign installed: $(sm_tilde "$COSIGN_BIN")"
    else
        sm_warn "cosign install failed"
        sm_note "Attestation verification will be skipped; SHA256 still anchors integrity."
    fi
else
    COSIGN_BIN="$HOME/.local/bin/cosign"
    sm_ok "cosign present: $(sm_tilde "$COSIGN_BIN")"
fi

if [[ -n "${COSIGN_BIN:-}" ]]; then
    sm_working 'Initializing cosign TUF trust (tuf-repo.github.com)...'
    if initialize_cosign_tuf "$COSIGN_BIN"; then
        sm_ok "cosign TUF initialized in $(sm_tilde "$TUF_ROOT")"
    else
        sm_warn "cosign TUF init failed"
        sm_note "Attestation verification will be skipped; SHA256 still anchors integrity."
    fi
else
    # cosign never arrived, so there is no trust store to initialise. The
    # step is still numbered and still reported: a silently absent step is
    # how a counter starts lying about what ran.
    sm_warn "cosign TUF trust skipped — cosign unavailable"
fi

# ── Section 2: sm-welcome ─────────────────────────────────────────────
# Fast-path resolution — channel-aware. The per-channel store
# (~/.simplemotion/share/<channel>/sm-welcome) holds the binary
# we last installed for THIS channel. If its version already matches the
# channel's latest release, skip the download — and re-point the
# ~/.simplemotion/bin symlink at it, so a channel *switch* still takes effect
# without a download. We check the channel's own stored binary (not the
# bin/ symlink, which may currently point at a different channel).
export SM_WELCOME_STEPS_TOTAL="$STEP_TOTAL"

confirm_section "Download"

if [[ $SKIP_DOWNLOAD -eq 0 ]]; then
    # Each sm-install.sh pass numbers its five steps from 1; the offset is
    # what makes them continue this script's count instead of restarting.
    # Without it both passes printed [01..05] and the binary then resumed
    # from a number neither of them had reached.
    export SM_WELCOME_STEPS_OFFSET="$STEP_N"
    INSTALL_SH=$(curl -fsSL "${SM_INSTALL_BASE}/sm-install.sh")
    if ! bash -c "$INSTALL_SH" sm-install \
        --package sm-welcome \
        --asset-suffix short \
        --source-repo 3400-0000-SM-Software/3400-0009-SM-Welcome \
        --mode install \
        ${CHANNEL_ARG[@]+"${CHANNEL_ARG[@]}"}; then
        sm_fail "sm-welcome could not be installed from the ${CHANNEL_VAL} channel (see above)." >&2
        exit 1
    fi
    STEP_N=$(( STEP_N + DL_STEPS ))
else
    sm_skip "sm-welcome already at $LOCAL_VER on this channel — download skipped"
fi

# ── sm-onboard ────────────────────────────────────────────────────────
# Ships from the same workspace and the same release, and lands beside
# sm-welcome in ~/.simplemotion/bin. It is the admin-run onboarding CLI:
# sm-welcome's own home-repo step failure tells the operator to run
# `sm-onboard <cohort> adduser ...`, which until now nothing ever installed —
# it just assumed the binary was on PATH.
#
# Runs when we already downloaded sm-welcome, OR when sm-onboard is simply
# absent. That second case is what reaches existing installs: the fast path
# above skips the download entirely when sm-welcome is already this channel's
# latest, so gating solely on it would never deliver sm-onboard to anyone
# already up to date. Version comparison is not an option here — sm-onboard
# reports its own crate version (0.1.0), not the workspace release tag.
#
# NON-FATAL by design. Releases cut before simplemotion/sm-ci#28 carry no
# sm-onboard asset at all (the build never passed --workspace, so the binary was
# enumerated, not found, and dropped). Making this fatal would break every
# install from an existing release, on every channel, until each is re-cut.
# A workstation without sm-onboard is fully functional — only admins invoke it.
if [[ $NEED_ONBOARD -eq 1 ]]; then
    export SM_WELCOME_STEPS_OFFSET="$STEP_N"
    : "${INSTALL_SH:=$(curl -fsSL "${SM_INSTALL_BASE}/sm-install.sh")}"
    if ! bash -c "$INSTALL_SH" sm-install \
        --package sm-onboard \
        --asset-suffix short \
        --source-repo 3400-0000-SM-Software/3400-0009-SM-Welcome \
        --mode install \
        ${CHANNEL_ARG[@]+"${CHANNEL_ARG[@]}"}; then
        sm_warn "sm-onboard was not installed from the ${CHANNEL_VAL} channel — continuing." >&2
        sm_note 'Expected if this release predates simplemotion/sm-ci#28, which is what' >&2
        sm_note 'first built workspace members. Admins can re-run this installer after' >&2
        sm_note 'the next release on that channel; everyone else does not need it.' >&2
    fi
    STEP_N=$(( STEP_N + DL_STEPS ))
else
    # Budgeted at one line, and here it is. A phase that decided to do
    # nothing should say so on the record rather than leave a gap the
    # reader has to interpret.
    sm_skip 'sm-onboard already present — download skipped'
fi

# ── Section 3: Launch ─────────────────────────────────────────────────
# The binary picks the count up from here and runs it out to STEP_TOTAL.
export SM_WELCOME_STEPS_OFFSET="$STEP_N"

# No phase header here. There used to be one titled "Setup", and it was
# empty on every run: the next thing to touch the terminal is the binary,
# which opens its own phase before its first step. A rule with nothing
# under it is not a section, it is a gap with a title.

exec_local() {
    if (: </dev/tty) 2>/dev/null; then
        exec "$LOCAL_BIN" ${BIN_ARGS[@]+"${BIN_ARGS[@]}"} </dev/tty
    else
        exec "$LOCAL_BIN" ${BIN_ARGS[@]+"${BIN_ARGS[@]}"}
    fi
}
exec_local
