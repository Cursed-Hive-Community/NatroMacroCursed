<#
  nm-git-adopt.ps1 - Turn an existing Natro Macro folder into a git repository,
  in place, without re-downloading anything and without touching settings\.

  Once adopted, the folder updates through nm-update.bat and keeps its name for
  good.

  Examples:
      # adopt a folder that came from a .zip release
      powershell -ExecutionPolicy Bypass -File tools\nm-git-adopt.ps1 -Target "C:\Natro\Natro Macro v1.0.1"

      # adopt the folder this script lives in
      powershell -ExecutionPolicy Bypass -File tools\nm-git-adopt.ps1

  See UPDATE-GIT.md for the whole workflow.
#>
[CmdletBinding()]
param(
  [string] $Target,
  [string] $RepoUrl = 'https://github.com/Cursed-Hive-Community/NatroMacroCursed.git',
  [string] $Branch = 'main',
  [switch] $Yes
)

. (Join-Path $PSScriptRoot 'nm-common.ps1')
Set-NmQuiet ([bool] $Yes)

trap {
  Write-Host ''
  Write-NmFail "Unexpected error: $($_.Exception.Message)"
  Write-Host ''
  Wait-NmKey
  exit 1
}

if (-not $Target) { $Target = Split-Path -Parent $PSScriptRoot }
$Target = (Resolve-Path -LiteralPath $Target).Path

Write-Host ''
Write-Host '  Natro Macro - adopt an existing folder into git' -ForegroundColor Magenta
Write-Host "  Target: $Target" -ForegroundColor DarkGray
Write-Host ''

Assert-NmGitInstalled
Set-NmRepo $Target

if (-not (Test-NmMacroFolder $Target)) {
  Stop-NmWithError 'This folder does not look like a Natro Macro install (submacros\natro_macro.ahk is missing).'
}

if (Test-Path (Join-Path $Target '.git')) {
  Write-NmInfo 'This folder is already a git repository - nothing to do.'
  Write-NmInfo 'Use nm-update.bat to update it.'
  Write-Host ''
  Wait-NmKey
  exit 0
}

# Running .exe files are locked by Windows, and AutoHotkey32.exe is tracked by
# the repository, so the checkout below would fail.
Write-NmStep 'Stopping instances of this folder'
Stop-NmMacroProcess $Target

$hasSettings = Test-Path (Join-Path $Target 'settings')
if ($hasSettings) {
  # settings\* is listed in .gitignore, so git never touches it.
  # https://git-scm.com/docs/gitignore
  Write-NmInfo 'settings\ found - it will be kept as is (git-ignored).'
}

Write-NmStep 'Initialising the repository'
$init = Invoke-NmGitRaw init --initial-branch=$Branch
if ($init.Code -ne 0) {
  # --initial-branch needs git 2.28 or newer.
  # https://git-scm.com/docs/git-init
  $init = Invoke-NmGitRaw init
  if ($init.Code -ne 0) { Stop-NmWithError ("git init failed.`n" + (Get-NmText $init.Output)) }
}
Write-NmInfo 'Repository initialised.'

Write-NmStep "Adding remote: $RepoUrl"
Invoke-NmGitRaw remote remove origin | Out-Null
$remote = Invoke-NmGitRaw remote add origin $RepoUrl
if ($remote.Code -ne 0) { Stop-NmWithError ("Could not add the origin remote.`n" + (Get-NmText $remote.Output)) }

Write-NmStep "Downloading branch '$Branch' (one time only)"
$fetch = Invoke-NmGitRaw fetch --progress origin $Branch
if ($fetch.Code -ne 0) {
  Stop-NmWithError ("Could not fetch '$Branch' from $RepoUrl.`n" + (Get-NmText $fetch.Output))
}
Write-NmInfo 'Branch downloaded.'

Write-NmStep 'Aligning the folder with the remote version'
# -f overwrites the existing files that belong to the repository. Files the
# repository does not know about (settings\, MMScreenshots\, ...) are kept.
# https://git-scm.com/docs/git-checkout
$checkout = Invoke-NmGitRaw checkout -f -B $Branch "origin/$Branch"
if ($checkout.Code -ne 0) {
  Stop-NmWithError ("Checkout failed - a file is most likely still locked.`n" + (Get-NmText $checkout.Output))
}

Invoke-NmGitRaw branch --set-upstream-to "origin/$Branch" $Branch | Out-Null

Write-Host ''
Write-NmInfo 'Adoption complete.'
Write-Host ''
Write-Host "  This folder now keeps its name for good: $Target" -ForegroundColor Green
Write-Host '  Future updates: double-click nm-update.bat' -ForegroundColor Green
if ($hasSettings) { Write-Host '  Your settings\ folder was preserved.' -ForegroundColor Green }
Write-Host ''

Wait-NmKey
exit 0
