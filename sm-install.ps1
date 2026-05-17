# SimpleMotion generic binary installer base (Windows).
#
# Resolves a SimpleMotion-published binary from a GitHub Releases-hosting
# repo, verifies SHA256 (and attestation if `gh` is authed), and either
# installs it to PATH or execs it from a temp file.
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
Write-Host ("  [v] {0} Checksum verified" -f (Format-Step 3)) -ForegroundColor Green

# Optional provenance check.
$ghAvailable = $null -ne (Get-Command gh -ErrorAction SilentlyContinue)
$ghAuthed = $false
if ($ghAvailable) {
    & gh auth status 2>$null | Out-Null
    $ghAuthed = ($LASTEXITCODE -eq 0)
}
if ($ghAuthed) {
    & gh attestation verify $tmpBin --repo $SourceRepo 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host ("  [v] {0} Provenance verified (against {1})" -f (Format-Step 4), $SourceRepo) -ForegroundColor Green
    } else {
        Write-Host ("  [-] {0} Provenance check skipped (source repo not accessible to this gh account)" -f (Format-Step 4)) -ForegroundColor DarkGray
    }
} else {
    Write-Host ("  [-] {0} Provenance check skipped (install & authenticate gh to enable)" -f (Format-Step 4)) -ForegroundColor DarkGray
}

function Install-Binary {
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
    $dest = Join-Path $InstallDir "$Package.exe"
    Move-Item -Path $tmpBin -Destination $dest -Force
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
