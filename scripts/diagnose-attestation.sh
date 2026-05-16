#!/usr/bin/env bash
# Diagnostic for sm-welcome attestation-verify failure on greg-gowans@crow.
#
# Runs three controlled variations of `gh attestation verify` to isolate
# whether the failure depends on the file path / filename:
#
#   Test 1 — relative paths with the original asset name (Greg's manual
#            invocation that succeeded).
#   Test 2 — absolute tempfile paths (`mktemp` defaults: no asset name)
#            which mirrors install.sh's invocation that fails.
#   Test 3 — absolute paths with the asset name in a tempdir (combines
#            install.sh's tempdir hygiene with proper file naming).
#
# Outputs are NOT redirected so we see gh's real error if any test fails.
#
# Usage:
#   curl -fsSL https://install.simplemotion.com/diagnose-attestation.sh | bash
# or
#   bash /tmp/diagnose-attestation.sh [channel] [tag] [triple]
#
# Defaults: channel=preview, tag=v0.1.26-preview-002, triple=aarch64-apple-darwin

set -uo pipefail

CHANNEL="${1:-preview}"
TAG="${2:-v0.1.26-preview-002}"
TRIPLE="${3:-aarch64-apple-darwin}"
ASSET="sm-welcome-${TRIPLE}"
URL="https://github.com/simplemotion/${CHANNEL}/releases/download/${TAG}/${ASSET}"
SOURCE_REPO="3400-0000-SM-Software/3400-0009-SM-Welcome"

# Pretty
if [[ -t 1 ]]; then
    GREEN=$'\e[92m'; RED=$'\e[91m'; YELLOW=$'\e[93m'; DIM=$'\e[2m'; RESET=$'\e[0m'
else
    GREEN=''; RED=''; YELLOW=''; DIM=''; RESET=''
fi

banner() {
    printf '\n%s━━━ %s ━━━%s\n' "$DIM" "$1" "$RESET"
}

result() {
    local name="$1" exit="$2"
    if [[ "$exit" -eq 0 ]]; then
        printf '%s✓%s %s (exit 0)\n' "$GREEN" "$RESET" "$name"
    else
        printf '%s✗%s %s (exit %s)\n' "$RED" "$RESET" "$name" "$exit"
    fi
}

# --- Setup --------------------------------------------------------------
banner "Setup"
printf 'channel:      %s\n' "$CHANNEL"
printf 'tag:          %s\n' "$TAG"
printf 'triple:       %s\n' "$TRIPLE"
printf 'asset:        %s\n' "$ASSET"
printf 'url:          %s\n' "$URL"
printf 'source-repo:  %s\n' "$SOURCE_REPO"
printf 'gh path:      %s\n' "$(command -v gh 2>/dev/null || echo 'NOT FOUND')"
printf 'gh version:   %s\n' "$(gh --version 2>/dev/null | head -1 || echo 'n/a')"

# --- Test 1: relative paths, asset name -------------------------------------
banner "Test 1 — relative paths, asset name in filename"
T1_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'sm-test')
cd "$T1_DIR"
curl -fsSL "$URL" -o "$ASSET" || { echo "binary download failed"; exit 2; }
curl -fsSL "${URL}.sigstore.jsonl" -o "${ASSET}.sigstore.jsonl" || { echo "bundle download failed"; exit 2; }
printf '%spwd: %s%s\n' "$DIM" "$(pwd)" "$RESET"
ls -la "./${ASSET}" "./${ASSET}.sigstore.jsonl"
echo
gh attestation verify "./${ASSET}" --bundle "./${ASSET}.sigstore.jsonl" --repo "$SOURCE_REPO"
T1_EXIT=$?
cd /
rm -rf "$T1_DIR"

# --- Test 2: anonymous tempfile paths (install.sh's pattern) ----------------
banner "Test 2 — anonymous tempfile paths (install.sh's pattern)"
T2_BIN=$(mktemp)
T2_ATT=$(mktemp)
curl -fsSL "$URL" -o "$T2_BIN" || { echo "binary download failed"; exit 2; }
curl -fsSL "${URL}.sigstore.jsonl" -o "$T2_ATT" || { echo "bundle download failed"; exit 2; }
ls -la "$T2_BIN" "$T2_ATT"
echo
gh attestation verify "$T2_BIN" --bundle "$T2_ATT" --repo "$SOURCE_REPO"
T2_EXIT=$?
rm -f "$T2_BIN" "$T2_ATT"

# --- Test 3: named files inside tempdir (hybrid) ----------------------------
banner "Test 3 — named files inside tempdir (absolute paths, asset name)"
T3_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'sm-test')
curl -fsSL "$URL" -o "${T3_DIR}/${ASSET}" || { echo "binary download failed"; exit 2; }
curl -fsSL "${URL}.sigstore.jsonl" -o "${T3_DIR}/${ASSET}.sigstore.jsonl" || { echo "bundle download failed"; exit 2; }
ls -la "${T3_DIR}/${ASSET}" "${T3_DIR}/${ASSET}.sigstore.jsonl"
echo
gh attestation verify "${T3_DIR}/${ASSET}" --bundle "${T3_DIR}/${ASSET}.sigstore.jsonl" --repo "$SOURCE_REPO"
T3_EXIT=$?
rm -rf "$T3_DIR"

# --- Summary ----------------------------------------------------------------
banner "Summary"
result "Test 1 (relative + named)            " "$T1_EXIT"
result "Test 2 (anonymous tempfiles)         " "$T2_EXIT"
result "Test 3 (absolute tempdir + named)    " "$T3_EXIT"

printf '\n'
if [[ "$T1_EXIT" -eq 0 && "$T2_EXIT" -ne 0 && "$T3_EXIT" -eq 0 ]]; then
    printf '%sDiagnosis:%s gh attestation verify needs the asset name in the file path.\n' "$YELLOW" "$RESET"
    printf '            install.sh fix: download to "${TMPDIR}/${ASSET}" instead of plain mktemp.\n'
elif [[ "$T1_EXIT" -eq 0 && "$T2_EXIT" -eq 0 && "$T3_EXIT" -eq 0 ]]; then
    printf '%sDiagnosis:%s all three pass standalone. install.sh failure is elsewhere\n' "$YELLOW" "$RESET"
    printf '            (env var, set -e interaction, redirect side-effect). Need to instrument install.sh.\n'
elif [[ "$T1_EXIT" -ne 0 && "$T2_EXIT" -ne 0 && "$T3_EXIT" -ne 0 ]]; then
    printf '%sDiagnosis:%s every variant fails — environmental issue (network, TUF cache, gh state)\n' "$YELLOW" "$RESET"
    printf '            unrelated to install.sh. Look at the gh error text in each test.\n'
else
    printf '%sDiagnosis:%s unexpected pattern. Send the full output back for review.\n' "$YELLOW" "$RESET"
fi
