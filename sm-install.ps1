# SimpleMotion generic binary installer base (Windows).
#
# Resolves a SimpleMotion-published binary from a GitHub Releases-hosting
# repo, verifies SHA256 + sigstore build-provenance attestation, and
# either installs it to PATH or execs it from a temp file. Bootstraps
# `gh` into `~/.local/bin/gh.exe` if missing so attestation verification
# works on fresh machines (matches the Bash side's `ensure_gh` flow).
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
    [string[]]$BinArgs = @()
)

$ErrorActionPreference = 'Stop'

# Surface SimpleMotion bins + the gh bootstrap dir so `Get-Command` finds
# our own tools on the *first* run, before any profile-script PATH edit
# has taken effect in a new PowerShell session.
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

# Host triple.
$arch = if ([System.Environment]::Is64BitOperatingSystem) {
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'aarch64' } else { 'x86_64' }
} else {
    Write-Host "  [x] 32-bit Windows is not supported." -ForegroundColor Red
    exit 1
}
$target = "$arch-pc-windows-msvc"
$asset  = "$Package-$target.exe"

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

# Ensure a usable `gh` is on disk before attempting attestation. Mirrors
# the Bash side's `ensure_gh`: returns the path to a usable gh, or $null
# if bootstrapping failed (in which case the attestation check is skipped
# — SHA256 still anchors integrity). Runs unconditionally so the one-time
# ~10s cost lands now instead of on the next release that ships a bundle.
function Ensure-Gh {
    $cmd = Get-Command gh -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # Match the Rust sm-welcome step's location (installer.rs:60) and the
    # Bash installer (~/.local/bin/gh) so we don't fork a second canonical
    # gh path across the bootstrap.
    $ghDir = Join-Path $HOME '.local\bin'
    $localGh = Join-Path $ghDir 'gh.exe'
    Write-Host ("      [*] Bootstrapping gh (kept at {0} for future runs)..." -f $localGh) -ForegroundColor DarkGray

    # Try the live cli/cli releases API; fall back to a known-good pinned
    # version on rate-limit (anon API is 60/hr/IP). Bump the fallback
    # periodically — keep in lock-step with the Bash side's GH_PIN.
    $ghPin = 'v2.89.0'
    $ghTag = $null
    try {
        $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/cli/cli/releases/latest' -UseBasicParsing -ErrorAction Stop
        $ghTag = $rel.tag_name
    } catch { $ghTag = $null }
    if (-not $ghTag) {
        Write-Host ("      [-] cli/cli release lookup failed (rate-limited?); using pinned {0}" -f $ghPin) -ForegroundColor DarkGray
        $ghTag = $ghPin
    }
    $ghVer = $ghTag.TrimStart('v')

    $ghArch = if ($arch -eq 'aarch64') { 'arm64' } else { 'amd64' }
    $ghAsset = "gh_${ghVer}_windows_${ghArch}.zip"
    $ghUrl       = "https://github.com/cli/cli/releases/download/${ghTag}/${ghAsset}"
    $ghSumsUrl   = "https://github.com/cli/cli/releases/download/${ghTag}/gh_${ghVer}_checksums.txt"

    $tmpZip  = Join-Path $env:TEMP ("gh-bootstrap-{0}.zip" -f ([Guid]::NewGuid().ToString('N')))
    $tmpSums = "$tmpZip.sums"
    try {
        Invoke-WebRequest -Uri $ghUrl     -OutFile $tmpZip  -UseBasicParsing -ErrorAction Stop
        Invoke-WebRequest -Uri $ghSumsUrl -OutFile $tmpSums -UseBasicParsing -ErrorAction Stop
    } catch {
        Remove-Item $tmpZip, $tmpSums -ErrorAction SilentlyContinue
        Write-Host "      [-] gh bootstrap skipped (download failed)" -ForegroundColor DarkGray
        return $null
    }

    # cli/cli's checksums.txt is `<sha>  <asset>` per line.
    $expected = $null
    foreach ($line in Get-Content $tmpSums) {
        $parts = $line -split '\s+'
        if ($parts.Count -ge 2 -and $parts[1] -eq $ghAsset) { $expected = $parts[0]; break }
    }
    Remove-Item $tmpSums -ErrorAction SilentlyContinue
    $actual = (Get-FileHash -Path $tmpZip -Algorithm SHA256).Hash.ToLower()
    if (-not $expected -or $expected.ToLower() -ne $actual) {
        Remove-Item $tmpZip -ErrorAction SilentlyContinue
        Write-Host "      [-] gh bootstrap skipped (SHA256 mismatch on cli/cli asset)" -ForegroundColor DarkGray
        return $null
    }

    if (-not (Test-Path $ghDir)) { New-Item -ItemType Directory -Path $ghDir -Force | Out-Null }
    $extractDir = Join-Path $env:TEMP ("gh-extract-{0}" -f ([Guid]::NewGuid().ToString('N')))
    try {
        Expand-Archive -Path $tmpZip -DestinationPath $extractDir -Force
        $inner = Get-ChildItem -Path $extractDir -Recurse -Filter 'gh.exe' | Select-Object -First 1
        if (-not $inner) {
            Write-Host "      [-] gh bootstrap skipped (gh.exe not in archive)" -ForegroundColor DarkGray
            return $null
        }
        Copy-Item -Path $inner.FullName -Destination $localGh -Force
    } catch {
        Write-Host "      [-] gh bootstrap skipped (extraction failed)" -ForegroundColor DarkGray
        return $null
    } finally {
        Remove-Item $tmpZip -ErrorAction SilentlyContinue
        Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path $localGh) {
        Write-Host ("      [v] Installed gh {0} to {1}" -f $ghVer, $localGh) -ForegroundColor Green
        return $localGh
    }
    Write-Host "      [-] gh bootstrap skipped (extraction failed)" -ForegroundColor DarkGray
    return $null
}

# Attestation check, two paths in order of preference:
#   1. Offline bundle (`<asset>.sigstore.jsonl`) — no API, no auth.
#   2. API lookup against the source repo — needs authed gh with read
#      access (SimpleMotion staff only).
# Verification failure on path 1 is fatal; missing bundle plus unauthed /
# unreadable source repo is a skip (SHA256 still anchors integrity).
$ghBin = Ensure-Gh
if ($ghBin) {
    $bundleUrl = "$url.sigstore.jsonl"
    $tmpAtt = [System.IO.Path]::Combine($env:TEMP, "$Package-$([Guid]::NewGuid().ToString('N')).sigstore.jsonl")
    $bundleOk = $false
    try {
        Invoke-WebRequest -Uri $bundleUrl -OutFile $tmpAtt -UseBasicParsing -ErrorAction Stop
        $bundleOk = $true
    } catch { $bundleOk = $false }

    if ($bundleOk) {
        & $ghBin attestation verify $tmpBin --bundle $tmpAtt --repo $SourceRepo *> $null
        $code = $LASTEXITCODE
        Remove-Item $tmpAtt -ErrorAction SilentlyContinue
        if ($code -eq 0) {
            Write-Host ("  [v] {0} Provenance verified (offline bundle, signed by {1})" -f (Format-Step 4), $SourceRepo) -ForegroundColor Green
        } else {
            Write-Host ("  [x] {0} Provenance bundle present but failed verification (signed by {1})" -f (Format-Step 4), $SourceRepo) -ForegroundColor Red
            Remove-Item $tmpBin -ErrorAction SilentlyContinue
            exit 1
        }
    } else {
        Remove-Item $tmpAtt -ErrorAction SilentlyContinue
        & $ghBin auth status *> $null
        $authed = ($LASTEXITCODE -eq 0)
        if ($authed) {
            & $ghBin attestation verify $tmpBin --repo $SourceRepo *> $null
            if ($LASTEXITCODE -eq 0) {
                Write-Host ("  [v] {0} Provenance verified (API lookup against {1})" -f (Format-Step 4), $SourceRepo) -ForegroundColor Green
            } else {
                Write-Host ("  [-] {0} Provenance check skipped (no bundle on release; source repo unauthed or not readable)" -f (Format-Step 4)) -ForegroundColor DarkGray
            }
        } else {
            Write-Host ("  [-] {0} Provenance check skipped (no bundle on release; source repo unauthed or not readable)" -f (Format-Step 4)) -ForegroundColor DarkGray
        }
    }
} else {
    Write-Host ("  [-] {0} Provenance check skipped (gh unavailable and bootstrap failed)" -f (Format-Step 4)) -ForegroundColor DarkGray
}

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
