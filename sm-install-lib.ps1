# SimpleMotion install-toolchain library (Windows).
#
# Pure function definitions, no top-level code. Sourced by:
#   - sm-install.ps1     (the generic SimpleMotion binary installer)
#   - sm-welcome.ps1     (the onboarding bootstrap)
#   - sm-simplicity.ps1  (thin sm-install.ps1 wrapper)
#
# Usage:
#   $lib = (New-Object Net.WebClient).DownloadString('https://install.simplemotion.com/sm-install-lib.ps1')
#   Invoke-Expression $lib
#
# Callers must load this lib BEFORE checking $PSVersionTable (see
# Invoke-Pwsh7Guard below) - downloading via WebClient + Invoke-Expression
# works fine under stock Windows PowerShell 5.1, same as every other use
# of this lib.
#
# Functions:
#   Invoke-Pwsh7Guard     No-ops on pwsh 6+. On Windows PowerShell 5.1,
#                         locates (or installs a portable copy of) pwsh 7
#                         into ~/.local/bin, then relaunches the calling
#                         script under it and exits. Must stay ASCII
#                         (PS parses the whole file before running it, so
#                         non-ASCII anywhere in this lib would abort 5.1
#                         before the guard even runs).
#   Confirm-Section       Section-gated Y/n prompt with framed header.
#                         SM_WELCOME_ASSUME_YES=1 bypasses the prompt.
#   Get-GitHubApiHeaders  api.github.com headers, authenticated when
#                         GH_TOKEN/GITHUB_TOKEN is set.
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
#                         else (100%-local toolchain rule - system-wide
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

function Invoke-Pwsh7Guard {
    param(
        [Parameter(Mandatory=$true)] [string]$ScriptUrl,
        [string]$ScriptPath = $null,
        $BoundParameters = $null
    )
    if ($PSVersionTable.PSVersion.Major -ge 6) { return }

    $pwsh = Join-Path $HOME '.local\bin\pwsh-7\pwsh.exe'
    if (-not (Test-Path $pwsh)) {
        $found = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $pwsh = $found.Source }
    }
    if (-not (Test-Path $pwsh)) {
        Write-Host "  [*] Installing PowerShell 7 (portable) to run the installer..."
        $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
        $rel = $null   # manual retry (PS 5.1 has no -MaximumRetryCount) for transient blips
        for ($try = 1; $try -le 3; $try++) {
            try { $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' -UseBasicParsing -Headers (Get-GitHubApiHeaders); break }
            catch { if ($try -eq 3) { throw }; Start-Sleep -Seconds (2 * $try) }
        }
        $ver = $rel.tag_name.TrimStart('v')
        $asset = $rel.assets | Where-Object { $_.name -eq "PowerShell-$ver-win-$arch.zip" } | Select-Object -First 1
        if (-not $asset) { Write-Host "  [x] No PowerShell 7 release asset for win-$arch." -ForegroundColor Red; exit 1 }
        $zip = Join-Path $env:TEMP ("pwsh-{0}.zip" -f ([Guid]::NewGuid().ToString('N')))
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing
        if (-not (Confirm-AssetDigest $zip $asset)) {
            Remove-Item $zip -Force -ErrorAction SilentlyContinue
            Write-Host "  [x] PowerShell 7 SHA256 mismatch." -ForegroundColor Red
            exit 1
        }
        $pwshDir = Join-Path $HOME '.local\bin\pwsh-7'
        Remove-TreeForcefully $pwshDir
        New-Item -ItemType Directory -Path $pwshDir -Force | Out-Null
        Expand-Archive -Path $zip -DestinationPath $pwshDir -Force
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        $pwsh = Join-Path $pwshDir 'pwsh.exe'
    }

    Write-Host "  [*] Relaunching under PowerShell 7..."
    if ($BoundParameters -and $BoundParameters.Count -gt 0) {
        # Re-run the calling script under pwsh 7, forwarding its parameters.
        # Use the on-disk file if invoked from one; otherwise (iex of a
        # download) materialize it to a temp file first.
        $self = $ScriptPath
        if (-not $self) {
            $self = Join-Path $env:TEMP ("sm-install-{0}.ps1" -f ([Guid]::NewGuid().ToString('N')))
            (New-Object Net.WebClient).DownloadString($ScriptUrl) | Set-Content -LiteralPath $self -Encoding UTF8
        }
        $fwd = @()
        foreach ($k in $BoundParameters.Keys) {
            $val = $BoundParameters[$k]
            if ($val -is [System.Management.Automation.SwitchParameter] -or $val -is [bool]) {
                if ($val) { $fwd += "-$k" }
            } elseif ($val -is [System.Array]) {
                foreach ($item in $val) { $fwd += "-$k"; $fwd += [string]$item }
            } else {
                $fwd += "-$k"; $fwd += [string]$val
            }
        }
        & $pwsh -NoProfile -File $self @fwd
    } else {
        & $pwsh -NoProfile -Command "irm $ScriptUrl | iex"
    }
    exit $LASTEXITCODE
}

# ── One output format for the whole toolchain (PowerShell side) ────────
# The Bash twin of every function below lives in sm-install-lib.sh, and
# tests/render-parity.sh renders the same cases through both and fails on
# any byte of difference. That test is the contract; this is one of its two
# implementations, and neither is allowed to be the authority.
#
# It exists because the two sides HAD diverged and nothing noticed:
# Confirm-Section drew `-- Title ---` on a width-56 formula in ASCII while
# sm_phase drew `── Title ───` on width 36 in box-drawing. 62 columns
# against 42, for two days, in the same product.
#
# Everything writes through Write-SmRaw so newlines are exactly LF, the
# same bytes printf emits. Write-Host would go to the information stream
# and PowerShell's own newline handling would put CRLF on Windows, which is
# a difference the parity test would (correctly) reject.

$SmRuleW      = 36   # total columns of a phase rule, title included
$SmGutterBase = 6    # columns of "  [✓] " — the gutter with no counter

function Write-SmRaw([string]$Text) { [Console]::Out.Write($Text) }

function Get-SmRule([string]$Glyph, [int]$Count) {
    if ($Count -le 0) { return '' }
    return ($Glyph * $Count)
}

# Colour and cursor control are separate questions, as on the Bash side.
# NO_COLOR is honoured per no-color.org; SM_FORCE_COLOR / SM_FORCE_TTY
# override detection for pagers that do render escapes, and for the tests.
function Test-SmUseColor {
    if ($env:NO_COLOR)       { return $false }
    if ($env:SM_FORCE_COLOR) { return $true }
    return [Console]::IsOutputRedirected -eq $false
}
function Test-SmInteractive {
    if ($env:SM_FORCE_TTY) { return $true }
    return [Console]::IsOutputRedirected -eq $false
}

function Initialize-SmPalette {
    $e = [char]27
    if (Test-SmUseColor) {
        $script:C_GREEN = "$e[92m"; $script:C_YELLOW = "$e[33m"; $script:C_RED = "$e[91m"
        $script:C_CYAN  = "$e[96m"; $script:C_DIM    = "$e[2m";  $script:C_BOLD = "$e[1m"
        $script:C_OFF   = "$e[0m"
    } else {
        $script:C_GREEN = ''; $script:C_YELLOW = ''; $script:C_RED = ''
        $script:C_CYAN  = ''; $script:C_DIM = ''; $script:C_BOLD = ''; $script:C_OFF = ''
    }
    if (Test-SmInteractive) { $script:C_ERASE = "`r$e[K" } else { $script:C_ERASE = '' }
    # Box-drawing and ═ are mangled by the legacy console codepage, so the
    # encoding is set here rather than left to whatever the host inherited.
    try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }
}
Initialize-SmPalette

# Open the transcript. Screen only: 2J + H blanks the viewport and homes the
# cursor, leaving the scrollback intact.
function Write-SmBanner {
    param([Parameter(Mandatory)][string]$Mode, [string[]]$Subtitle = @())
    $title = "SimpleMotion — Development Environment $Mode"
    # Width is computed, not measured — 39 columns of fixed text plus an
    # ASCII mode word — so it cannot drift with how a runtime counts the
    # em dash. Same constant, same reason, as the Bash side.
    $width = 39 + $Mode.Length
    if (Test-SmInteractive) { Write-SmRaw "$([char]27)[2J$([char]27)[H" }
    Write-SmRaw "`n  $($script:C_BOLD)$title$($script:C_OFF)`n"
    Write-SmRaw "  $($script:C_DIM)$(Get-SmRule '═' $width)$($script:C_OFF)`n"
    foreach ($line in $Subtitle) {
        Write-SmRaw "  $($script:C_DIM)$line$($script:C_OFF)`n"
    }
}

function Write-SmPhase([string]$Title) {
    $pad  = $SmRuleW - $Title.Length
    $rule = ''
    if ($pad -gt 0) { $rule = " $($script:C_DIM)$(Get-SmRule '─' $pad)$($script:C_OFF)" }
    Write-SmRaw "`n  $($script:C_DIM)──$($script:C_OFF) $($script:C_BOLD)$Title$($script:C_OFF)$rule`n"
}

# The step cursor, seeded from the environment so a nested invocation
# continues the caller's count instead of restarting at 1.
$script:SmStepN     = if ($env:SM_WELCOME_STEPS_OFFSET) { [int]$env:SM_WELCOME_STEPS_OFFSET } else { 0 }
$script:SmStepTotal = if ($env:SM_WELCOME_STEPS_TOTAL)  { [int]$env:SM_WELCOME_STEPS_TOTAL }  else { 0 }

function Set-SmStepPosition([int]$N, [int]$Total) {
    $script:SmStepN = $N; $script:SmStepTotal = $Total
}

function Get-SmCounterOf([int]$N, [int]$Total) {
    return ('{0}[{1:d2}/{2:d2}]{3} ' -f $script:C_DIM, $N, $Total, $script:C_OFF)
}
function Get-SmCounter {
    if ($script:SmStepTotal -eq 0) { return '' }
    return (Get-SmCounterOf $script:SmStepN $script:SmStepTotal)
}

# Measured off the counter's own output rather than re-derived from its
# format, so a wider total cannot silently break the alignment.
function Get-SmGutter {
    $c = Get-SmCounter
    if (-not $c) { return $SmGutterBase }
    return $SmGutterBase + $c.Length - $script:C_DIM.Length - $script:C_OFF.Length
}

function Write-SmStep([string]$Glyph, [string]$Colour, [string]$Message) {
    $script:SmStepN++
    Write-SmRaw "$($script:C_ERASE)  [$Colour$Glyph$($script:C_OFF)] $(Get-SmCounter)$Message`n"
}
function Write-SmOk    ([string]$Message) { Write-SmStep '✓' $script:C_GREEN  $Message }
function Write-SmWarn  ([string]$Message) { Write-SmStep '!' $script:C_YELLOW $Message }
function Write-SmFail  ([string]$Message) { Write-SmStep '✗' $script:C_RED    $Message }
function Write-SmAct   ([string]$Message) { Write-SmStep '>' $script:C_CYAN   $Message }
function Write-SmSkip  ([string]$Message) { Write-SmStep '-' $script:C_DIM    $Message }

# An in-progress line carrying the number it is ABOUT to take. Does not
# advance the cursor — the outcome line that replaces it does that.
function Write-SmWorking([string]$Message) {
    $script:SmStepN++
    $c = Get-SmCounter
    $script:SmStepN--
    $nl = if (Test-SmInteractive) { '' } else { "`n" }
    Write-SmRaw "  [$($script:C_CYAN)*$($script:C_OFF)] $c$Message$nl"
}

function Write-SmNote([string]$Message) {
    Write-SmRaw "$(' ' * (Get-SmGutter))$($script:C_DIM)$Message$($script:C_OFF)`n"
}

# Abbreviate the home directory so a path fits the line instead of wrapping
# to column 0 and taking the gutter with it.
function Get-SmTilde([string]$Path) {
    # $env:HOME first, because that is what the Bash side reads and the
    # parity test overrides it. UserProfile is the Windows fallback, where
    # HOME is usually unset.
    $home_ = if ($env:HOME) { $env:HOME } else { [Environment]::GetFolderPath('UserProfile') }
    if ($home_ -and $Path.StartsWith($home_)) { return '~' + $Path.Substring($home_.Length) }
    return $Path
}

function Confirm-Section($title) {
    # The rule is Write-SmPhase's, so a phase opened here and one opened by
    # the Bash side are the same object drawn by one formula. This function
    # used to draw its own, and drew a different one.
    Write-SmPhase $title
    # Auto-proceed by default — matches sm-welcome v0.1.10 dropping its
    # per-step Proceed gate. SM_WELCOME_CONFIRM=1 restores the prompt;
    # SM_WELCOME_ASSUME_YES=1 (the old non-interactive override) still
    # wins over it for existing CI/scripted callers.
    if ($env:SM_WELCOME_ASSUME_YES -or -not $env:SM_WELCOME_CONFIRM) {
        return
    }
    $resp = Read-Host "  Proceed? [Y/n]"
    $resp = if ($resp) { $resp.Trim().ToLower() } else { '' }
    if ($resp -notin @('', 'y', 'yes')) {
        Write-Host "  [!] Aborted by user." -ForegroundColor Yellow
        exit 1
    }
}

# Headers for api.github.com: authenticate when GH_TOKEN/GITHUB_TOKEN is set,
# lifting the 60/hr unauthenticated rate limit on shared CI / corporate-NAT IPs.
function Get-GitHubApiHeaders {
    $h = @{ 'X-GitHub-Api-Version' = '2022-11-28' }
    $tok = if ($env:GH_TOKEN) { $env:GH_TOKEN } elseif ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } else { $null }
    if ($tok) { $h['Authorization'] = "Bearer $tok" }
    return $h
}

function Get-LatestRelease($repo) {
    try {
        return Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -UseBasicParsing -Headers (Get-GitHubApiHeaders) -MaximumRetryCount 3 -RetryIntervalSec 2
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
