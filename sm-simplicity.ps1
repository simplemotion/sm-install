# SimpleMotion Simplicity installer (Windows).
# Thin wrapper around sm-install.ps1 — installs sm-simplicity to PATH.
#
# Usage:
#   irm https://install.simplemotion.com/sm-simplicity.ps1 | iex
#   $env:SM_CHANNEL='preview'; irm https://install.simplemotion.com/sm-simplicity.ps1 | iex

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "  SimpleMotion — Simplicity Installer"
Write-Host "  ═══════════════════════════════════"
Write-Host ""

$installer = (New-Object Net.WebClient).DownloadString('https://install.simplemotion.com/sm-install.ps1')
$sb = [ScriptBlock]::Create($installer)
& $sb -Package 'sm-simplicity' `
      -SourceRepo '3400-0000-SM-Software/3400-0026-SM-Simplicity' `
      -TagPrefix 'sm-simplicity-v' `
      -Mode 'install'
