# SimpleMotion install-toolchain library (Windows).
#
# Pure function definitions, no top-level code. Sourced by:
#   - sm-install.ps1   (the generic SimpleMotion binary installer)
#   - sm-welcome.ps1   (the onboarding bootstrap)
#
# Usage:
#   $lib = (New-Object Net.WebClient).DownloadString('https://install.simplemotion.com/sm-install-lib.ps1')
#   Invoke-Expression $lib
#
# Functions:
#   Confirm-Section       Section-gated Y/n prompt with framed header.
#                         SM_WELCOME_ASSUME_YES=1 bypasses the prompt.
#   Get-LatestRelease     Invoke /releases/latest on a GitHub repo and
#                         return the parsed JSON (or $null on failure).
#   Confirm-AssetDigest   SHA256-verify a downloaded file against the
#                         `digest` field the GitHub API publishes for
#                         the matching asset.
#   Remove-TreeForcefully Wipe a Windows tree even when read-only flags
#                         (PortableGit, antivirus locks) defeat
#                         Remove-Item -Force. Shells to `cmd /c rmdir
#                         /s /q` first, then a clear-attributes + retry
#                         fallback.
#   Find-Cosign           Probe ~/.local/bin/cosign.exe and nothing
#                         else (100%-local toolchain rule — system-wide
#                         cosigns are deliberately ignored).
#   Install-Cosign        Download cosign-windows-amd64.exe from
#                         sigstore/cosign /releases/latest, SHA256-
#                         verify against the API digest, install to
#                         ~/.local/bin/cosign.exe. cosign doesn't ship
#                         a Windows-arm64 build; Windows-on-ARM emulates
#                         amd64 transparently for a one-shot verify.
#   Initialize-CosignTuf  `cosign initialize` against tuf-repo.github.com
#                         so cosign can verify GitHub-issued attestations
#                         natively. Cache lands in $env:TUF_ROOT
#                         (~/.simplemotion/sigstore by default).

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

function Get-LatestRelease($repo) {
    try {
        return Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -UseBasicParsing
    } catch {
        Write-Host ("  [!] release lookup failed for {0}: {1}" -f $repo, $_.Exception.Message) -ForegroundColor Yellow
        return $null
    }
}

function Confirm-AssetDigest($file, $asset) {
    $expected = ($asset.digest -replace '^sha256:', '').ToLower()
    if (-not $expected) { return $false }
    $actual = (Get-FileHash -Path $file -Algorithm SHA256).Hash.ToLower()
    return ($expected -eq $actual)
}

function Remove-TreeForcefully($path) {
    if (-not (Test-Path $path)) { return }
    cmd /c "rmdir /s /q `"$path`"" 2>$null
    if (Test-Path $path) {
        Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
            ForEach-Object { try { $_.Attributes = 'Normal' } catch {} }
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Find-Cosign {
    $local = Join-Path $HOME '.local\bin\cosign.exe'
    if (Test-Path $local) { return $local }
    return $null
}

function Install-Cosign {
    $rel = Get-LatestRelease 'sigstore/cosign'
    if (-not $rel) { return $null }
    # cosign doesn't ship a Windows-arm64 binary; Windows-on-ARM runs the
    # amd64 build under Prism emulation transparently for the verify call.
    $assetName = 'cosign-windows-amd64.exe'
    $asset = $rel.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
    if (-not $asset) {
        Write-Host "  [!] cosign asset $assetName not in release" -ForegroundColor Yellow
        return $null
    }
    $localBinDir = Join-Path $HOME '.local\bin'
    $tmp = Join-Path $env:TEMP ("cosign-{0}.exe" -f ([Guid]::NewGuid().ToString('N')))
    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmp -UseBasicParsing -ErrorAction Stop
        if (-not (Confirm-AssetDigest $tmp $asset)) {
            Remove-Item $tmp -ErrorAction SilentlyContinue
            Write-Host "  [!] cosign SHA256 mismatch" -ForegroundColor Yellow
            return $null
        }
        if (-not (Test-Path $localBinDir)) { New-Item -ItemType Directory -Path $localBinDir -Force | Out-Null }
        Move-Item -Path $tmp -Destination (Join-Path $localBinDir 'cosign.exe') -Force
    } catch {
        Remove-Item $tmp -ErrorAction SilentlyContinue
        Write-Host ("  [!] cosign install failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        return $null
    }
    $exe = Join-Path $localBinDir 'cosign.exe'
    if (Test-Path $exe) { return $exe }
    return $null
}

function Initialize-CosignTuf($cosignExe) {
    if (-not $cosignExe) { return $false }
    if (-not $env:TUF_ROOT) { $env:TUF_ROOT = Join-Path $HOME '.simplemotion\sigstore' }
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
