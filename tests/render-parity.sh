#!/usr/bin/env bash
# Cross-language parity test for the shared output format.
#
# The format is drawn by a Bash library and a PowerShell library. Both are
# implementations; NEITHER is the authority. This test is: it renders the
# same cases through both and fails on any byte of difference.
#
# It exists because they HAD diverged and nothing noticed. `Confirm-Section`
# drew `-- Title ---` on a width-56 ASCII formula while `sm_phase` drew
# `── Title ───` on width 36 in box-drawing — 62 columns against 42, in the
# same product, for two days after #82 changed one side. Two independently
# maintained test suites would not have caught that; a diff does.
#
# pwsh is cross-platform, so this needs no Windows runner: the renderer is
# string formatting, and string formatting is testable anywhere.
#
# Run:  bash tests/render-parity.sh
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

PWSH="${PWSH:-}"
if [[ -z "$PWSH" ]]; then
    for c in pwsh "$HOME/.local/bin/pwsh-7/pwsh" "$HOME/.local/bin/pwsh"; do
        command -v "$c" >/dev/null 2>&1 && { PWSH="$c"; break; }
        [[ -x "$c" ]] && { PWSH="$c"; break; }
    done
fi
if [[ -z "$PWSH" ]]; then
    echo "::error::pwsh not found — the parity test cannot run, so the two renderers are unverified. Install PowerShell 7 or set PWSH." >&2
    exit 1
fi

# A fixed HOME so the ~-abbreviation cases are comparable, and a fixed
# locale so neither side can be flattered by the host's.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export LC_ALL=C.UTF-8 LANG=C.UTF-8

fail=0
for mode in plain colour; do
    if [[ "$mode" == plain ]]; then
        export NO_COLOR=1; unset SM_FORCE_COLOR SM_FORCE_TTY
    else
        unset NO_COLOR; export SM_FORCE_COLOR=1 SM_FORCE_TTY=1
    fi
    # Both drivers inherit the same environment, so a palette or
    # interactivity decision that differs shows up as a diff.
    bash tests/parity/cases.sh          > "$TMP/bash.$mode"  2>"$TMP/bash.$mode.err"
    "$PWSH" -NoProfile -File tests/parity/cases.ps1 > "$TMP/pwsh.$mode" 2>"$TMP/pwsh.$mode.err"

    for side in bash pwsh; do
        if [[ -s "$TMP/$side.$mode.err" ]]; then
            printf '  FAIL %s driver wrote to stderr in %s mode:\n' "$side" "$mode"
            sed 's/^/       /' "$TMP/$side.$mode.err"; fail=1
        fi
    done

    b=$(grep -c '^CASE ' "$TMP/bash.$mode" || true)
    p=$(grep -c '^CASE ' "$TMP/pwsh.$mode" || true)
    # Pinned, so a case deleted from BOTH drivers fails instead of quietly
    # reducing what this test covers.
    EXPECTED_CASES=21
    if [[ "$b" != "$EXPECTED_CASES" || "$p" != "$EXPECTED_CASES" ]]; then
        printf '  FAIL %s mode: case count bash=%s pwsh=%s, expected %s\n' \
            "$mode" "$b" "$p" "$EXPECTED_CASES"; fail=1
    fi

    if cmp -s "$TMP/bash.$mode" "$TMP/pwsh.$mode"; then
        printf '  ok   %s mode: %s cases, byte-identical\n' "$mode" "$b"
    else
        printf '  FAIL %s mode: the two renderers disagree\n' "$mode"
        # Report by case, so the output names what diverged instead of
        # dumping two transcripts and leaving you to find it.
        awk '/^CASE /{c=$2} {print c"\t"$0}' "$TMP/bash.$mode" > "$TMP/b.tag"
        awk '/^CASE /{c=$2} {print c"\t"$0}' "$TMP/pwsh.$mode" > "$TMP/p.tag"
        diff "$TMP/b.tag" "$TMP/p.tag" | head -40 | sed 's/^/       /'
        fail=1
    fi
done

printf '\n'
if [[ $fail -eq 0 ]]; then echo "renderers agree in both modes"; else echo "renderers DISAGREE"; fi
exit "$fail"
