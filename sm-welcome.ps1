# SimpleMotion onboarding bootstrap (Windows).
# Thin wrapper around sm-install.ps1 — fetches sm-welcome and execs it.
#
# Usage:
#   irm https://install.simplemotion.com/sm-welcome.ps1 | iex
#   $env:SM_CHANNEL='preview'; irm https://install.simplemotion.com/sm-welcome.ps1 | iex
#
# Fast path: if %USERPROFILE%\.simplemotion\bin\sm-welcome.exe already
# exists, the script consults the GitHub Releases API for the latest
# tag on the selected channel:
#   - match    → invoke the local binary directly (no download)
#   - mismatch → invoke `sm-welcome update`, then the refreshed local
#                binary (recursion broken by
#                $env:SM_WELCOME_SKIP_FAST_PATH=1 on the update child)
#   - missing  → fall through to the sm-install.ps1 download flow

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "  SimpleMotion — Development Environment Onboarding"
Write-Host "  ══════════════════════════════════════════════════"
Write-Host ""

# sm-welcome's step-counter UI accounts for the bootstrap's pre-binary
# steps via env vars the binary reads.
$env:SM_WELCOME_NO_BANNER    = '1'
$env:SM_WELCOME_STEPS_OFFSET = '5'
# Binary has 15 internal steps (00-preflight through 14-reload-shell);
# bootstrap contributes 5 silent steps. 5 + 15 = 20.
# Update if the binary's step count changes.
$env:SM_WELCOME_STEPS_TOTAL  = '20'

# Fast path: skip the sm-install.ps1 download if the persistent binary
# is already on disk at the latest tag for the selected channel.
$channel  = if ($env:SM_CHANNEL) { $env:SM_CHANNEL } else { 'release' }
$installDir = if ($env:SM_INSTALL_DIR) { $env:SM_INSTALL_DIR } else { Join-Path $HOME '.simplemotion\bin' }
$localBin = Join-Path $installDir 'sm-welcome.exe'
if (-not $env:SM_WELCOME_SKIP_FAST_PATH -and (Test-Path $localBin)) {
    # `sm-welcome -V` prints "sm-welcome X.Y.Z"; strip the program name
    # and any leading "v".
    $localVer = $null
    try {
        $verOut = (& $localBin -V 2>$null) -join ''
        if ($verOut -match '^\s*sm-welcome\s+v?(\S+)') { $localVer = $matches[1] }
    } catch { $localVer = $null }

    # Resolve latest tag on the selected channel via the channel's
    # GitHub Releases API. Each channel repo has its own releases/latest.
    $channelRepo = $null
    switch ($channel) {
        'release' { $channelRepo = 'simplemotion/release' }
        'preview' { $channelRepo = 'simplemotion/preview' }
        'private' { $channelRepo = 'simplemotion/private' }
        'testing' { $channelRepo = 'simplemotion/testing' }
    }
    $latestVer = $null
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

    if ($localVer -and $latestVer) {
        if ($localVer -eq $latestVer) {
            Write-Host ("  [v] sm-welcome {0} already installed (channel={1}) — skipping download" -f $localVer, $channel) -ForegroundColor Green
            & $localBin
            exit $LASTEXITCODE
        } else {
            # Mismatch: fall through to the full install below. The local
            # binary's `sm-welcome update` historically defaulted to the
            # `release` channel regardless of the user's chosen one, so
            # calling it here led to cross-channel downgrades and step-name
            # mismatches on the rebooted binary. The full-install path
            # below is already channel-aware, so a plain fall-through is
            # simpler and correct. Install-receipt-driven channel pinning
            # is the follow-up that lets `sm-welcome update` stand alone.
            Write-Host ("  [^] sm-welcome {0} installed; {1} available on channel={2} — re-installing" -f $localVer, $latestVer, $channel) -ForegroundColor DarkGray
        }
    }
}

$installer = (New-Object Net.WebClient).DownloadString('https://install.simplemotion.com/sm-install.ps1')
$sb = [ScriptBlock]::Create($installer)
& $sb -Package 'sm-welcome' `
      -AssetSuffix 'short' `
      -SourceRepo '3400-0000-SM-Software/3400-0009-SM-Welcome' `
      -Channel $channel `
      -Mode 'install-and-run'
