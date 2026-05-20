# SimpleMotion onboarding bootstrap (Windows).
# Thin wrapper around sm-install.ps1 — fetches sm-welcome and execs it.
#
# Usage:
#   irm https://install.simplemotion.com/sm-welcome.ps1 | iex
#   $env:SM_CHANNEL='preview'; irm https://install.simplemotion.com/sm-welcome.ps1 | iex
#
# Three interactive sections, each gated by a Y/n prompt and prefaced by
# a splash explaining the section in detail:
#   1. Prerequisites — install PowerShell 7, Git, and cosign via winget
#                      (already-present packages are detected + skipped).
#                      cosign powers Section 2's attestation check.
#   2. sm-welcome    — download sm-welcome.exe from the selected channel,
#                      verify SHA256 + sigstore build-provenance (cosign,
#                      installed in Section 1), then install. Fast-paths
#                      if the local copy is already at the latest tag.
#   3. Launch        — exec sm-welcome.exe in a fresh pwsh 7 console so
#                      the user lands in the modern shell going forward.
#
# Non-interactive override: set $env:SM_WELCOME_ASSUME_YES=1 to auto-accept
# every section prompt (used by CI / unattended re-runs).

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "  SimpleMotion — Development Environment Onboarding"
Write-Host "  ══════════════════════════════════════════════════"
Write-Host ""
Write-Host "  Welcome. This bootstrap runs in three sections, each gated by a"
Write-Host "  Y/n prompt so you can review before anything is changed:"
Write-Host ""
Write-Host "    1. Prerequisites  —  installs PowerShell 7, Git, and cosign via"
Write-Host "                         winget (silent, agreements pre-accepted)."
Write-Host "                         cosign verifies sm-welcome.exe's sigstore"
Write-Host "                         build provenance in Section 2 before any"
Write-Host "                         code from the release channel runs."
Write-Host "    2. sm-welcome     —  download, SHA256-check, and attestation-"
Write-Host "                         verify sm-welcome.exe, then install."
Write-Host "    3. Launch         —  open sm-welcome in a new pwsh 7 console."
Write-Host ""
Write-Host "  We'll start with Section 1 next."
Write-Host ""

# Per-section gate. Prints a framed header + description, then blocks on
# Read-Host until the user confirms. Default = Yes (Enter accepts). Any
# other response aborts the entire bootstrap.
function Confirm-Section($title, $lines) {
    Write-Host ""
    Write-Host ("  ── {0} {1}" -f $title, ('─' * [Math]::Max(0, 56 - $title.Length)))
    Write-Host ""
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

# Cosign isn't always on PATH in the session it was just winget-installed
# into (PATH refresh requires a new shell), so we also check winget's
# user-scope Links dir directly. sm-install.ps1 uses the same resolver.
function Find-Cosign {
    $cmd = Get-Command cosign -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\cosign.exe'),
        (Join-Path $env:ProgramFiles 'WinGet\Links\cosign.exe')
    )
    foreach ($p in $candidates) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    $pkgsRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path $pkgsRoot) {
        $cosignDir = Get-ChildItem $pkgsRoot -Directory -Filter 'sigstore.cosign*' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cosignDir) {
            $exe = Get-ChildItem $cosignDir.FullName -Filter 'cosign*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($exe) { return $exe.FullName }
        }
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

# ── Section 1: Prerequisites ──────────────────────────────────────────
$pwshPath   = Find-Pwsh7
$gitCmd     = Get-Command git -ErrorAction SilentlyContinue
$cosignPath = Find-Cosign
$needPwsh   = -not $pwshPath
$needGit    = -not $gitCmd
$needCosign = -not $cosignPath

$prereqLines = @(
    "Installs or verifies the three tools required for a secure bootstrap:",
    "",
    "  PowerShell 7  (winget Microsoft.PowerShell)  modern shell host",
    "  Git           (winget Git.Git)               clones the employee repo",
    "  cosign        (winget sigstore.cosign)       verifies sm-welcome's",
    "                                               sigstore build-provenance",
    "",
    "All installs run silently with --accept-source-agreements and",
    "--accept-package-agreements. Already-installed packages are skipped.",
    "",
    "cosign is the sole attestation verifier in Section 2 — if it doesn't",
    "install successfully, the provenance check is skipped (SHA256 still",
    "anchors integrity). Before sm-welcome.exe is installed or invoked, we",
    "verify it was built by SimpleMotion's CI in 3400-0009-SM-Welcome.",
    "",
    "Detected state:",
    ("  PowerShell 7: {0}" -f $(if ($needPwsh)   { 'missing — will install' } else { "present ($pwshPath)" })),
    ("  Git:          {0}" -f $(if ($needGit)    { 'missing — will install' } else { "present ($($gitCmd.Source))" })),
    ("  cosign:       {0}" -f $(if ($needCosign) { 'missing — will install' } else { "present ($cosignPath)" }))
)
Confirm-Section 'Section 1 of 3: Prerequisites' $prereqLines

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
if ($needCosign) {
    Write-Host "  [*] Installing cosign..." -ForegroundColor DarkGray
    winget install --id sigstore.cosign --source winget --silent --accept-source-agreements --accept-package-agreements | Out-Null
    $cosignPath = Find-Cosign
    if ($cosignPath) {
        Write-Host ("  [v] cosign installed: {0}" -f $cosignPath) -ForegroundColor Green
    } else {
        Write-Host "  [!] cosign install failed — Section 2 will skip attestation verification (SHA256 still anchors integrity)" -ForegroundColor Yellow
    }
}

# ── Section 2: sm-welcome ─────────────────────────────────────────────
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

$smLines = @(
    "Downloads and verifies sm-welcome.exe from simplemotion/$channel before",
    "any code from the release channel runs:",
    "",
    "  1. Fetch the binary plus two sidecar files:",
    "       <asset>.sha256             content checksum",
    "       <asset>.sigstore.jsonl     sigstore build-provenance bundle",
    "  2. Hash the binary; compare against the .sha256 file.",
    "  3. Verify the sigstore bundle with cosign — check the bundle's cert",
    "     identity matches the 3400-0009-SM-Welcome source repo.",
    "  4. Move the verified binary to $installDir.",
    "",
    "The binary is never installed or invoked until all checks pass."
)
$smLines += ""
if ($skipDownload) {
    $smLines += "Status: fast-path skip — local $localVer matches latest on channel=$channel."
} elseif ($localVer -and $latestVer) {
    $smLines += "Status: local $localVer → installing $latestVer (channel=$channel)."
} elseif ($latestVer) {
    $smLines += "Status: installing $latestVer (channel=$channel)."
} else {
    $smLines += "Status: installing latest (channel=$channel)."
}
Confirm-Section 'Section 2 of 3: sm-welcome' $smLines

if (-not $skipDownload) {
    $installer = (New-Object Net.WebClient).DownloadString('https://install.simplemotion.com/sm-install.ps1')
    $sb = [ScriptBlock]::Create($installer)
    & $sb -Package 'sm-welcome' `
          -AssetSuffix 'short' `
          -SourceRepo '3400-0000-SM-Software/3400-0009-SM-Welcome' `
          -Channel $channel `
          -Mode 'install'
}

# ── Section 3: Launch ─────────────────────────────────────────────────
$launchLines = @()
if ($pwshPath) {
    $launchLines += "Opens sm-welcome.exe in a brand-new PowerShell 7 console window."
    $launchLines += "The original window stays open. -NoExit keeps the new pwsh"
    $launchLines += "session alive after sm-welcome finishes, so onboarding lands you"
    $launchLines += "in the modern shell rather than dropping back to PS 5.1."
    $launchLines += ""
    $launchLines += "Env vars set in this session (\$env:SM_EMAIL, \$env:SM_CHANNEL,"
    $launchLines += "\$env:SM_WELCOME_*) flow through Start-Process and are visible"
    $launchLines += "to sm-welcome.exe in the new console."
    $launchLines += ""
    $launchLines += ("  pwsh:   $pwshPath")
    $launchLines += ("  binary: $localBin")
} else {
    $launchLines += "PowerShell 7 is unavailable, so sm-welcome.exe will run in the"
    $launchLines += "current Windows PowerShell session instead. No new console window"
    $launchLines += "is opened."
    $launchLines += ""
    $launchLines += ("  binary: $localBin")
}
Confirm-Section 'Section 3 of 3: Launch' $launchLines

if ($pwshPath) {
    Start-Process $pwshPath -ArgumentList @('-NoExit', '-Command', "& '$localBin'")
} else {
    & $localBin
}
