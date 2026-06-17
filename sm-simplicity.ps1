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

# --- PowerShell 7 guard (must stay ASCII so Windows PowerShell 5.1 can parse
# the whole file before running this check). On 5.1, locate pwsh 7 (installing
# a portable copy into ~/.local/bin if absent) and relaunch under it. ---
if ($PSVersionTable.PSVersion.Major -lt 6) {
    $pwsh = Join-Path $HOME '.local\bin\pwsh-7\pwsh.exe'
    if (-not (Test-Path $pwsh)) {
        $found = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $pwsh = $found.Source }
    }
    if (-not (Test-Path $pwsh)) {
        Write-Host "  [*] Installing PowerShell 7 (portable) to run the installer..."
        $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
        $gh = @{ 'X-GitHub-Api-Version' = '2022-11-28' }
        if ($env:GH_TOKEN) { $gh['Authorization'] = "Bearer $($env:GH_TOKEN)" } elseif ($env:GITHUB_TOKEN) { $gh['Authorization'] = "Bearer $($env:GITHUB_TOKEN)" }
        $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' -UseBasicParsing -Headers $gh
        $ver = $rel.tag_name.TrimStart('v')
        $asset = $rel.assets | Where-Object { $_.name -eq "PowerShell-$ver-win-$arch.zip" } | Select-Object -First 1
        if (-not $asset) { Write-Host "  [x] No PowerShell 7 release asset for win-$arch." -ForegroundColor Red; exit 1 }
        $zip = Join-Path $env:TEMP ("pwsh-{0}.zip" -f ([Guid]::NewGuid().ToString('N')))
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing
        $want = ($asset.digest -replace '^sha256:', '').ToLower()
        $got  = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLower()
        if ($want -and $want -ne $got) { Remove-Item $zip -Force -ErrorAction SilentlyContinue; Write-Host "  [x] PowerShell 7 SHA256 mismatch." -ForegroundColor Red; exit 1 }
        $pwshDir = Join-Path $HOME '.local\bin\pwsh-7'
        if (Test-Path $pwshDir) { Remove-Item $pwshDir -Recurse -Force }
        New-Item -ItemType Directory -Path $pwshDir -Force | Out-Null
        Expand-Archive -Path $zip -DestinationPath $pwshDir -Force
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        $pwsh = Join-Path $pwshDir 'pwsh.exe'
    }
    Write-Host "  [*] Relaunching under PowerShell 7..."
    & $pwsh -NoProfile -Command "irm https://install.simplemotion.com/sm-simplicity.ps1 | iex"
    exit $LASTEXITCODE
}

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
