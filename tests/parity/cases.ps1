#!/usr/bin/env pwsh
# PowerShell driver for the renderer parity test. The twin of cases.sh:
# same cases, same order, same labels. See that file's header.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../sm-install-lib.ps1')
Initialize-SmPalette

function c([string]$n) { Write-SmRaw "CASE $n`n" }
function line([string]$s) { Write-SmRaw "[$s]`n" }

c 'banner-update';   Write-SmBanner -Mode 'Update'  -Subtitle @('channel=develop · from install receipt')
c 'banner-install';  Write-SmBanner -Mode 'Install'
c 'banner-two-subs'; Write-SmBanner -Mode 'Update'  -Subtitle @('first line','second line')

c 'phase-short';     Write-SmPhase 'Install'
c 'phase-long';      Write-SmPhase 'Authenticate & Fetch'
c 'phase-exact';     Write-SmPhase (Get-SmRule 'x' 36)
c 'phase-overlong';  Write-SmPhase (Get-SmRule 'x' 60)

c 'rule-zero';       line (Get-SmRule '-' 0)
c 'rule-neg';        line (Get-SmRule '-' -3)
c 'rule-five';       line (Get-SmRule '-' 5)

c 'counter-of';      line (Get-SmCounterOf 7 18)
c 'counter-wide';    line (Get-SmCounterOf 5 120)

Set-SmStepPosition 0 0
c 'step-no-counter'; Write-SmOk 'no budget set'
c 'note-no-counter'; Write-SmNote 'detail under an unnumbered line'

Set-SmStepPosition 0 13
c 'markers';         Write-SmOk 'ok line'; Write-SmWarn 'warn line'; Write-SmFail 'fail line'
                     Write-SmAct 'act line'; Write-SmSkip 'skip line'
c 'note-counter';    Write-SmNote 'detail under a numbered line'

Set-SmStepPosition 4 13
c 'working-then-ok'; Write-SmWorking 'Downloading...'; Write-SmOk 'Downloaded'

Set-SmStepPosition 5 120
c 'note-wide';       Write-SmOk 'wide total'; Write-SmNote 'aligned under a 3-digit total'

c 'tilde-home';      line (Get-SmTilde (Join-Path $env:HOME '.local/bin/cosign'))
c 'tilde-other';     line (Get-SmTilde '/opt/thing')
c 'tilde-embedded';  line (Get-SmTilde ('/srv' + $env:HOME + '/a'))
