<#
  nm-common.ps1 - Shared helpers for the Natro Macro git tooling.

  Dot-source it from any nm-*.ps1 script:

      . (Join-Path $PSScriptRoot 'nm-common.ps1')

  Targets Windows PowerShell 5.1, which ships with Windows 10.
  https://learn.microsoft.com/powershell/scripting/windows-powershell/starting-windows-powershell
#>

# git writes to stderr during normal operation (fetch/clone progress). Under
# Windows PowerShell 5.1, redirecting that stream while $ErrorActionPreference
# is 'Stop' raises a NativeCommandError and aborts the script. Every failure is
# therefore detected explicitly through git's exit code instead.
# https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_preference_variables
$ErrorActionPreference = 'Continue'

# Module state. Dot-sourcing runs this in the caller's script scope, so every
# nm-*.ps1 gets its own copy.
$script:NmRepoPath = $null
$script:NmGitExe = $null
$script:NmQuiet = $false

# ---------------------------------------------------------------------------
# Console output
# ---------------------------------------------------------------------------

function Write-NmStep { param([string] $Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-NmInfo { param([string] $Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-NmWarn { param([string] $Message) Write-Host "    $Message" -ForegroundColor Yellow }
function Write-NmFail { param([string] $Message) Write-Host "    $Message" -ForegroundColor Red }

function Wait-NmKey {
  # $NmQuiet is set by each script from its own -Yes switch, so unattended runs
  # (nm-update-all) never block on a keypress.
  param([string] $Message = 'Press any key to close . . .')

  if ($script:NmQuiet) { return }
  Write-Host $Message -ForegroundColor DarkGray
  try { [void][System.Console]::ReadKey($true) } catch { Start-Sleep -Seconds 3 }
}

function Stop-NmWithError {
  param([string] $Message)

  Write-Host ''
  Write-NmFail $Message
  Write-Host ''
  Wait-NmKey
  exit 1
}

function Set-NmQuiet {
  param([bool] $Quiet)
  $script:NmQuiet = $Quiet
}

# ---------------------------------------------------------------------------
# git access
# ---------------------------------------------------------------------------

function Initialize-NmGit {
  # Resolves the git executable once. -CommandType Application matters: without
  # it, Get-Command would resolve an alias or function named 'git' before the
  # real executable.
  # https://learn.microsoft.com/powershell/module/microsoft.powershell.core/get-command
  $command = Get-Command git -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1

  if (-not $command) { return $false }

  $script:NmGitExe = $command.Source
  return $true
}

function Set-NmRepo {
  # Sets the repository every later git call runs against ('git -C <path>').
  # Pass an empty path for repository-less commands such as 'git clone'.
  param([string] $Path)
  $script:NmRepoPath = $Path
}

function Get-NmGitVersion {
  return (Get-NmText (& $script:NmGitExe --version))
}

function Invoke-NmGitRaw {
  # Runs git and returns [pscustomobject] @{ Output = <string[]>; Code = <int> }.
  #
  # This is deliberately a *simple* function: an advanced one (any [Parameter]
  # attribute) would try to bind native-style tokens such as -m, -fd or --hard
  # as its own parameter names and fail. With $args every token is forwarded
  # untouched.
  # https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_functions_advanced_parameters
  $gitArgs = @()
  if ($script:NmRepoPath) { $gitArgs += @('-C', $script:NmRepoPath) }
  $gitArgs += $args

  $output = & $script:NmGitExe @gitArgs 2>&1
  $code = $LASTEXITCODE

  # @($null) is an array holding one null element, so empty git output (a clean
  # repository, for instance) would otherwise be counted as a single line.
  # https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_arrays
  $lines = @()
  if ($null -ne $output) { $lines = @($output | Where-Object { $null -ne $_ }) }

  return [pscustomobject] @{ Output = $lines; Code = $code }
}

function Invoke-NmGit {
  # Same as Invoke-NmGitRaw but throws when git fails.
  $called = $args
  $result = Invoke-NmGitRaw @args

  if ($result.Code -ne 0) {
    throw ("git " + ($called -join ' ') + " failed with code $($result.Code):`n" + (Get-NmText $result.Output))
  }

  return $result.Output
}

function Invoke-NmGitSafe {
  # Same as Invoke-NmGitRaw but returns $null when git fails.
  $result = Invoke-NmGitRaw @args
  if ($result.Code -ne 0) { return $null }
  return $result.Output
}

function Get-NmText {
  # Flattens git output into a single trimmed string.
  param($Value)

  if ($null -eq $Value) { return '' }
  return (($Value | ForEach-Object { "$_" }) -join "`n").Trim()
}

# ---------------------------------------------------------------------------
# Macro folders and processes
# ---------------------------------------------------------------------------

function Test-NmMacroFolder {
  param([string] $Path)
  return (Test-Path (Join-Path $Path 'submacros\natro_macro.ahk'))
}

function Get-NmFolderPrefix {
  # Path prefix ending with a separator. Without the trailing backslash,
  # 'C:\Natro\Bot1' would also match 'C:\Natro\Bot1x'.
  param([string] $Path)
  return ($Path.TrimEnd('\') + '\')
}

function Get-NmMacroProcess {
  # AutoHotkey processes started from $Path only, so updating one instance never
  # disturbs the ones running in the other Remote Desktop sessions.
  # https://learn.microsoft.com/windows/win32/cimwin32prov/win32-process
  param([string] $Path)

  $prefix = Get-NmFolderPrefix $Path

  try {
    return @(Get-CimInstance Win32_Process -Filter "Name='AutoHotkey32.exe' OR Name='AutoHotkey64.exe'" -ErrorAction SilentlyContinue |
      Where-Object {
        $_.ExecutablePath -and
        $_.ExecutablePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
      })
  } catch {
    Write-NmWarn "Could not enumerate processes: $($_.Exception.Message)"
    return @()
  }
}

function Stop-NmMacroProcess {
  param([string] $Path)

  $processes = Get-NmMacroProcess $Path
  if ($processes.Count -eq 0) {
    Write-NmInfo 'No running instance for this folder.'
    return
  }

  Write-NmInfo "Stopping $($processes.Count) process(es) from this folder only."
  foreach ($process in $processes) {
    try {
      Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
    } catch {
      Write-NmWarn "PID $($process.ProcessId) not stopped: $($_.Exception.Message)"
    }
  }

  # Windows keeps a lock on a running .exe, and AutoHotkey32.exe is tracked by
  # git, so the update would fail until every process is really gone.
  for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 250
    if ((Get-NmMacroProcess $Path).Count -eq 0) { break }
  }
}

function Start-NmMacro {
  param([string] $Path)

  $starter = Join-Path $Path 'START.bat'
  if (-not (Test-Path $starter)) {
    Write-NmWarn 'START.bat not found, start the macro manually.'
    return
  }

  Write-NmStep 'Restarting the macro'
  Start-Process -FilePath $starter -WorkingDirectory $Path
  Write-NmInfo 'Macro restarted.'
}

function Get-NmMacroVersion {
  # Reads VersionID from submacros\natro_macro.ahk, or '' when unavailable.
  param([string] $Path)

  $match = Select-String -Path (Join-Path $Path 'submacros\natro_macro.ahk') `
    -Pattern '^VersionID\s*:=\s*"([^"]+)"' -ErrorAction SilentlyContinue |
    Select-Object -First 1

  if (-not $match) { return '' }
  return $match.Matches[0].Groups[1].Value
}

function Assert-NmGitInstalled {
  if (Initialize-NmGit) { return }

  Stop-NmWithError @'
git is not installed, or not on PATH.

Install it, then open a new window:
    winget install --id Git.Git -e

Or download it from https://git-scm.com/download/win
'@
}
