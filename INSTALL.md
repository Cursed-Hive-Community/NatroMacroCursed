# Installing this fork on a Natro Macro you already have

For somebody who has never touched git. Windows, five minutes.

**Your settings are not touched.** Accounts, hotkeys, fields, patterns, the
Discord webhook: the whole `settings` folder is left exactly as it is, by this
install and by every update after it. Nothing is re-downloaded either - the
folder you already run becomes the one that updates itself.

---

## 1. Close the macro

Every window of it. Then open **Task Manager** (Ctrl+Shift+Esc), look for
**AutoHotkey** in the list, and end whatever is left.

Windows locks a program's files while it runs, and the install has to replace
two of them. If you skip this, step 3 stops and tells you so - nothing is
broken, you just have to come back here.

## 2. Install Git, once per computer

Git is what fetches the updates. You will never have to use it yourself.

Right-click the **Start** button, choose **Terminal** or **PowerShell**, paste
this and press Enter:

```powershell
winget install --id Git.Git -e
```

When it finishes, **close that window and open a new one**. Without that,
`git` will not be recognised.

> No `winget` on your Windows? Download the installer from
> <https://git-scm.com/download/win> and click Next to the end. Every default
> is fine.

## 3. Point your folder at the repository

In the new Terminal window, paste this block - **replacing the path on the
first line with your own macro folder**, the one that contains `START.bat`:

```powershell
cd "C:\Natro\Bot1"
git init -b feature/rays-extensions
git remote add origin https://github.com/Cursed-Hive-Community/NatroMacroCursed.git
git fetch origin
git reset --hard origin/feature/rays-extensions
git branch -u origin/feature/rays-extensions
```

Line by line, so you know what you are running:

| Command | What it does |
|---|---|
| `cd "..."` | go into your macro folder |
| `git init -b feature/rays-extensions` | get the folder ready to be tracked by git |
| `git remote add origin ...` | say where the fork is |
| `git fetch origin` | download the fork, without changing anything yet |
| `git reset --hard origin/feature/rays-extensions` | replace the macro's files with the fork's |
| `git branch -u origin/feature/rays-extensions` | remember which branch to follow, for updates |

`git reset --hard` is what does the work, and it is also what **cannot** touch
`settings`: git has never had that folder among its files, and `reset` only
writes the ones it knows about. Your notes, your logs and anything else you put
there yourself survive for the same reason.

## 4. Start the macro

Double-click **`START.bat`**, the way you always have.

Everything is where you left it. Along the bottom of the macro window there is
now a **Git Sync** button, next to Stop: that is how you update from here.

---

## Updating, from then on

Two ways, one click each:

- the **Git Sync** button in the macro, then **Update**;
- or **`nm-update.bat`** in the folder.

Both stop the macro, install the new version, keep your settings and start the
macro again.

---

## When it goes wrong

### `fatal: detected dubious ownership in repository at ...`

Git refuses to work in a folder that, as far as Windows is concerned, belongs
to somebody else - because a repository you do not own could run its own code.
It happens when the folder was created under another Windows login, copied from
another PC, or made by a program running as Administrator.

On your own PC that is not what is happening. Paste the line git offers you
itself - it is in the error message - which looks like:

```powershell
git config --global --add safe.directory "C:/Natro/Bot1"
```

Then pick step 3 back up where it stopped.

> If you have five macro folders and would rather not do this five times:
> `git config --global --add safe.directory "*"` accepts everything. That turns
> the check off everywhere, which is fine on your own PC and best avoided on a
> shared machine.

### `Permission denied` or `Access is denied`

Here Windows will not let you write in the folder at all: it belongs to another
user **and** that user has not given yours the rights. Not even Natro Macro's
own updater could work in it.

Simplest fix: **copy the folder somewhere of your own**. Make `C:\Natro`, copy
the whole macro folder into it, and do step 3 on the copy. Your settings come
along.

Otherwise, to take ownership: right-click **Start**, **Terminal (Admin)**, then
with your own path in place of the example:

```powershell
takeown /F "C:\Natro\Bot1" /R /D Y
icacls "C:\Natro\Bot1" /grant "$env:USERNAME":(OI)(CI)F /T
```

### `error: unable to unlink ...`, or a `.exe` named in the error

The macro is still running. Back to step 1: close its windows, check in Task
Manager that no **AutoHotkey** is left, and run the last command again.

### `git is not recognized`

Step 2 did not finish, or you stayed in the same window. Close every Terminal,
open a new one and check:

```powershell
git --version
```

### You want to go back

Nothing is lost - the old version is in the folder's history. In the Terminal,
in your macro folder:

```powershell
git log --oneline
git reset --hard <the number of the line you want>
```

`settings` is not affected by that either.

---

## Questions people ask

**Does this replace Natro Macro?** No. It *is* Natro Macro, with extra features
on top. Everything you know how to do works the same way.

**Will I lose my settings?** No. `settings` is left alone by every install and
every update, for good.

**Several accounts?** Yes, one folder each, as before. Do step 3 in each
folder.

**Back to the official version?** In **Git Sync**, set the repository to
`https://github.com/NatroTeam/NatroMacro.git`, Save, then Update.

**Do I need a GitHub account?** No.

**I was told to follow a different branch.** Put its name in place of
`feature/rays-extensions` everywhere it appears in step 3 - all three times.

---

## If you are stuck

Say which step you were on and paste what the window showed. The exact wording
matters: the messages above are written to be told apart from each other.

The details behind all of this, for anyone who wants them, are in
[UPDATE-GIT.md](UPDATE-GIT.md).
