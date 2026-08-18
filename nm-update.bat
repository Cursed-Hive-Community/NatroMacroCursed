@echo off
:: Update Natro Macro IN PLACE - same folder, same name.
:: Just double-click this file.
::
:: Command line options:
::   nm-update.bat -KeepLocal    re-apply your local changes after the update
::   nm-update.bat -NoRestart    do not restart the macro
::   nm-update.bat -Clean        also drop untracked files (settings\ is kept)
::   nm-update.bat -Branch main  force a specific branch
::   nm-update.bat -RepoUrl <url>  repoint origin before updating
::
:: See UPDATE-GIT.md for the whole workflow.
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\nm-git-update.ps1" %*
endlocal
