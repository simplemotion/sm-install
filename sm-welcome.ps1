# SimpleMotion onboarding bootstrap (Windows).
# Thin wrapper around sm-install.ps1 — fetches sm-welcome and execs it.
#
# Usage:
#   irm https://install.simplemotion.com/sm-welcome.ps1 | iex
#   $env:SM_CHANNEL='preview'; irm https://install.simplemotion.com/sm-welcome.ps1 | iex
#
# Three interactive sections, each gated by a Y/n prompt:
#   1. Prerequisites — install PowerShell 7 + Git via winget (skipped per
#                      package if already present)
#   2. sm-welcome    — download + verify sm-welcome.exe from the selected
#                      channel; fast-paths if local copy is already at the
#                      latest tag
#   3. Launch        — exec sm-welcome.exe in a fresh pwsh 7 console so
#                      the user lands in the modern shell going forward
#
# Non-interactive override: set $env:SM_WELCOME_ASSUME_YES=1 to auto-accept
# every section prompt (used by CI / unattended re-runs).

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "  SimpleMotion — Development Environment Onboarding"
Write-Host "  ══════════════════════════════════════════════════"
Write-Host ""

# Per-section gate. Prints a framed header + description, then blocks on
# Read-Host until the user confirms. Default = Yes (Enter accepts). Any
# other response aborts the entire bootstrap.
function Confirm-Section($title, $lines) {
    Write-Host ""
    Write-Host ("  ── {0} {1}" -f $title, ('─' * [Math]::Max(0, 36 - $title.Length)))
    foreach ($l in $lines) { Write-Host ("      {0}" -f $l) }
    Write-Host ""
    if ($env:SM_WELCOME_ASSUME_YES) {
        Write-Host "  [+] Proceeding (SM_WELCOME_ASSUME_YES set)" -ForegroundColor DarkGray
        return
    }
    $resp = Read-Host "  Proceed? [Y/n]"
    $resp = if ($resp) { $resp.Trim().ToLower() } else { '' }
    if ($resp -notin @('', 'y', 'yes')) {
        Write-Host "  [!] Aborted by user." -ForegroundColor Yellow
        exit 1
    }
}

function Find-Pwsh7 {
    $cmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'PowerShell\7\pwsh.exe'),
        (Join-Path $HOME 'AppData\Local\Microsoft\PowerShell\7\pwsh.exe')
    )
    foreach ($p in $candidates) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return $null
}

# sm-welcome's step-counter UI accounts for the bootstrap's pre-binary
# steps via env vars the binary reads.
$env:SM_WELCOME_NO_BANNER    = '1'
$env:SM_WELCOME_STEPS_OFFSET = '5'
# Binary has 15 internal steps (00-preflight through 14-reload-shell);
# bootstrap contributes 5 silent steps. 5 + 15 = 20.
# Update if the binary's step count changes.
$env:SM_WELCOME_STEPS_TOTAL  = '20'

$channel    = if ($env:SM_CHANNEL) { $env:SM_CHANNEL } else { 'release' }
$installDir = if ($env:SM_INSTALL_DIR) { $env:SM_INSTALL_DIR } else { Join-Path $HOME '.simplemotion\bin' }
$localBin   = Join-Path $installDir 'sm-welcome.exe'

# ── Section 1: Prerequisites ───────────────────────────────────────────
$pwshPath = Find-Pwsh7
$gitCmd   = Get-Command git -ErrorAction SilentlyContinue
$needPwsh = -not $pwshPath
$needGit  = -not $gitCmd

$prereqLines = @(
    "Checks for PowerShell 7 and Git, and installs anything missing via winget.",
    ("  PowerShell 7: {0}" -f $(if ($needPwsh) { 'will install (winget Microsoft.PowerShell)' } else { "already present ($pwshPath)" })),
    ("  Git:          {0}" -f $(if ($needGit)  { 'will install (winget Git.Git)'           } else { "already present ($($gitCmd.Source))" }))
)
Confirm-Section 'Prerequisites' $prereqLines

if ($needPwsh) {
    Write-Host "  [*] Installing PowerShell 7..." -ForegroundColor DarkGray
    winget install --id Microsoft.PowerShell --source winget --silent --accept-source-agreements --accept-package-agreements | Out-Null
    $pwshPath = Find-Pwsh7
    if ($pwshPath) {
        Write-Host ("  [v] PowerShell 7 installed: {0}" -f $pwshPath) -ForegroundColor Green
    } else {
        Write-Host "  [!] pwsh.exe not found after winget install — will fall back to current shell" -ForegroundColor Yellow
    }
}
if ($needGit) {
    Write-Host "  [*] Installing Git..." -ForegroundColor DarkGray
    winget install --id Git.Git --source winget --silent --accept-source-agreements --accept-package-agreements | Out-Null
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd) {
        Write-Host ("  [v] Git installed: {0}" -f $gitCmd.Source) -ForegroundColor Green
    } else {
        Write-Host "  [!] git not on PATH after winget install — sm-welcome will report this" -ForegroundColor Yellow
    }
}

# ── Section 2: sm-welcome ──────────────────────────────────────────────
# Fast-path resolution: if the binary is already on disk, ask the channel
# repo for the latest tag. If they match, skip the download entirely.
$skipDownload = $false
$localVer  = $null
$latestVer = $null
if (-not $env:SM_WELCOME_SKIP_FAST_PATH -and (Test-Path $localBin)) {
    try {
        $verOut = (& $localBin -V 2>$null) -join ''
        if ($verOut -match '^\s*sm-welcome\s+v?(\S+)') { $localVer = $matches[1] }
    } catch { $localVer = $null }

    $channelRepo = $null
    switch ($channel) {
        'release' { $channelRepo = 'simplemotion/release' }
        'preview' { $channelRepo = 'simplemotion/preview' }
        'private' { $channelRepo = 'simplemotion/private' }
        'testing' { $channelRepo = 'simplemotion/testing' }
    }
    if ($channelRepo) {
        try {
            $latest = Invoke-RestMethod -Uri ("https://api.github.com/repos/{0}/releases/latest" -f $channelRepo) -UseBasicParsing
            if ($latest -and $latest.tag_name) {
                $tag = $latest.tag_name
                if ($tag.StartsWith('v')) { $tag = $tag.Substring(1) }
                $latestVer = $tag
            }
        } catch { $latestVer = $null }
    }
    if ($localVer -and $latestVer -and $localVer -eq $latestVer) {
        $skipDownload = $true
    }
}

$smLines = @()
if ($skipDownload) {
    $smLines += "Local sm-welcome $localVer is already at the latest tag for channel=$channel."
    $smLines += "  Download step will be skipped; we'll launch the local binary."
} else {
    $smLines += "Downloads sm-welcome.exe from simplemotion/$channel, verifies SHA256 +"
    $smLines += "  sigstore build-provenance, and installs to $installDir."
    if ($localVer -and $latestVer) {
        $smLines += ("  Local $localVer → installing $latestVer (channel=$channel).")
    } elseif ($latestVer) {
        $smLines += ("  Installing $latestVer (channel=$channel).")
    } else {
        $smLines += ("  Channel: $channel.")
    }
}
Confirm-Section 'sm-welcome' $smLines

if (-not $skipDownload) {
    $installer = (New-Object Net.WebClient).DownloadString('https://install.simplemotion.com/sm-install.ps1')
    $sb = [ScriptBlock]::Create($installer)
    & $sb -Package 'sm-welcome' `
          -AssetSuffix 'short' `
          -SourceRepo '3400-0000-SM-Software/3400-0009-SM-Welcome' `
          -Channel $channel `
          -Mode 'install'
}

# ── Section 3: Launch ──────────────────────────────────────────────────
$launchLines = @()
if ($pwshPath) {
    $launchLines += "Opens sm-welcome.exe in a new PowerShell 7 console window so the"
    $launchLines += "  rest of onboarding runs in the modern shell. The original window"
    $launchLines += "  stays open; -NoExit keeps the new pwsh session alive afterward."
    $launchLines += ("  pwsh: $pwshPath")
} else {
    $launchLines += "PowerShell 7 is unavailable; sm-welcome.exe will run in the current"
    $launchLines += "  Windows PowerShell session instead."
}
$launchLines += ("  Binary: $localBin")
Confirm-Section 'Launch' $launchLines

if ($pwshPath) {
    Start-Process $pwshPath -ArgumentList @('-NoExit', '-Command', "& '$localBin'")
} else {
    & $localBin
}
