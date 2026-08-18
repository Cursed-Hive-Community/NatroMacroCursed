<#
  nm-git-update.ps1 - Update Natro Macro in place, using git.

  The stock updater (submacros\update.bat) downloads a .zip and extracts it into
  a NEW folder whose name carries the version number. This script instead:
    - keeps the folder and its name untouched
    - rewrites only the files that actually changed
    - preserves settings\, MMScreenshots\ and logs (all git-ignored)
    - stops only the instances started from THIS folder
    - restarts the macro when done

  Usage, from the macro folder:
      nm-update.bat                 standard update
      nm-update.bat -KeepLocal      re-apply your local changes afterwards
      nm-update.bat -NoRestart      do not restart the macro
      nm-update.bat -Clean          also drop untracked files (settings\ kept)
      nm-update.bat -Branch main    force a specific branch

  See UPDATE-GIT.md for the whole workflow.
#>
[CmdletBinding()]
param(
  [string] $Branch,
  [switch] $KeepLocal,
  [switch] $NoRestart,
  [switch] $Clean,
  [switch] $Yes
)

. (Join-Path $PSScriptRoot 'nm-common.ps1')
Set-NmQuiet ([bool] $Yes)

# Safety net: without it an unexpected error would close the window instantly
# and the user would never see the message.
trap {
  Write-Host ''
  Write-NmFail "Unexpected error: $($_.Exception.Message)"
  Write-Host ''
  Wait-NmKey
  exit 1
}

# ---------------------------------------------------------------------------
# Locate the macro folder (this script lives in <macro>\tools\)
# ---------------------------------------------------------------------------
$Root = Split-Path -Parent $PSScriptRoot
if (-not (Test-NmMacroFolder $Root)) {
  Stop-NmWithError "This script must sit in <Natro Macro folder>\tools\. Resolved folder: $Root"
}

Write-Host ''
Write-Host '  Natro Macro - in-place update (git)' -ForegroundColor Magenta
Write-Host "  Folder: $Root" -ForegroundColor DarkGray
Write-Host ''

# ---------------------------------------------------------------------------
# 1. Requirements
# ---------------------------------------------------------------------------
Write-NmStep 'Checking git'
Assert-NmGitInstalled
Set-NmRepo $Root
Write-NmInfo (Get-NmGitVersion)

if (-not (Test-Path (Join-Path $Root '.git'))) {
  Stop-NmWithError @"
This folder is not a git repository: $Root

To convert it in place (nothing re-downloaded, settings\ kept):
    powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\nm-git-adopt.ps1"
"@
}

# ---------------------------------------------------------------------------
# 2. Work out which remote ref to follow
# ---------------------------------------------------------------------------
Write-NmStep 'Resolving the branch to track'
$detached = (Get-NmText (Invoke-NmGitSafe rev-parse --abbrev-ref HEAD)) -eq 'HEAD'

if ($Branch) {
  $remoteRef = "origin/$Branch"
} else {
  $upstream = Get-NmText (Invoke-NmGitSafe rev-parse --abbrev-ref --symbolic-full-name '@{u}')
  if ($upstream) {
    $remoteRef = $upstream
  } else {
    # Detached HEAD (worktree) or branch without upstream: fall back to the
    # default branch advertised by origin.
    $originHead = Get-NmText (Invoke-NmGitSafe symbolic-ref --short refs/remotes/origin/HEAD)
    if ($originHead) { $remoteRef = $originHead } else { $remoteRef = 'origin/main' }
  }
}
Write-NmInfo "Remote ref: $remoteRef"

$remoteName = $remoteRef.Split('/')[0]
$branchName = $remoteRef.Substring($remoteName.Length + 1)

# ---------------------------------------------------------------------------
# 3. Fetch
# ---------------------------------------------------------------------------
Write-NmStep "Fetching from $remoteName"
$fetch = Invoke-NmGitRaw fetch --prune $remoteName
if ($fetch.Code -ne 0) {
  Stop-NmWithError ("Could not reach the remote repository.`n" + (Get-NmText $fetch.Output))
}
Write-NmInfo 'Remote queried.'

$localSha = Get-NmText (Invoke-NmGit rev-parse HEAD)
$remoteSha = Get-NmText (Invoke-NmGitSafe rev-parse $remoteRef)

if (-not $remoteSha) {
  Stop-NmWithError ("Remote branch '$remoteRef' not found.`nAvailable branches:`n" +
    (Get-NmText (Invoke-NmGitSafe branch -r)))
}

if ($localSha -eq $remoteSha) {
  Write-Host ''
  Write-NmInfo "Already up to date ($($localSha.Substring(0, 7)) - $branchName)."
  Write-Host ''
  if (-not $NoRestart) { Start-NmMacro $Root }
  Wait-NmKey
  exit 0
}

# ---------------------------------------------------------------------------
# 4. Preview
# ---------------------------------------------------------------------------
Write-NmStep 'Incoming changes'
$changed = @(Invoke-NmGitSafe diff --name-status "$localSha..$remoteSha")
Write-Host "    $($changed.Count) file(s) changed:" -ForegroundColor DarkGray
$changed | Select-Object -First 25 | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
if ($changed.Count -gt 25) {
  Write-Host "      ... and $($changed.Count - 25) more" -ForegroundColor DarkGray
}

$commits = @(Invoke-NmGitSafe log --oneline --no-merges "$localSha..$remoteSha")
if ($commits.Count -gt 0) {
  Write-Host "    $($commits.Count) new commit(s):" -ForegroundColor DarkGray
  $commits | Select-Object -First 10 | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
}
Write-Host ''

# ---------------------------------------------------------------------------
# 5. Stop the macro
# ---------------------------------------------------------------------------
Write-NmStep 'Stopping the macro'
Stop-NmMacroProcess $Root

# ---------------------------------------------------------------------------
# 6. Park local changes
# ---------------------------------------------------------------------------
$stashed = $false
$dirty = @(Invoke-NmGitSafe status --porcelain)
if ($dirty.Count -gt 0) {
  Write-NmStep 'Local changes detected'
  $dirty | Select-Object -First 15 | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }

  $label = "nm-update $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
  $stash = Invoke-NmGitRaw stash push -m $label
  if ($stash.Code -eq 0) {
    $stashed = $true
    Write-NmInfo "Stashed as `"$label`""
    Write-NmWarn 'Recover them with:  git stash list  then  git stash pop'
  } else {
    Write-NmWarn 'Could not stash; local changes are about to be overwritten.'
  }
}

# ---------------------------------------------------------------------------
# 7. Apply
# ---------------------------------------------------------------------------
Write-NmStep "Applying $($remoteSha.Substring(0, 7))"

$applied = $false
for ($attempt = 1; $attempt -le 3; $attempt++) {
  # https://git-scm.com/docs/git-reset
  if ($detached) {
    $result = Invoke-NmGitRaw checkout --force --detach $remoteSha
  } else {
    $result = Invoke-NmGitRaw reset --hard $remoteRef
  }
  if ($result.Code -eq 0) { $applied = $true; break }

  # Usually AutoHotkey32.exe still locked by Windows.
  Write-NmWarn "Attempt $attempt failed, retrying in 2 s..."
  Stop-NmMacroProcess $Root
  Start-Sleep -Seconds 2
}

if (-not $applied) {
  Stop-NmWithError @'
Update failed: some files are still locked.

Close every Natro Macro window belonging to THIS folder, check in Task Manager
that no AutoHotkey32.exe from it is left, then run nm-update.bat again.
'@
}
Write-NmInfo 'Files updated.'

if ($Clean) {
  Write-NmStep 'Removing untracked files'
  # -d covers directories; -x is deliberately omitted so settings\,
  # MMScreenshots\ and logs survive.
  # https://git-scm.com/docs/git-clean
  $removed = @(Invoke-NmGitSafe clean -fd)
  $removed | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
  Write-NmInfo 'Cleanup done (settings\ kept).'
}

if ($stashed -and $KeepLocal) {
  Write-NmStep 'Re-applying your local changes'
  $pop = Invoke-NmGitRaw stash pop
  if ($pop.Code -ne 0) {
    Write-NmWarn 'Conflict while re-applying: your changes stay in the stash.'
    Write-NmWarn 'Resolve with:  git status  then  git stash pop'
  } else {
    Write-NmInfo 'Local changes re-applied.'
  }
}

# ---------------------------------------------------------------------------
# 8. Report and restart
# ---------------------------------------------------------------------------
Write-Host ''
$version = Get-NmMacroVersion $Root
$suffix = ''
if ($version) { $suffix = " (v$version)" }

Write-Host "  Update complete$suffix - folder unchanged: $Root" -ForegroundColor Green
Write-Host ''

if (-not $NoRestart) { Start-NmMacro $Root }

Write-Host ''
Wait-NmKey
exit 0
