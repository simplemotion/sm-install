#!/usr/bin/env bash
# Renders a full bootstrap transcript without installing anything.
#
# The look of an install used to be reviewable only by running one, which
# meant a design change could not be seen until it had already shipped to
# install.simplemotion.com. This replays the same renderer calls the real
# scripts make, against the same library, so the format can be read, diffed
# and argued about in a pull request.
#
#   bash tests/render-preview.sh update     # what `sm-welcome update` prints
#   bash tests/render-preview.sh install    # a first run on a clean machine
#
# It is a rendering, not a run: no network, no downloads, no writes.

# STEP_N/STEP_TOTAL are read by the sourced library.
# shellcheck disable=SC2034
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
# shellcheck source=../sm-install-lib.sh
source ./sm-install-lib.sh

MODE="${1:-update}"
export SM_FORCE_COLOR="${SM_FORCE_COLOR:-1}"
sm_palette

TAG='v0.1.1-develop-020'
SHA='385ed6d4e9aa1e3ed82525f2c7839e85833145b77c3d29ab3d02dbb0c72ebb33'

case "$MODE" in
  update)  MODE_WORD='Update';  SUB='channel=develop · from install receipt'; BIN_STEPS=0 ;;
  install) MODE_WORD='Install'; SUB='channel=release · first run';            BIN_STEPS=19 ;;
  *) echo "usage: $0 [update|install]" >&2; exit 1 ;;
esac

STEP_TOTAL=$(( 3 + 2 * 5 + BIN_STEPS ))
STEP_N=0

sm_banner "$MODE_WORD" "$SUB"

confirm_section 'Prerequisites'
sm_ok "PowerShell 7 present: $(sm_tilde "$HOME/.local/bin/pwsh-7/pwsh")"
sm_ok "cosign present: $(sm_tilde "$HOME/.local/bin/cosign")"
sm_working 'Initializing cosign TUF trust (tuf-repo.github.com)...'
sm_ok "cosign TUF initialized in $(sm_tilde "$HOME/.simplemotion/sigstore")"

confirm_section 'Download'
for pkg in sm-welcome sm-onboard; do
    sm_ok "Resolved $pkg $TAG (channel=develop, aarch64-apple-darwin)"
    sm_working "Downloading $pkg..."
    sm_ok "Downloaded ${pkg}-mac-arm64"
    sm_ok "Checksum verified ${C_DIM}(SHA256 ${SHA:0:8}…${SHA: -8})${C_OFF}"
    sm_ok 'Provenance verified (cosign; built from 3400-0009-SM-Welcome via sm-ci)'
    sm_ok "Installed $pkg $TAG"
    sm_note "store  $(sm_tilde "$HOME/.simplemotion/share/develop/$pkg/$TAG")"
    sm_note "linked $(sm_tilde "$HOME/.simplemotion/bin/$pkg")"
done

if [[ "$MODE" == update ]]; then
    # `update` hands the binary `list`, which prints the step table and
    # exits. Rendered here in the binary's own format.
    # The binary's listing. Its bracket is an INDEX out of the highest
    # index, not a position out of a count — 00..18 for nineteen steps —
    # because the number shown is the one `sm-welcome step NN` resolves.
    row() { printf '  [%s] %s%s\n' "$1" "$(sm_counter_of "$2" 18)" "$3"; }
    for phase in Install 'Authenticate & Build' Configure Finish; do
        sm_phase "$phase"
        case "$phase" in
          Install)
            row "${C_GREEN}✓${C_OFF}" 0 'Detect platform, check prerequisites'
            row "${C_GREEN}✓${C_OFF}" 1 'Install GitHub CLI to ~/.local/bin' ;;
          Configure)
            row "${C_GREEN}✓${C_OFF}" 13 'Deploy ~/.claude/CLAUDE.md from canonical source' ;;
          Finish)
            row ' ' 18 'Configure Claude Desktop + point at the web checklist' ;;
          *)
            row "${C_GREEN}✓${C_OFF}" 8 'Authenticate with GitHub' ;;
        esac
    done
    printf '\n'
    STEP_TOTAL=0
    # Exactly what cmd_update prints: the destination on the marker line,
    # the origin as detail under it. It said `updated: X → Y` here, which the
    # binary stopped saying, and it claimed a line about sm-onboard that
    # cmd_update has never printed at all. A preview that invents output is
    # worse than no preview, because it gets reviewed and believed.
    sm_ok "sm-welcome updated to $TAG"
    sm_note 'from v0.1.1-develop-019'
else
    sm_phase 'Install'
    sm_working 'Installing GitHub CLI to ~/.local/bin...'
    sm_ok 'GitHub CLI installed'
    sm_act 'Open https://microsoft.com/devicelogin and enter code F7K-2QX9'
    sm_skip 'Touch ID for sudo skipped (no Secure Enclave)'
    sm_warn 'rust-analyzer LSP not installed'
    sm_note 'Re-run `sm-welcome step 10-install-mcp` once the toolchain settles.'
fi
printf '\n'
