<#
  nm-new-instance.ps1 - Create another Natro Macro instance next to this one.

  The clone is made from the local folder: on the same drive git hard-links the
  object database, so creating an instance is near-instant and costs almost no
  extra disk space.
  https://git-scm.com/docs/git-clone#Documentation/git-clone.txt---local

  Examples:
      tools\nm-new-instance.ps1 -Name Bot2
      tools\nm-new-instance.ps1 -Name Bot2 -CopySettings
      tools\nm-new-instance.ps1 -Name Bot3 -Path "D:\Natro"

  See UPDATE-GIT.md for the whole workflow.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string] $Name,

  [string] $Path,
  [switch] $CopySettings,
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

$Source = Split-Path -Parent $PSScriptRoot
if (-not $Path) { $Path = Split-Path -Parent $Source }
$Destination = Join-Path $Path $Name

Write-Host ''
Write-Host '  Natro Macro - new instance' -ForegroundColor Magenta
Write-Host "  Source:      $Source" -ForegroundColor DarkGray
Write-Host "  Destination: $Destination" -ForegroundColor DarkGray
Write-Host ''

Assert-NmGitInstalled

if (-not (Test-Path (Join-Path $Source '.git'))) {
  Stop-NmWithError 'The source folder is not a git repository. Run tools\nm-git-adopt.ps1 first.'
}
if (Test-Path $Destination) {
  Stop-NmWithError "Folder already exists: $Destination"
}

# Real remote URL, so the new instance updates straight from GitHub instead of
# from its local source folder.
Set-NmRepo $Source
$originUrl = Get-NmText (Invoke-NmGitSafe remote get-url origin)

Write-NmStep 'Cloning locally (hard links, almost no disk cost)'
Set-NmRepo ''
$clone = Invoke-NmGitRaw clone --local $Source $Destination
if ($clone.Code -ne 0) {
  Stop-NmWithError ("Clone failed.`n" + (Get-NmText $clone.Output))
}
Write-NmInfo 'Clone created.'

if ($originUrl) {
  Write-NmStep "Pointing origin at $originUrl"
  Set-NmRepo $Destination
  Invoke-NmGitRaw remote set-url origin $originUrl | Out-Null
  Invoke-NmGitRaw fetch --prune origin | Out-Null
  Write-NmInfo 'origin now points at the remote repository.'
}

if ($CopySettings) {
  $sourceSettings = Join-Path $Source 'settings'
  if (Test-Path $sourceSettings) {
    Write-NmStep 'Copying settings'
    Copy-Item -LiteralPath $sourceSettings -Destination (Join-Path $Destination 'settings') -Recurse -Force
    Write-NmInfo 'settings\ copied - remember to adjust what must stay unique.'
  }
}

Write-Host ''
Write-NmInfo "Instance '$Name' ready: $Destination"
Write-Host '  Start it with START.bat, update it with nm-update.bat.' -ForegroundColor Green
if ($CopySettings) {
  Write-Host '  Unique per instance: Roblox account, hotkeys, Discord webhook.' -ForegroundColor Yellow
}
Write-Host ''

Wait-NmKey
exit 0
