# SimpleMotion Simplicity installer (Windows).
# Thin wrapper around sm-install.ps1 - installs sm-simplicity to PATH.
#
# Usage:
#   irm https://install.simplemotion.com/sm-simplicity.ps1 | iex
#   $env:SM_CHANNEL='preview'; irm https://install.simplemotion.com/sm-simplicity.ps1 | iex

$ErrorActionPreference = 'Stop'

# Stock Windows PowerShell 5.1 negotiates TLS 1.0/1.1 by default, which GitHub
# and our Pages host reject - every WebClient/IWR/IRM call below would fail. Add
# TLS 1.2 to whatever's already enabled (preserving 1.3 where present). No-op on
# PowerShell 7 (already negotiates 1.2/1.3).
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# Source the shared install-toolchain library. Brings in Invoke-Pwsh7Guard
# (used immediately below) plus the helpers sm-install.ps1 needs once
# relaunched under pwsh 7 (Confirm-AssetDigest, Find-Cosign, etc.).
$smInstallLib = (New-Object Net.WebClient).DownloadString('https://install.simplemotion.com/sm-install-lib.ps1')
Invoke-Expression $smInstallLib

# On Windows PowerShell 5.1, relaunches this script under pwsh 7 (installing
# a portable copy into ~/.local/bin if absent) and exits. No-op on pwsh 6+.
Invoke-Pwsh7Guard -ScriptUrl 'https://install.simplemotion.com/sm-simplicity.ps1'

Write-Host ""
Write-Host "  SimpleMotion - Simplicity Installer"
Write-Host "  ==================================="
Write-Host ""

$installer = (New-Object Net.WebClient).DownloadString('https://install.simplemotion.com/sm-install.ps1')
$sb = [ScriptBlock]::Create($installer)
& $sb -Package 'sm-simplicity' `
      -SourceRepo '3400-0000-SM-Software/3400-0026-SM-Simplicity' `
      -TagPrefix 'sm-simplicity-v' `
      -Mode 'install'
