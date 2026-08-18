<#
  nm-update-all.ps1 - Update every Natro Macro instance under a parent folder.

  Each instance keeps its own folder, its own name and its own settings; only
  the files that changed are rewritten.

  Examples:
      tools\nm-update-all.ps1                    # sibling folders
      tools\nm-update-all.ps1 -Root "C:\Natro"   # explicit parent folder
      tools\nm-update-all.ps1 -Restart           # restart each macro afterwards

  See UPDATE-GIT.md for the whole workflow.
#>
[CmdletBinding()]
param(
  [string] $Root,
  [switch] $Restart,
  [switch] $KeepLocal,
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

$macroFolder = Split-Path -Parent $PSScriptRoot
if (-not $Root) { $Root = Split-Path -Parent $macroFolder }
$Root = (Resolve-Path -LiteralPath $Root).Path

Write-Host ''
Write-Host '  Natro Macro - update every instance' -ForegroundColor Magenta
Write-Host "  Parent folder: $Root" -ForegroundColor DarkGray
Write-Host ''

$instances = @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
  Where-Object {
    (Test-NmMacroFolder $_.FullName) -and (Test-Path (Join-Path $_.FullName '.git'))
  })

if ($instances.Count -eq 0) {
  Write-NmWarn "No git-managed instance found under $Root"
  Write-NmWarn 'Convert your folders with tools\nm-git-adopt.ps1 -Target "<folder>"'
  Write-Host ''
  Wait-NmKey
  exit 0
}

Write-Host "  $($instances.Count) instance(s): $(($instances | ForEach-Object { $_.Name }) -join ', ')" -ForegroundColor DarkGray
Write-Host ''

$results = @()
foreach ($instance in $instances) {
  Write-Host ('-' * 70) -ForegroundColor DarkGray
  Write-NmStep "Instance: $($instance.Name)"

  # Each instance runs its own copy of the updater, so an instance pinned to an
  # older revision keeps the updater it shipped with.
  $updater = Join-Path $instance.FullName 'tools\nm-git-update.ps1'
  if (-not (Test-Path $updater)) {
    Write-NmWarn 'Skipped: tools\nm-git-update.ps1 is missing (instance not migrated yet).'
    $results += [pscustomobject] @{ Instance = $instance.Name; Result = 'skipped' }
    continue
  }

  $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $updater, '-Yes')
  if (-not $Restart) { $arguments += '-NoRestart' }
  if ($KeepLocal) { $arguments += '-KeepLocal' }

  $process = Start-Process -FilePath 'powershell' -ArgumentList $arguments -NoNewWindow -Wait -PassThru
  if ($process.ExitCode -eq 0) {
    $results += [pscustomobject] @{ Instance = $instance.Name; Result = 'ok' }
  } else {
    $results += [pscustomobject] @{ Instance = $instance.Name; Result = "failed (code $($process.ExitCode))" }
  }
}

Write-Host ''
Write-Host ('=' * 70) -ForegroundColor DarkGray
Write-Host '  Summary' -ForegroundColor Magenta
foreach ($result in $results) {
  $colour = 'Yellow'
  if ($result.Result -eq 'ok') { $colour = 'Green' }
  Write-Host ("    {0,-30} {1}" -f $result.Instance, $result.Result) -ForegroundColor $colour
}
Write-Host ''

Wait-NmKey
exit 0
