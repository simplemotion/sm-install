#!/usr/bin/env bash
# SimpleMotion Simplicity installer (macOS + Linux).
# Thin wrapper around sm-install.sh — installs sm-simplicity to PATH.
#
# Usage (command substitution avoids the curl: (56) race that pipe-into-
# bash forms produce when sm-install.sh hits its trailing `exec`):
#   bash -c "$(curl -fsSL https://install.simplemotion.com/sm-simplicity.sh)" sm-simplicity
#   SM_CHANNEL=preview bash -c "$(curl -fsSL https://install.simplemotion.com/sm-simplicity.sh)" sm-simplicity
#
# Channel selection via SM_CHANNEL (release | preview); default release.
# Tier selection (one/two/six) happens at runtime via `sm-simplicity` args.

set -euo pipefail

printf '\n  SimpleMotion — Simplicity Installer\n  ═══════════════════════════════════\n\n'

INSTALL_SH=$(curl -fsSL "https://install.simplemotion.com/sm-install.sh")
exec bash -c "$INSTALL_SH" install \
    --package sm-simplicity \
    --source-repo 3400-0000-SM-Software/3400-0026-SM-Simplicity \
    --tag-prefix sm-simplicity-v \
    --mode install
