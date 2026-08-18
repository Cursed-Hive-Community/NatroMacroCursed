# In-place updates for Natro Macro

## The problem

The stock updater (`submacros/update.bat`) downloads a `.zip` of the latest
release and **extracts it into a brand new folder**, whose name carries the
version number: `Natro Macro v1.0.1`, `Natro Macro v1.1.0`, and so on. It then
copies `settings/`, `patterns/` and `paths/` across, and offers to delete the
old folder.

When several macros run in parallel, for instance one per Remote Desktop
session on the same machine, this causes three problems.

- The folder name changes with every release, so shortcuts, scheduled tasks
  and the auto-start registry entry all end up pointing at nothing.
- It becomes impossible to tell which folder belongs to which account or
  which session.
- Everything is downloaded and rewritten, including the hundreds of files
  that did not change at all.

## How it works

Each instance becomes a **git repository**. Updating then means fetching the
new commits and realigning the folder.

- The folder keeps its name, permanently.
- Only the files that actually changed are rewritten.
- `settings/`, `MMScreenshots/` and the logs are ignored by git[^gitignore],
  so they are never touched.
- You can roll back at any time, and see exactly what changed with
  `git log` and `git diff`.

## Requirements

Git for Windows[^git-download], once per machine:

```powershell
winget install --id Git.Git -e
```

Then **open a new window** so that `git` is on the `PATH`.

## Setting up

### Adopting an existing folder

This is the common case: `C:\Natro\Bot1` already runs, with its settings
configured. Nothing is re-downloaded and `settings/` is left alone.

```powershell
powershell -ExecutionPolicy Bypass `
  -File "C:\Natro\Bot1\tools\nm-git-adopt.ps1" -Target "C:\Natro\Bot1"
```

If the folder has no `tools\` directory yet, run the script from an instance
that has already been converted; it accepts any folder as `-Target`:

```powershell
powershell -ExecutionPolicy Bypass `
  -File "C:\Natro\Bot1\tools\nm-git-adopt.ps1" `
  -Target "C:\Natro\Old folder v1.0.1"
```

### Cloning from scratch

```powershell
cd C:\Natro
git clone https://github.com/Cursed-Hive-Community/NatroMacroCursed.git Bot1
xcopy /E /I "C:\Natro\Old folder v1.0.1\settings" "C:\Natro\Bot1\settings"
```

### Adding another instance

```powershell
cd C:\Natro\Bot1
powershell -ExecutionPolicy Bypass `
  -File tools\nm-new-instance.ps1 -Name Bot2 -CopySettings
```

The clone is made from the local folder, so on the same drive git hard-links
the object database[^git-clone-local]: it is near-instant and costs almost no
disk space. `origin` is then repointed at GitHub so the new instance updates
normally.

After `-CopySettings`, remember to adjust whatever must stay unique to each
instance: Roblox account, hotkeys, Discord webhook.

## Daily use

### Updating one instance

Double-click **`nm-update.bat`** in the macro folder.

It shows what is about to change, stops **only** the processes started from
that folder, applies the update, then restarts the macro.

- `-KeepLocal` puts your local changes back on top afterwards.
- `-NoRestart` skips the restart.
- `-Clean` also drops untracked files; `settings/` still survives.
- `-Branch main` forces a specific branch.

### Updating every instance

Double-click **`nm-update-all.bat`**. It walks the sibling folders, updates
the ones managed by git, and prints a summary.

It does **not** restart the macros by default, which is what you want when
running it from a single session; add `-Restart` to change that.

## Recommended layout

```text
C:\Natro\
├── Bot1\            <- Remote Desktop session 1, name fixed for good
│   ├── settings\    <- never touched by an update
│   ├── tools\
│   ├── nm-update.bat
│   └── START.bat
├── Bot2\            <- Remote Desktop session 2
└── Bot3\
```

Because the names no longer change, desktop shortcuts, the
`HKCU\...\Run` entry, scheduled tasks and session start-up scripts can all
point at them safely.

## What is kept, what is overwritten

- `settings/` is **kept**, being git-ignored.
- `MMScreenshots/`, `logs/` and `*.log` are **kept**, being git-ignored.
- `paths/`, `patterns/`, `submacros/`, `lib/` and `nm_image_assets/` are
  **realigned** on the repository.
- Your own edits to tracked files are moved into a `git stash` before being
  overwritten.

If you had edited tracked files, the script says so and stashes them. To
review or restore them:

```powershell
git stash list
git stash pop
```

Use `nm-update.bat -KeepLocal` to have that happen automatically every time.

## Pulling upstream fixes into the fork

Instances follow **your fork**. When NatroTeam[^natro-dev] publishes fixes,
integrate them into the fork once:

```powershell
git remote add natrodev https://github.com/NatroTeam/NatroMacroDev.git
git fetch natrodev
git merge natrodev/new-reset
git push origin main
```

The `git remote add` line is only needed the first time. Every instance then
just runs `nm-update.bat`.

Both histories were connected during the migration, so these merges behave
normally: no `--allow-unrelated-histories` is required.

## Disabling the stock updater

This version reports itself as **1.1.2**, which is higher than the latest
public release of NatroMacro[^natro-macro]. The condition
`VerCompare(VersionID, LatestVer) < 0` in `submacros/natro_macro.ahk` is
therefore never true, and the update window no longer opens by itself.

Should a public release ever pass that number, disable the window by adding
this to `settings/nm_config.ini`:

```ini
[Settings]
IgnoreUpdateVersion=999.0.0
```

Do not use the *Update* button in the interface any more: it would run
`submacros/update.bat` again, and create a new folder.

## Troubleshooting

**"Update failed: some files are still locked"**

Windows locks `AutoHotkey32.exe` while it runs. Close every Natro Macro
window belonging to **that** folder, confirm in Task Manager that no
`AutoHotkey32.exe` from it is left, then try again.

**"git is not installed"**

Run `winget install --id Git.Git -e`, then open a new window.

**The script cannot find the remote branch**

Check the tracked branch with `git branch -vv`, and force it if needed with
`nm-update.bat -Branch main`.

**Rolling back to an earlier version**

```powershell
git log --oneline
git reset --hard <sha>
```

**Starting completely clean while keeping the settings**

```powershell
git fetch origin
git reset --hard origin/main
git clean -fd
```

`git reset --hard`[^git-reset] realigns the tracked files, and
`git clean -fd`[^git-clean] removes untracked ones. Without `-x`, both leave
`settings/` alone.

[^gitignore]: <https://git-scm.com/docs/gitignore>

[^git-download]: <https://git-scm.com/download/win>

[^git-clone-local]:
    <https://git-scm.com/docs/git-clone#Documentation/git-clone.txt---local>

[^natro-dev]: <https://github.com/NatroTeam/NatroMacroDev>

[^natro-macro]: <https://github.com/NatroTeam/NatroMacro>

[^git-reset]: <https://git-scm.com/docs/git-reset>

[^git-clean]: <https://git-scm.com/docs/git-clean>
