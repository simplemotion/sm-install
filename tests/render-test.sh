#!/usr/bin/env bash
# Contract tests for the shared output format in sm-install-lib.sh.
#
# The format is drawn by three programs — sm-welcome.sh, sm-install.sh and
# the sm-welcome binary — and every past divergence between them was a
# SILENT one: a green that was 32 in one file and 92 in another, a
# continuation indent five columns short of the gutter it documented, a
# rule that came out two characters long on macOS and nowhere else. None of
# that fails a build and none of it is obvious in a diff, so it is asserted
# here instead of noticed later in a screenshot.
#
# Run:  bash tests/render-test.sh
# No network, no installs, no writes outside a temp file.

# STEP_N/STEP_TOTAL are read by the sourced library, and every ~ below is
# an expected VALUE rather than a path to expand.
# shellcheck disable=SC2034,SC2088
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

# shellcheck source=../sm-install-lib.sh
source ./sm-install-lib.sh

PASS=0; FAIL=0
CAP="$(mktemp)"; trap 'rm -f "$CAP"' EXIT

ok()  { PASS=$(( PASS + 1 )); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$(( FAIL + 1 )); printf '  FAIL %s\n       %s\n' "$1" "$2"; }
is()    { if [[ "$2" == "$3"  ]]; then ok "$1"; else bad "$1" "want [$3] got [$2]"; fi; }
has()   { if [[ "$2" == *"$3"* ]]; then ok "$1"; else bad "$1" "[$2] lacks [$3]"; fi; }
hasnt() { if [[ "$2" != *"$3"* ]]; then ok "$1"; else bad "$1" "[$2] contains [$3]"; fi; }

# Render a renderer call and hand back what it wrote. The redirect runs in
# THIS shell, not a subshell, so a call that advances the step cursor
# actually advances it — `x="$(sm_ok ...)"` would test a throwaway copy.
render() { : > "$CAP"; "$@" >"$CAP" 2>&1; }
out()    { cat "$CAP"; }
line()   { sed -n "${1}p" "$CAP"; }
nlines() { wc -l < "$CAP" | tr -d ' '; }

plain_mode() { export NO_COLOR=1; unset SM_FORCE_COLOR SM_FORCE_TTY; sm_palette; }
plain_mode

printf '\n== rule geometry ==\n'
is 'sm_rule draws n glyphs'         "$(sm_rule '-' 5)"  '-----'
is 'sm_rule 0 draws nothing'        "$(sm_rule '-' 0)"  ''
# BSD seq counts DOWN from 1 to 0, so the seq-based rule this replaced
# emitted two characters for a zero-width pad — on macOS only.
is 'sm_rule negative draws nothing' "$(sm_rule '-' -3)" ''

printf '\n== phase rule ==\n'
render sm_phase 'Install';              short="$(line 2)"
render sm_phase 'Authenticate & Build'; long="$(line 2)"
is 'phase rules are one fixed width'  "${#short}" "${#long}"
# "  " + "──" + " " + title + " " + pad, where pad = SM_RULE_W - len(title).
is 'phase rule width is SM_RULE_W + 6' "${#short}" "$(( SM_RULE_W + 6 ))"
is 'phase rule opens with a blank line' "$(line 1)" ''
render sm_phase "$(sm_rule 'x' 60)";    over="$(line 2)"
is 'over-long title gets no rule'          "${over: -1}" 'x'
is 'over-long title gets no trailing space' "$over" "  ── $(sm_rule 'x' 60)"

printf '\n== banner ==\n'
render sm_banner 'Update' 'channel=develop · from install receipt'
is 'blank line first'         "$(line 1)" ''
is 'banner title'             "$(line 2)" '  SimpleMotion — Development Environment Update'
title="$(line 2)"; rule="$(line 3)"
is 'rule matches title width' "${#rule}" "${#title}"
is 'subtitle rendered'        "$(line 4)" '  channel=develop · from install receipt'
hasnt 'no screen clear when not interactive' "$(out)" $'\033[2J'
# The width is computed from a constant plus the mode word, not ${#title}:
# ${#title} counts BYTES under LANG=C and overshoots by two on the em dash.
render sm_banner 'Install'; utf8_banner="$(out)"
( export LC_ALL=C LANG=C; sm_banner 'Install' ) >"$CAP" 2>&1
is 'banner is byte-identical under LANG=C' "$(out)" "$utf8_banner"

printf '\n== step lines and the counter ==\n'
STEP_N=0 STEP_TOTAL=0
render sm_ok 'hello';  is 'no counter until a budget is set' "$(out)" '  [✓] hello'
STEP_N=0 STEP_TOTAL=32
render sm_ok 'hello';  is 'counter is zero-padded NN/TT'     "$(out)" '  [✓] [01/32] hello'
render sm_warn 'b';    is 'each step advances the cursor'    "$(out)" '  [!] [02/32] b'
render sm_skip 'x';    is 'marker: skip'                     "$(out)" '  [-] [03/32] x'
render sm_fail 'x';    is 'marker: fail'                     "$(out)" '  [✗] [04/32] x'
render sm_act  'x';    is 'marker: act'                      "$(out)" '  [>] [05/32] x'

render sm_counter_of 7 18
is 'explicit bracket matches the live counter format' "$(out)" '[07/18] '

printf '\n== the gutter ==\n'
STEP_N=0 STEP_TOTAL=32
render sm_ok 'msg';   step_line="$(out)"
render sm_note 'why'; note_line="$(out)"
indent="${note_line%%[! ]*}"
# The gutter must be exactly the width of the prefix on the line above, or
# continuation text sits under the counter rather than under the message it
# explains. "msg" is 3 characters.
is 'gutter matches a numbered step prefix' "$(sm_gutter)" "$(( ${#step_line} - 3 ))"
is 'note indents to the gutter'            "${#indent}"   "$(sm_gutter)"
is 'note carries no marker'                "$note_line"   "$(printf '%*swhy' "$(sm_gutter)" '')"
# Outside a step there is no counter, so the gutter shrinks to match. A
# fixed 14 hung the summary line's detail eight columns adrift.
STEP_N=0 STEP_TOTAL=0
render sm_ok 'msg';   bare_line="$(out)"
render sm_note 'why'; bare_note="$(out)"
is 'gutter matches an unnumbered prefix' "$(sm_gutter)" "$(( ${#bare_line} - 3 ))"
bare_indent="${bare_note%%[! ]*}"
is 'unnumbered note indents to 6'        "${#bare_indent}" "$SM_GUTTER_BASE"
# A three-digit total widens the counter asymmetrically — STEP_N still
# renders as "05" — so a gutter derived from the total's width alone is
# one column out. Measured off the real line instead.
STEP_N=5 STEP_TOTAL=120
render sm_ok 'msg'; wide_line="$(out)"
is 'gutter follows a 3-digit total' "$(sm_gutter)" "$(( ${#wide_line} - 3 ))"

printf '\n== in-progress lines ==\n'
STEP_N=4 STEP_TOTAL=32
render sm_working 'Downloading...'
is 'sm_working shows the number it will take' "$(out)" '  [*] [05/32] Downloading...'
is 'sm_working does not advance the cursor'   "$STEP_N" '4'
is 'non-interactive progress line terminates' "$(nlines)" '1'
render sm_ok 'Downloaded'
is 'the outcome line takes that number'       "$(out)" '  [✓] [05/32] Downloaded'

printf '\n== interactive mode ==\n'
export SM_FORCE_TTY=1 SM_FORCE_COLOR=1; unset NO_COLOR; sm_palette
STEP_N=0 STEP_TOTAL=9
: > "$CAP"; sm_working 'busy' >>"$CAP"; sm_ok 'done' >>"$CAP"
# One physical line: the outcome erases the progress line instead of
# stacking under it. That stacking is what put [03/32] on screen twice.
is 'progress line is overwritten, not stacked' "$(nlines)" '1'
has 'outcome leads with the erase sequence'    "$(out)" $'\r\033[K'
has 'colour is emitted when forced'            "$(out)" $'\033[92m'
render sm_banner 'Update'
has 'banner clears the screen, not scrollback' "$(out)" $'\033[2J\033[H'
hasnt 'banner does not clear scrollback'       "$(out)" $'\033[3J'

printf '\n== NO_COLOR ==\n'
# NO_COLOR strips COLOUR. It deliberately does not strip cursor control:
# a caller that asked for no SGR still wants one progress line rewritten
# in place rather than two lines of it, so the erase stays. The two
# decisions are separate functions for exactly this reason.
export NO_COLOR=1 SM_FORCE_COLOR=1 SM_FORCE_TTY=1; sm_palette
: > "$CAP"; sm_ok 'x' >>"$CAP"; sm_phase 'y' >>"$CAP"; sm_banner 'Update' 'z' >>"$CAP"
hasnt 'NO_COLOR strips green'  "$(out)" $'\033[92m'
hasnt 'NO_COLOR strips dim'    "$(out)" $'\033[2m'
hasnt 'NO_COLOR strips bold'   "$(out)" $'\033[1m'
has   'NO_COLOR keeps the erase' "$(out)" $'\r\033[K'
# With nothing forced and no terminal, nothing escapes at all — this is
# what a CI log and a piped install receipt see.
plain_mode
: > "$CAP"; sm_ok 'x' >>"$CAP"; sm_phase 'y' >>"$CAP"; sm_banner 'Update' 'z' >>"$CAP"
hasnt 'a piped run emits no escapes whatsoever' "$(out)" $'\033'

printf '\n== path abbreviation ==\n'
is 'home becomes a bare tilde'        "$(HOME=/Users/x sm_tilde /Users/x/.local/bin/cosign)" '~/.local/bin/cosign'
is 'no stray backslash on bash 3.2'   "$(HOME=/Users/x sm_tilde /Users/x/a)" '~/a'
is 'a non-home path is untouched'     "$(HOME=/Users/x sm_tilde /opt/thing)" '/opt/thing'
is 'only a leading match abbreviates' "$(HOME=/Users/x sm_tilde /srv/Users/x/a)" '/srv/Users/x/a'

# Update this when adding or removing a check — deliberately, so that
# removing one is a decision rather than an accident.
EXPECTED_CHECKS=45
TOTAL=$(( PASS + FAIL ))
if [[ $TOTAL -ne $EXPECTED_CHECKS ]]; then
    bad 'check count' "ran $TOTAL checks, expected $EXPECTED_CHECKS — an assertion was skipped or added"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
