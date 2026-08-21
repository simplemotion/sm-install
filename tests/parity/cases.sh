#!/usr/bin/env bash
# Bash driver for the renderer parity test. Emits one labelled block per
# case; tests/render-parity.sh runs this and its .ps1 twin and diffs the
# two byte for byte. Keep the cases, their order, and their labels in
# lock-step with cases.ps1 — the case count is pinned by the runner, so a
# case that vanishes from one side fails rather than shrinking coverage.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../sm-install-lib.sh"
sm_palette

c() { printf 'CASE %s\n' "$1"; }

c banner-update;   sm_banner 'Update' 'channel=develop · from install receipt'
c banner-install;  sm_banner 'Install'
c banner-two-subs; sm_banner 'Update' 'first line' 'second line'

c phase-short;     sm_phase 'Install'
c phase-long;      sm_phase 'Authenticate & Fetch'
c phase-exact;     sm_phase "$(sm_rule 'x' 36)"
c phase-overlong;  sm_phase "$(sm_rule 'x' 60)"

c rule-zero;       printf '[%s]\n' "$(sm_rule '-' 0)"
c rule-neg;        printf '[%s]\n' "$(sm_rule '-' -3)"
c rule-five;       printf '[%s]\n' "$(sm_rule '-' 5)"

c counter-of;      printf '[%s]\n' "$(sm_counter_of 7 18)"
c counter-wide;    printf '[%s]\n' "$(sm_counter_of 5 120)"

STEP_N=0 STEP_TOTAL=0
c step-no-counter;  sm_ok 'no budget set'
c note-no-counter;  sm_note 'detail under an unnumbered line'

STEP_N=0 STEP_TOTAL=13
c markers;          sm_ok 'ok line'; sm_warn 'warn line'; sm_fail 'fail line'
                    sm_act 'act line'; sm_skip 'skip line'
c note-counter;     sm_note 'detail under a numbered line'

STEP_N=4 STEP_TOTAL=13
c working-then-ok;  sm_working 'Downloading...'; sm_ok 'Downloaded'

STEP_N=5 STEP_TOTAL=120
c note-wide;        sm_ok 'wide total'; sm_note 'aligned under a 3-digit total'

c tilde-home;      printf '[%s]\n' "$(sm_tilde "$HOME/.local/bin/cosign")"
c tilde-other;     printf '[%s]\n' "$(sm_tilde '/opt/thing')"
c tilde-embedded;  printf '[%s]\n' "$(sm_tilde "/srv$HOME/a")"
