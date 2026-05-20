# SimpleMotion generic binary installer base (Windows).
#
# Resolves a SimpleMotion-published binary from a GitHub Releases-hosting
# repo, verifies SHA256 + sigstore build-provenance attestation via cosign
# (installed to ~/.local/bin by sm-welcome.ps1's Section 1, with GitHub's
# Sigstore TUF root initialized in $env:TUF_ROOT), and either installs to
# PATH or execs from a temp file.
#
# Usage (typically called by a thin per-product wrapper):
#   irm "https://install.simplemotion.com/sm-install.ps1" |
#     iex "& { $input | Out-Null }; sm-install.ps1 -Repo ... -Package ..."
#
# More commonly invoked indirectly via a per-product wrapper that pipes
# this script's contents to iex and supplies the args.
#
# Required parameters:
#   -Repo OWNER/NAME             GitHub repo hosting the Releases.
#   -Package NAME                Binary name + asset prefix. Asset name
#                                resolves to `<package>-<host-triple>.exe`.
#
# Optional parameters:
#   -SourceRepo OWNER/NAME       Repo the attestation is signed against.
#                                Defaults to -Repo.
#   -TagPrefix PREFIX            Tag filter for channel resolution.
#   -Mode install|run|install-and-run
#                                install         = drop in install dir, exit.
#                                run             = exec from temp file.
#                                install-and-run = install AND exec from
#                                                  the install path.
#                                Default: install.
#   -InstallDir PATH             install mode only. Resolution order:
#                                -InstallDir > $env:SM_INSTALL_DIR >
#                                ~/.simplemotion/bin.
#   -Version TAG                 Pin a specific tag.
#   -Channel release|preview     Default: $env:SM_CHANNEL or 'release'.
#   -AssetSuffix triple|short    Asset-name suffix style:
#                                  triple = `<package>-<arch>-<os>.exe`
#                                           (default; e.g.
#                                           `sm-x-aarch64-pc-windows-msvc.exe`)
#                                  short  = `<package>-win-<arch>.exe`
#                                           with arm64/x64 short codes
#                                           (e.g. `sm-x-win-arm64.exe`).
#   -BinArgs ARGS                Forwarded to the binary in run mode.

param(
    [Parameter(Mandatory=$true)] [string]$Package,
    [string]$Repo = '',
    [string]$SourceRepo = '',
    [string]$TagPrefix = '',
    [ValidateSet('install','run','install-and-run')] [string]$Mode = 'install',
    [string]$InstallDir = '',
    [string]$Version = '',
    [ValidateSet('release','preview','private','testing')] [string]$Channel = '',
    [ValidateSet('triple','short')] [string]$AssetSuffix = 'triple',
    [string[]]$BinArgs = @()
)

$ErrorActionPreference = 'Stop'

# Surface SimpleMotion bins on `Get-Command` for the *first* run, before
# any profile-script PATH edit has taken effect in a new PowerShell
# session. (~/.local/bin is included for parity with the Bash side.)
$env:PATH = (Join-Path $HOME '.simplemotion\bin') + ';' + (Join-Path $HOME '.local\bin') + ';' + $env:PATH

if (-not $Channel) { $Channel = if ($env:SM_CHANNEL) { $env:SM_CHANNEL } else { 'release' } }
# Channel → repo defaulting. Each channel maps to its own GitHub repo.
if (-not $Repo) { $Repo = "simplemotion/$Channel" }
if (-not $SourceRepo) { $SourceRepo = $Repo }
if (-not $InstallDir) {
    if ($env:SM_INSTALL_DIR) {
        $InstallDir = $env:SM_INSTALL_DIR
    } elseif ($Package.StartsWith('sm-')) {
        $InstallDir = Join-Path $HOME '.simplemotion\bin'
    } else {
        $InstallDir = Join-Path $HOME '.local\bin'
    }
}

# Host triple + short OS/arch codes (used by -AssetSuffix=short).
$arch = if ([System.Environment]::Is64BitOperatingSystem) {
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'aarch64' } else { 'x86_64' }
} else {
    Write-Host "  [x] 32-bit Windows is not supported." -ForegroundColor Red
    exit 1
}
$archShort = if ($arch -eq 'aarch64') { 'arm64' } else { 'x64' }
$target = "$arch-pc-windows-msvc"
$suffix = if ($AssetSuffix -eq 'short') { "win-$archShort" } else { $target }
$asset  = "$Package-$suffix.exe"

# Step numbering — matches sm-welcome's `[NN/TOTAL]` counter so the
# Download phase and the binary's onboarding steps read as one
# continuous numbered sequence (01..TOTAL). Defaults to 20 (= 5
# download-phase steps + 15 onboarding steps).
$StepsTotal = if ($env:SM_WELCOME_STEPS_TOTAL) { $env:SM_WELCOME_STEPS_TOTAL } else { '20' }
function Format-Step([int]$i) { return ('[{0:D2}/{1}]' -f $i, $StepsTotal) }

# Resolve tag. With channel-per-repo, each repo has its own
# releases/latest and we never use the prerelease flag:
#   - Single-package channel repos: hit /releases/latest directly.
#   - Multi-package channel repos (-TagPrefix set): scan the releases
#     list and pick the newest tag matching the prefix.
if (-not $Version) {
    if ($TagPrefix) {
        $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases" -UseBasicParsing
        $picked = $releases | Where-Object { $_.tag_name.StartsWith($TagPrefix) } | Select-Object -First 1
        if (-not $picked) {
            Write-Host "  [x] No release available for $Package in $Repo (channel=$Channel)" -ForegroundColor Red
            exit 1
        }
        $Version = $picked.tag_name
    } else {
        try {
            $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -UseBasicParsing
            $Version = $latest.tag_name
        } catch {
            Write-Host "  [x] No release available for $Package in $Repo (channel=$Channel)" -ForegroundColor Red
            exit 1
        }
    }
}

$url = "https://github.com/$Repo/releases/download/$Version/$asset"

$tmpBin = [System.IO.Path]::Combine($env:TEMP, "$Package-$([Guid]::NewGuid().ToString('N')).exe")
$tmpSum = "$tmpBin.sha256"

# Phase header — matches sm-welcome's `phase_header` formatting so the
# download output frames as one continuous workflow. Rule width is
# 36 - len("Download") = 28 dashes (same formula as the Rust side).
Write-Host ""
Write-Host "  ── Download ────────────────────────────"
Write-Host ("  [+] {0} Platform: {1} (channel={2}, tag={3})" -f (Format-Step 1), $target, $Channel, $Version)

# Download binary.
Write-Host ("  [*] {0} Downloading {1}..." -f (Format-Step 2), $Package)
try {
    Invoke-WebRequest -Uri $url -OutFile $tmpBin -UseBasicParsing
} catch {
    Write-Host "  [x] Failed to download $url" -ForegroundColor Red
    exit 1
}

# Download + verify checksum.
try {
    Invoke-WebRequest -Uri "$url.sha256" -OutFile $tmpSum -UseBasicParsing
} catch {
    Remove-Item $tmpBin -ErrorAction SilentlyContinue
    Write-Host "  [x] Failed to download $url.sha256" -ForegroundColor Red
    exit 1
}
$expected = ((Get-Content $tmpSum -Raw).Trim() -split '\s+')[0]
$actual   = (Get-FileHash -Path $tmpBin -Algorithm SHA256).Hash.ToLower()
Remove-Item $tmpSum -ErrorAction SilentlyContinue
if ($expected -ne $actual) {
    Remove-Item $tmpBin -ErrorAction SilentlyContinue
    Write-Host "  [x] Checksum mismatch for ${asset}: expected $expected, got $actual" -ForegroundColor Red
    exit 1
}
Write-Host ("  [v] {0} Checksum verified (SHA256: {1})" -f (Format-Step 3), $actual) -ForegroundColor Green

# Locate cosign. sm-welcome.ps1's Section 1 always installs cosign to
# ~/.local/bin/cosign.exe (100% local toolchain — any system-wide cosign
# is ignored). We only probe that one path so this script picks up
# exactly the binary Section 1 provisioned.
function Find-Cosign {
    $local = Join-Path $HOME '.local\bin\cosign.exe'
    if (Test-Path $local) { return $local }
    return $null
}

# Attestation check — cosign-only. Verification of GitHub-issued
# attestations needs cosign pointed at GitHub's private Sigstore TUF
# (sm-welcome.ps1 ran `cosign initialize --mirror https://tuf-repo.github.com`
# into $env:TUF_ROOT during Section 1) plus the GH-Sigstore-shaped flag
# set: TSA timestamps instead of Rekor inclusion proofs, no SCTs on the
# leaf cert, SLSA-v1 predicate type. Bundle present + cosign rejects is
# fatal. Bundle present + cosign missing skips (SHA256 above still
# anchors integrity).
$bundleUrl = "$url.sigstore.jsonl"
$tmpAtt = [System.IO.Path]::Combine($env:TEMP, "$Package-$([Guid]::NewGuid().ToString('N')).sigstore.jsonl")
$bundleOk = $false
try {
    Invoke-WebRequest -Uri $bundleUrl -OutFile $tmpAtt -UseBasicParsing -ErrorAction Stop
    $bundleOk = $true
} catch { $bundleOk = $false }

# Default TUF_ROOT if Section 1 hasn't been through (e.g., sm-install.ps1
# invoked standalone). Will be empty/uninitialized if no init ever ran;
# cosign will then fall back to the public-good Sigstore and reject the
# GitHub-issued leaf cert — caller can spot that in the error.
if (-not $env:TUF_ROOT) { $env:TUF_ROOT = Join-Path $HOME '.simplemotion\sigstore' }

$cosignBin = Find-Cosign
if ($bundleOk -and $cosignBin) {
    $certIdRegex = "https://github.com/$SourceRepo/\.github/workflows/.*"
    & $cosignBin verify-blob-attestation `
        --bundle $tmpAtt `
        --new-bundle-format `
        --use-signed-timestamps `
        --insecure-ignore-tlog `
        --insecure-ignore-sct `
        --type slsaprovenance1 `
        --certificate-identity-regexp $certIdRegex `
        --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' `
        $tmpBin *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Host ("  [v] {0} Provenance verified (cosign, signed by {1})" -f (Format-Step 4), $SourceRepo) -ForegroundColor Green
    } else {
        Write-Host ("  [x] {0} Provenance verification failed (cosign rejected the bundle)" -f (Format-Step 4)) -ForegroundColor Red
        Remove-Item $tmpAtt, $tmpBin -ErrorAction SilentlyContinue
        exit 1
    }
} elseif ($bundleOk) {
    Write-Host ("  [-] {0} Provenance check skipped (cosign not installed)" -f (Format-Step 4)) -ForegroundColor DarkGray
} else {
    Write-Host ("  [-] {0} Provenance check skipped (no sigstore bundle on release)" -f (Format-Step 4)) -ForegroundColor DarkGray
}
Remove-Item $tmpAtt -ErrorAction SilentlyContinue

# Install-receipt: a per-package TOML at
# `~/.simplemotion/install-receipt/<package>.toml` recording the channel,
# tag, source-repo, asset SHA, and timestamp of this install. Consumed
# by the binary's own `update` subcommand so subsequent refreshes target
# the channel the user actually installed from. Best-effort: failure to
# create the receipt is reported but does not abort the install.
function Write-InstallReceipt {
    param(
        [string]$Pkg,
        [string]$Channel,
        [string]$Tag,
        [string]$SourceRepo,
        [string]$Sha
    )
    $dir = Join-Path $HOME '.simplemotion\install-receipt'
    try {
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    } catch {
        Write-Host "  [!] could not create $dir — receipt skipped" -ForegroundColor DarkGray
        return
    }
    $file = Join-Path $dir "$Pkg.toml"
    $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $body = @"
schema       = 1
package      = "$Pkg"
channel      = "$Channel"
tag          = "$Tag"
source_repo  = "$SourceRepo"
asset_sha256 = "$Sha"
installed_at = "$ts"
installer    = "sm-install.ps1"
"@
    try {
        Set-Content -Path $file -Value $body -Encoding UTF8
    } catch {
        Write-Host "  [!] could not write $file — receipt skipped" -ForegroundColor DarkGray
    }
}

function Install-Binary {
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
    $dest = Join-Path $InstallDir "$Package.exe"
    Move-Item -Path $tmpBin -Destination $dest -Force
    Write-InstallReceipt -Pkg $Package -Channel $Channel -Tag $Version -SourceRepo $SourceRepo -Sha $actual
    Write-Host ("  [v] {0} Installed {1} to {2}" -f (Format-Step 5), $Package, $dest) -ForegroundColor Green

    $pathDirs = $env:PATH -split ';'
    if ($pathDirs -notcontains $InstallDir) {
        Write-Host "  [!] $InstallDir is not on `$env:PATH — add it to your profile to run $Package directly" -ForegroundColor DarkGray
    }
    return $dest
}

switch ($Mode) {
    'install' {
        Install-Binary | Out-Null
    }
    'run' {
        try {
            & $tmpBin @BinArgs
        } finally {
            Remove-Item $tmpBin -ErrorAction SilentlyContinue
        }
    }
    'install-and-run' {
        $installed = Install-Binary
        & $installed @BinArgs
    }
}
