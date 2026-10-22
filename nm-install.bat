@echo off
:: Install the Cursed fork into THIS Natro Macro folder, in place.
::
:: Just double-click this file. Your settings are not touched: accounts,
:: hotkeys, fields, patterns and the Discord webhook all stay exactly as they
:: are, and every update after this one keeps them too.
::
:: Command line options:
::   nm-install.bat -Target "C:\Natro\Bot2"   install into another folder
::   nm-install.bat -Branch main              follow a specific branch
::   nm-install.bat -Yes                      do not ask anything
::
:: See INSTALL.md to be walked through it, or UPDATE-GIT.md for the details.
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\nm-git-adopt.ps1" %*
endlocal
