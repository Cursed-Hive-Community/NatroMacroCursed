@echo off
:: Update EVERY Natro Macro instance sitting in the parent folder.
:: Each instance keeps its own folder name and its own settings.
::
:: Command line options:
::   nm-update-all.bat -Restart          restart each macro after updating
::   nm-update-all.bat -Root "D:\Natro"  explicit parent folder
::
:: See UPDATE-GIT.md for the whole workflow.
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\nm-update-all.ps1" %*
endlocal
