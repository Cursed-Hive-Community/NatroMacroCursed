# Tad sync: your tad and fuzzy accounts follow your main

Your main farms a field; every tad and fuzzy account walks to that field and
farms it too, because the field they stand in is the one they improve. When
the main changes field, they change with it. Nothing is typed twice.

In this fork, tad sync is part of **Fleet**: the macros on your accounts talk
to each other over your network. It is not the `tad-sync` branch of Natro
Macro Dev, which works differently and is not in this fork.

> **Status.** The pieces are covered by automated tests on one Windows
> machine. It has never run across two PCs, and never in the game. If
> something behaves oddly, say which step and what you saw.

# Before you start

- Every account has its own macro folder, each one installed with this fork:
  see [INSTALL.md][install].
- All the macros run on **one PC**, or on PCs on **the same home network**.
- Every account is in the **same server**. Tad sync chooses the field the
  alts gather; it does not move them between servers.

# 1. Start the fleet on the main

On the macro that plays your **main** account:

1. Open the **Extensions** tab and press **Fleet panel**, then **Settings**.
2. Press **Set up this macro**.
3. Fill in the window:
   - **Name**: anything, it is only a label - `Main` will do;
   - **Role**: `main`;
   - **User**: the exact Roblox username of that account.
4. Press **Start a new fleet here**.

That macro now runs the fleet.

# 2. Add each tad and fuzzy account

Do this once per alt, one at a time.

On the **main's** macro, in the same Settings window, press **Accept new
macros**. The door stays open for two minutes and the button counts down.

Then on the **alt's** macro:

1. **Extensions**, **Fleet panel**, **Settings**, **Set up this macro**.
2. **Role**: `tad` or `fuzzy`. Nothing is picked for you, and the buttons
   stay grey until a role is chosen.
3. **User**: the alt's Roblox username.
4. Wait for the line saying `Found ... accepting new macros`, then press
   **Join this fleet**. If nothing is found after a few seconds, type the
   address the main's Settings window shows (`Address: ...`) in **Not found?
   Type its address**, then press **Join this fleet**.

A message says `Joined`. From now on that macro rejoins by itself every time
it starts; this step is never repeated.

# 3. Choose which trips the alts follow

On the **main's** macro only: Settings, **Advanced**, the box **Fuzzy and tad
accounts follow the main into**.

| Box | Ticked by default | Why |
|---|---|---|
| Its own field | yes | where the main normally farms |
| The boosted field | yes | the whole point of a fuzzy |
| A quest field | no | an errand for the main alone |
| A planter field | no | the same |

When a trip is not followed, the alts stay where they were: in the field the
main will come back to.

# 4. Start everything

Start every macro the usual way (F1).

The main says which field it is going to as soon as it picks it, before it
walks there. Every tad and fuzzy stops what it is doing within a quarter of a
second, resets to its hive and goes to that field. It stays there until the
main moves again or its own bag is full. A full bag is converted the way that
macro's Natro is set, reset or walk, and the alt goes straight back.

An alt that starts, restarts or reconnects later is told the main's field as
soon as it joins. The field is also repeated every five seconds, so an alt
that missed the order is put right within one beat.

# What a tad or fuzzy account does not do

An account set as `tad` or `fuzzy` has one job: being in the main's field,
as soon as possible and for as long as possible. Its macro skips everything
else Natro would do:

- planters, quests and bug runs;
- collecting, dispensers and the sticker stack;
- boosts, boosters and the shrine;
- Mondo and the night hunt.

It gathers with no time limit: only a full bag or the main moving makes it
leave.

Until the main has said where it is, the alt farms its own field. If Fleet is
switched off on it, or the fleet turns it away for good, it is an ordinary
Natro again and does all of the above.

# Changing an account later

On any macro in the fleet, Settings, section **3 - the accounts**: click the
account, change its **Role**, press **Update**. The change reaches every
macro. A fleet has one main: to move the role, change the old main first.
An alt taken off `tad` or `fuzzy` stops following straight away, without a
restart.

To take a macro out of the fleet: its own Settings, **Leave the fleet**.

# When something is wrong

**The alt says `Listening for a fleet on your network...` and nothing
happens.**

- The door is shut: press **Accept new macros** on the main again. It only
  stays open for two minutes.
- Windows Firewall blocked the macro. If Windows asks whether to allow
  **AutoHotkey** on the network, allow it on **private** networks, on every
  PC. If you already answered no, allow AutoHotkey in Windows Security,
  Firewall, *Allow an app through firewall*.
- The two PCs cannot hear each other. A macro finds the fleet by a message
  sent to the whole network, and guest Wi-Fi or a router with *client
  isolation* drops it. Put both PCs on the same normal network, or run the
  macros on one PC.

Or go round it: the main's Settings window shows the main PC's address in
section 1. Type it in the alt's join window under **Not found? Type its
address**. The alt keeps that address and uses it to reconnect from then on.

**The alt joined but keeps farming its own field.**

- Its role is not `tad` or `fuzzy`: check section 3 on the main.
- The main's role is not `main`. Only an account set as main is followed.
- The main is on a trip whose box is unticked in step 3.
- The main has not started a gather trip yet since it was started.
- The alt's Natro has no pattern for the main's field.

Each macro writes what it heard and did in `settings\fleet_macro.log`. On the
alt, `the main is farming X - following it now` means the order arrived, and
`gather trip: following the main into X` means it acted on it. On the main,
each field is listed with whether it was announced.

**The main's PC is turned off.**

Another macro takes over running the fleet after 45 seconds, and gives the
job back when the main returns. The alts keep farming the last field they
were sent to. No macro stops because the fleet is gone.

**The Fleet panel shows an error.**

Copy the exact line and send it along with the step you were on.

[install]: INSTALL.md
