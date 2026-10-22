# Installing this fork on a Natro Macro you already have

For somebody who has never used git and does not want to start. Windows,
start to finish, about five minutes.

**Your settings are not touched.** Accounts, hotkeys, fields, patterns, the
Discord webhook, your planter setup - all of it stays exactly as it is, and
every update after this one keeps it too. Nothing is re-downloaded either:
the folder you already run becomes the folder that updates itself.

---

## 1. Close the macro

Every window of it. Then open **Task Manager** (Ctrl+Shift+Esc), look down the
list for **AutoHotkey**, and end whatever is left.

This matters: Windows locks a program's files while it runs, and the install
cannot replace a file that is locked. If you skip this, step 3 stops and tells
you so - it does not break anything, you just have to come back here.

## 2. Install Git, once per computer

Git is what fetches updates. You will never have to use it yourself.

Right-click the **Start** button, choose **Terminal** or **PowerShell**, paste
this and press Enter:

```powershell
winget install --id Git.Git -e
```

When it finishes, **close that window**. Nothing else uses it.

> No `winget` on your Windows? Download the installer from
> <https://git-scm.com/download/win> and click Next until it ends. Every
> default is fine.

## 3. Run the installer

In your Natro Macro folder - the one with `START.bat` in it - find
**`nm-install.bat`** and **double-click it**.

> `nm-install.bat` is not in your folder yet, because it comes with this fork.
> Download the fork as a .zip from the green **Code** button on
> <https://github.com/Cursed-Hive-Community/NatroMacroCursed>, open the .zip,
> and copy `nm-install.bat` and the whole `tools` folder into your macro
> folder. That is all you need from the .zip - the installer fetches the rest.

It tells you what it is about to do and waits for you to agree. Then it works
for a minute or two and says it is done.

## 4. Start the macro

Double-click **`START.bat`**, the way you always have.

Everything is where you left it. Along the bottom bar of the macro window
there is now a **Git Sync** button, next to Stop - that is how you update from
now on.

---

## Updating, from then on

Two ways, both of them a click:

- the **Git Sync** button in the macro, then **Update**;
- or **`nm-update.bat`** in the folder.

Either one stops the macro, brings the new version in, keeps your settings and
starts the macro again.

---

## When Windows gets in the way

This is the part that catches people, so it is worth reading before it happens
rather than after.

### "This folder is recorded as owned by BUILTIN\\Administrators"

Harmless, nothing for you to do, and you will probably see it. Windows records
anything an Administrator created as belonging to the Administrators group
rather than to a person, so this is the ordinary state of a folder made from an
admin window or dropped there by an installer.

### "This folder belongs to <somebody>, not to you"

Also harmless, and also handled. This is the one you get when the folder really
was made under a different Windows login, or copied from another PC.

Both messages are about the same thing. Git refuses to work in a folder it
thinks belongs to someone else, because a folder you do not own could run its
own code behind your back. On your own PC that is not what is happening, so the
installer tells git that this one folder is fine - only that one - and carries
on.

### "Windows will not let this account write in ..."

This one does need you. The folder belongs to another Windows user **and** that
user did not give yours permission, so nothing can be installed or updated in
it at all - not by this fork, and not by Natro Macro's own updater either.

Three ways out, easiest first:

1. **Log in as the user who owns the folder** and run `nm-install.bat` there.

2. **Copy the folder somewhere of your own.** Make `C:\Natro`, copy the whole
   macro folder into it, and run `nm-install.bat` in the copy. Your settings
   come along with it.

3. **Take ownership of it.** Right-click **Start**, choose
   **Terminal (Admin)**, and paste these two lines, with your own path in
   place of the example:

   ```powershell
   takeown /F "C:\Natro\Bot1" /R /D Y
   icacls "C:\Natro\Bot1" /grant "$env:USERNAME":(OI)(CI)F /T
   ```

   The first makes you the owner, the second gives you full access to
   everything inside. Then run `nm-install.bat`.

### "Update failed: some files are still locked"

Step 1 again: a macro window from **that** folder is still open, or an
`AutoHotkey` process from it is still in Task Manager. Close it and run the
update again.

### "git is not installed"

Step 2 did not finish, or the window it ran in was never closed. Close every
Terminal window, open a new one, and check with:

```powershell
git --version
```

### Something went wrong and you want the old version back

Nothing is lost - the previous version is still in the folder's history. Open
Terminal in the folder and run:

```powershell
git log --oneline
git reset --hard <the line you want>
```

Your `settings` folder is never affected by that.

---

## Questions people ask

**Does this replace Natro Macro?** No. It *is* Natro Macro, with extra
features on top. Everything you know how to do still works the same way.

**Will I lose my settings?** No. `settings\` is left alone by every install and
every update, for ever. That is the one promise this tooling is built around.

**Can I run several accounts?** Yes, one folder each, exactly as before. There
is a tool for making a second one in a few seconds - see
[UPDATE-GIT.md](UPDATE-GIT.md#adding-another-instance).

**Can I go back to the official version?** Yes. In **Git Sync**, change the
repository to `https://github.com/NatroTeam/NatroMacro.git`, press Save, then
Update.

**Do I need a GitHub account?** No.

---

## If you are stuck

Say which step you were on and paste what the window said. The exact wording
matters - the messages above are written to be told apart from each other.

The details behind all of this, for anyone who wants them, are in
[UPDATE-GIT.md](UPDATE-GIT.md).
