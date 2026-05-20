# SimpleMotion onboarding bootstrap (Windows).
# Thin wrapper around sm-install.ps1 — fetches sm-welcome and execs it.
#
# Usage:
#   irm https://install.simplemotion.com/sm-welcome.ps1 | iex
#   $env:SM_CHANNEL='preview'; irm https://install.simplemotion.com/sm-welcome.ps1 | iex
#
# Clean re-install:
#   $env:SM_WELCOME_CLEAN=1; irm https://install.simplemotion.com/sm-welcome.ps1 | iex
# Wipes ~/.local, ~/.simplemotion, and ~/.sm-welcome.toml before Section 1,
# so the toolchain, sm-welcome install, sigstore TUF cache, and the
# binary's step-tracker are all rebuilt from scratch. `irm | iex` doesn't
# forward positional args, so the flag is plumbed as an env var.
#
# Three interactive sections, each gated by a Y/n prompt and prefaced by
# a splash explaining the section in detail:
#   1. Prerequisites — install PowerShell 7, Git, and cosign into
#                      ~/.local/bin via direct GitHub-release downloads
#                      (SHA256-verified against the API-published asset
#                      digests), then initialize cosign's TUF trust
#                      against GitHub's Sigstore (`tuf-repo.github.com`)
#                      so it can verify GitHub-issued attestations
#                      natively. No winget, no MSI, no sudo, no gh.
#   2. sm-welcome    — download sm-welcome.exe from the selected channel,
#                      verify SHA256 + sigstore build-provenance with
#                      cosign, then install. Fast-paths if the local
#                      copy is already at the latest tag.
#   3. Launch        — exec sm-welcome.exe in a fresh pwsh 7 console
#                      (using ~/.local/bin/pwsh-7/pwsh.exe) so the user
#                      lands in the modern shell going forward.
#
# Non-interactive override: set $env:SM_WELCOME_ASSUME_YES=1 to auto-accept
# every section prompt (used by CI / unattended re-runs).

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "  SimpleMotion — Development Environment Onboarding"
Write-Host "  ══════════════════════════════════════════════════"

# Per-section gate. Prints a framed one-line section header, then blocks
# on Read-Host until the user confirms. Default = Yes (Enter accepts).
# Any other response aborts the entire bootstrap.
function Confirm-Section($title) {
    Write-Host ""
    Write-Host ("  ── {0} {1}" -f $title, ('─' * [Math]::Max(0, 56 - $title.Length)))
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

# Canonical install root for all three tools. Single PATH entry suffices
# for cosign (top-level .exe); pwsh and git live in subdirs and get their
# own PATH entries appended in the same session below.
#
# *** Variable name is deliberately `$LocalBinDir`, not `$LocalBin`. ***
# PowerShell variable names are case-insensitive, so `$LocalBin` would
# collide with the existing `$localBin` (= path to sm-welcome.exe under
# $installDir) defined later in this script. That collision once caused
# cosign to be written to `<installDir>\sm-welcome.exe\cosign.exe`.
$LocalBinDir = Join-Path $HOME '.local\bin'
$LocalPwshDir = Join-Path $LocalBinDir 'pwsh-7'
$LocalGitDir = Join-Path $LocalBinDir 'git'

# Per-SimpleMotion TUF root for cosign so we don't clobber any existing
# public-good Sigstore trust the user may have under ~/.sigstore.
# Exported so sm-install.ps1 (Section 2) picks up the same value.
$env:TUF_ROOT = Join-Path $HOME '.simplemotion\sigstore'

# Host arch — used by every Install-* helper. cosign doesn't ship a
# Windows-arm64 build (only `cosign-windows-amd64.exe`), so we always
# pull the amd64 binary on Windows; Windows-on-ARM emulates x64 fine
# for a one-shot verify call. pwsh and Git both have native arm64.
$archSuffix = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
$archSuffixCosign = 'amd64'

# ── Discovery helpers ──────────────────────────────────────────────
# Deliberately check ~/.local/bin ONLY — system-wide pwsh / git / cosign
# installs are ignored. The SimpleMotion onboarding wants a controlled,
# per-user toolchain so version drift across machines stays bounded;
# Section 1 always provisions to ~/.local/bin even when the tools are
# already present in Program Files or on PATH.
function Find-Pwsh7 {
    $p = Join-Path $LocalPwshDir 'pwsh.exe'
    if (Test-Path $p) { return $p }
    return $null
}
function Find-Git {
    $p = Join-Path $LocalGitDir 'cmd\git.exe'
    if (Test-Path $p) { return $p }
    return $null
}
function Find-Cosign {
    $p = Join-Path $LocalBinDir 'cosign.exe'
    if (Test-Path $p) { return $p }
    return $null
}

# ── Install helpers ────────────────────────────────────────────────
# Each Install-* fetches the project's /releases/latest metadata via the
# GitHub API to get tag + asset list + SHA256 digest in one call, then
# downloads the matching asset, SHA256-verifies, and unpacks to its
# install location. Returns the path to the installed binary on success
# or $null on failure (caller decides whether the missing tool is fatal).
function Get-LatestRelease($repo) {
    try {
        return Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -UseBasicParsing
    } catch {
        Write-Host ("  [!] release lookup failed for {0}: {1}" -f $repo, $_.Exception.Message) -ForegroundColor Yellow
        return $null
    }
}
# PortableGit's 7z extract sets read-only attributes on parts of the tree
# (and antivirus / OneDrive can briefly hold file handles), which makes a
# plain `Remove-Item -Recurse -Force` fail with "You do not have sufficient
# access rights". cmd's rmdir /s /q ignores attributes and retries through
# transient locks, so we shell out to it for the trickiest cleanups.
function Remove-TreeForcefully($path) {
    if (-not (Test-Path $path)) { return }
    cmd /c "rmdir /s /q `"$path`"" 2>$null
    if (Test-Path $path) {
        # Fallback for tree paths that confuse cmd's rmdir (e.g. long paths
        # without the `\\?\` prefix). Clear read-only first, then retry.
        Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
            ForEach-Object { try { $_.Attributes = 'Normal' } catch {} }
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}
function Confirm-AssetDigest($file, $asset) {
    $expected = ($asset.digest -replace '^sha256:', '').ToLower()
    if (-not $expected) { return $false }
    $actual = (Get-FileHash -Path $file -Algorithm SHA256).Hash.ToLower()
    return ($expected -eq $actual)
}

function Install-PwshPortable {
    $rel = Get-LatestRelease 'PowerShell/PowerShell'
    if (-not $rel) { return $null }
    $version = $rel.tag_name.TrimStart('v')
    $assetName = "PowerShell-$version-win-$archSuffix.zip"
    $asset = $rel.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
    if (-not $asset) { Write-Host "  [!] PowerShell asset $assetName not in release" -ForegroundColor Yellow; return $null }
    $tmp = Join-Path $env:TEMP ("pwsh-{0}.zip" -f ([Guid]::NewGuid().ToString('N')))
    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmp -UseBasicParsing -ErrorAction Stop
        if (-not (Confirm-AssetDigest $tmp $asset)) {
            Remove-Item $tmp -ErrorAction SilentlyContinue
            Write-Host "  [!] PowerShell SHA256 mismatch" -ForegroundColor Yellow; return $null
        }
        Remove-TreeForcefully $LocalPwshDir
        New-Item -ItemType Directory -Path $LocalPwshDir -Force | Out-Null
        Expand-Archive -Path $tmp -DestinationPath $LocalPwshDir -Force
    } finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
    $exe = Join-Path $LocalPwshDir 'pwsh.exe'
    if (Test-Path $exe) { return $exe }
    return $null
}
function Install-GitPortable {
    $rel = Get-LatestRelease 'git-for-windows/git'
    if (-not $rel) { return $null }
    # git-for-windows tag is `v2.54.0.windows.1` but the asset filename
    # only embeds the upstream git version (`2.54.0`). Pull the asset
    # name out of the release listing directly rather than reconstructing it.
    $assetPattern = if ($archSuffix -eq 'arm64') { '*-arm64.7z.exe' } else { '*-64-bit.7z.exe' }
    $asset = $rel.assets | Where-Object { $_.name -like ('PortableGit-' + $assetPattern) } | Select-Object -First 1
    if (-not $asset) { Write-Host ("  [!] PortableGit asset matching {0} not in release" -f $assetPattern) -ForegroundColor Yellow; return $null }
    $tmp = Join-Path $env:TEMP ("portablegit-{0}.7z.exe" -f ([Guid]::NewGuid().ToString('N')))
    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmp -UseBasicParsing -ErrorAction Stop
        if (-not (Confirm-AssetDigest $tmp $asset)) {
            Remove-Item $tmp -ErrorAction SilentlyContinue
            Write-Host "  [!] Git SHA256 mismatch" -ForegroundColor Yellow; return $null
        }
        Remove-TreeForcefully $LocalGitDir
        New-Item -ItemType Directory -Path $LocalGitDir -Force | Out-Null
        # PortableGit-*.7z.exe is a 7z self-extractor. `-o<dir>` sets the
        # output dir, `-y` suppresses prompts. Wait for completion before
        # checking; the SFX runs detached otherwise.
        $proc = Start-Process -FilePath $tmp -ArgumentList @("-o`"$LocalGitDir`"", '-y') -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -ne 0) {
            Write-Host ("  [!] PortableGit extractor exited {0}" -f $proc.ExitCode) -ForegroundColor Yellow
            return $null
        }
    } finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
    $exe = Join-Path $LocalGitDir 'cmd\git.exe'
    if (Test-Path $exe) { return $exe }
    return $null
}
function Install-Cosign {
    $rel = Get-LatestRelease 'sigstore/cosign'
    if (-not $rel) { return $null }
    $assetName = "cosign-windows-$archSuffixCosign.exe"
    $asset = $rel.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
    if (-not $asset) { Write-Host "  [!] cosign asset $assetName not in release" -ForegroundColor Yellow; return $null }
    $tmp = Join-Path $env:TEMP ("cosign-{0}.exe" -f ([Guid]::NewGuid().ToString('N')))
    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmp -UseBasicParsing -ErrorAction Stop
        if (-not (Confirm-AssetDigest $tmp $asset)) {
            Remove-Item $tmp -ErrorAction SilentlyContinue
            Write-Host "  [!] cosign SHA256 mismatch" -ForegroundColor Yellow; return $null
        }
        if (-not (Test-Path $LocalBinDir)) { New-Item -ItemType Directory -Path $LocalBinDir -Force | Out-Null }
        Move-Item -Path $tmp -Destination (Join-Path $LocalBinDir 'cosign.exe') -Force
    } catch {
        Remove-Item $tmp -ErrorAction SilentlyContinue
        Write-Host ("  [!] cosign install failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        return $null
    }
    $exe = Join-Path $LocalBinDir 'cosign.exe'
    if (Test-Path $exe) { return $exe }
    return $null
}

# Point cosign at GitHub's Sigstore TUF repo so it can verify GitHub-issued
# attestations natively. Cosign walks the TUF chain from the bootstrap
# 1.root.json, fetches the current trusted_root.json (containing GitHub's
# Fulcio CA + TSA pubkeys), and caches everything under $env:TUF_ROOT.
# Idempotent: re-running just refreshes the cache.
function Initialize-CosignTuf($cosignExe) {
    if (-not $cosignExe) { return $false }
    if (-not (Test-Path $env:TUF_ROOT)) { New-Item -ItemType Directory -Path $env:TUF_ROOT -Force | Out-Null }
    $tmpRoot = Join-Path $env:TEMP ("gh-1.root-{0}.json" -f ([Guid]::NewGuid().ToString('N')))
    try {
        Invoke-WebRequest -Uri 'https://tuf-repo.github.com/1.root.json' -OutFile $tmpRoot -UseBasicParsing -ErrorAction Stop
        & $cosignExe initialize --mirror 'https://tuf-repo.github.com' --root $tmpRoot *> $null
        return ($LASTEXITCODE -eq 0)
    } catch {
        Write-Host ("  [!] cosign TUF init failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        return $false
    } finally {
        Remove-Item $tmpRoot -ErrorAction SilentlyContinue
    }
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

# Optional clean wipe. SM_WELCOME_CLEAN=1 deletes the three SimpleMotion-
# owned bootstrap locations on disk so Section 1 rebuilds from scratch:
# the local toolchain (~/.local), the install + receipts + TUF cache
# (~/.simplemotion), and the binary's step-tracker (~/.sm-welcome.toml).
if ($env:SM_WELCOME_CLEAN) {
    Write-Host ""
    Write-Host "  [!] SM_WELCOME_CLEAN set — wiping prior bootstrap state" -ForegroundColor Yellow
    foreach ($d in @((Join-Path $HOME '.local'), (Join-Path $HOME '.simplemotion'))) {
        if (Test-Path $d) {
            Remove-TreeForcefully $d
            Write-Host ("      removed {0}" -f $d) -ForegroundColor DarkGray
        }
    }
    $stateFile = Join-Path $HOME '.sm-welcome.toml'
    if (Test-Path $stateFile) {
        Remove-Item $stateFile -Force -ErrorAction SilentlyContinue
        Write-Host ("      removed {0}" -f $stateFile) -ForegroundColor DarkGray
    }
}

# ── Section 1: Prerequisites ──────────────────────────────────────────
$pwshPath   = Find-Pwsh7
$gitPath    = Find-Git
$cosignPath = Find-Cosign

Confirm-Section 'Section 1 of 3: Prerequisites'

if (-not $pwshPath) {
    Write-Host "  [*] Installing PowerShell 7 (portable)..." -ForegroundColor DarkGray
    $pwshPath = Install-PwshPortable
    if ($pwshPath) { Write-Host ("  [v] PowerShell 7 installed: {0}" -f $pwshPath) -ForegroundColor Green }
}
if (-not $gitPath) {
    Write-Host "  [*] Installing Git (PortableGit)..." -ForegroundColor DarkGray
    $gitPath = Install-GitPortable
    if ($gitPath) { Write-Host ("  [v] Git installed: {0}" -f $gitPath) -ForegroundColor Green }
}
if (-not $cosignPath) {
    Write-Host "  [*] Installing cosign..." -ForegroundColor DarkGray
    $cosignPath = Install-Cosign
    if ($cosignPath) { Write-Host ("  [v] cosign installed: {0}" -f $cosignPath) -ForegroundColor Green }
}

# Initialize cosign's TUF trust against GitHub's Sigstore. Runs even if
# cosign was already on disk so re-bootstraps refresh the cache.
if ($cosignPath) {
    Write-Host "  [*] Initializing cosign TUF trust (tuf-repo.github.com)..." -ForegroundColor DarkGray
    if (Initialize-CosignTuf $cosignPath) {
        Write-Host ("  [v] cosign TUF initialized in {0}" -f $env:TUF_ROOT) -ForegroundColor Green
    } else {
        Write-Host "  [!] cosign TUF init failed — Section 2 will skip attestation verification" -ForegroundColor Yellow
    }
}

# Extend the current session's PATH so Section 2's calls to cosign / git
# find the just-installed binaries without a new shell.
$env:PATH = "$LocalBinDir;$LocalPwshDir;$(Join-Path $LocalGitDir 'cmd');$env:PATH"

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

Confirm-Section 'Section 2 of 3: sm-welcome'

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
Confirm-Section 'Section 3 of 3: Launch'

if ($pwshPath) {
    Start-Process $pwshPath -ArgumentList @('-NoExit', '-Command', "& '$localBin'")
} else {
    & $localBin
}
