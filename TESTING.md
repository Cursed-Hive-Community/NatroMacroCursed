# What is proven, and what is not

This fork adds a lot that has never been played. The commits say so one at a
time, which is no use when the question is "what is left to check?" - so this
file is the one list, and it is meant to be edited as things get proven.

**The rule: move a line up only when you have the evidence the line names.**
A thing that loads is not a thing that works.

## The six kinds of evidence

They are not interchangeable, and most of this fork has only the first two.

| Tag | What it means | How |
|---|---|---|
| `sieve` | The structure is not obviously broken. Says nothing about behaviour. | `python3 tools/nm-check.py` |
| `loads` | AutoHotkey parses it and would start it. | `tools/win-test.sh`, step 3 |
| `wire` | A self-test drove the real code and checked the answer. | `tools/win-test.sh`, step 4 |
| `layout` | Every control's rectangle and text was read out of the built window. | the dump harness, see below |
| `game` | Somebody watched it do the right thing in Bee Swarm Simulator. | you, on the machine that plays |
| `fleet` | It was run across two or more machines at once. | you, with two PCs |

`sieve`, `loads`, `wire` and `layout` are all automated and all run from the
Mac against the Windows VM. `game` and `fleet` cannot be: the VM has no Roblox
and one network interface. **No macro feature in this fork has `game` or
`fleet` yet** - one PowerShell tool is the only thing here that has met a real
machine.

### Running the automated ones

```bash
tools/win-test.sh                 # everything
tools/win-test.sh --changed       # only what your edits can break
```

On the Windows machine itself, without the Mac:

```
.\submacros\AutoHotkey64.exe /script .\submacros\SocketSelfTest.ahk
.\submacros\AutoHotkey64.exe /script .\submacros\FleetSelfTest.ahk
```

Both open a window with the verdict and write `settings\fleet_diag.txt` or
`settings\socket_diag.txt`. Add `/quiet` for an exit code and no window.

### Why `layout` exists instead of screenshots

A window built over SSH lives on the service session's desktop and is never
composited, so `PrintWindow` returns solid black however it is asked. The
substitute is to build the real window and dump every control's name, type,
rectangle, enabled state and text. That catches a wrong field, a collision, an
overflow and a control that should be greyed out. It cannot catch a colour.
See the `windows-vm` skill for the harness.

---

## Proven on the wire

These eighteen checks run the real coordinator process, the real socket layer
and the real protocol. They are the strongest evidence in the repository.

- [x] both rows reach the main macro
- [x] both rows reach the fuzzy macro
- [x] a space in an account name survives the wire
- [x] a wrong secret is refused
- [x] the main's field reaches a resident as a GOTO
- [x] a resident joining late is sent the field anyway
- [x] an unreadable roster strikes nobody off
- [x] a ping is answered and timed
- [x] a macro that leaves is struck from the fleet, file included
- [x] a second coordinator is refused the port
- [x] a second setup of one account reuses its row
- [x] the server list arrives with its link and owner intact
- [x] a deleted server disappears from a macro's copy
- [x] a configured row that has never connected is still broadcast
- [x] a bad secret is final, an unknown row is not
- [x] a stale configuration handed up is refused
- [x] a better configuration handed up is taken
- [x] a tie keeps ours and files theirs as `.conflict`
- [x] a roster cleared on purpose is applied, where an unreadable one is not
- [x] a macro's own configuration version reaches the fleet

Plus the socket layer: a plain line, an accented line, a line longer than one
read, and a UDP datagram with the sender's address.

And thirty-four checks on the extensions' arithmetic — every window in time
that any of them turns on, each with a row one second outside it, one exactly
on its edge and one inside:

- [x] the lease window at thirty, sixty and a hundred and five seconds, and the
      upper edge being exclusive because at 900 the lease is over
- [x] pre-glitter between ten and eleven minutes before the booster, and not
      while a glitter is still running
- [x] the blue booster at 2660 of its 2700 second cooldown
- [x] the sticker stack past its timer, after a failure, and never twice inside
      a minute
- [x] Mondo at :59, through the :00 to :14 catch-up window, and the fifty-five
      minute guard against claiming one spawn twice

They run in well under a second: no socket, no sleep, no clock read. The
functions they call were deliberately separated from the state they used to
read, so they take their numbers as arguments.

**This proves the arithmetic, not the feature.** That a window is the right
thirty seconds says nothing about whether the macro presses the key when it
opens.

### The gap inside that

The self-test speaks the protocol **directly**. It is a pretend macro, not the
real one. So the coordinator and the wire are proven; the macro's own half is
not. These mirror the coordinator's logic "in miniature" in the test and have
never actually run:

- [ ] `ext_fleetReplicate` — writing a replica, and refusing to go backwards `loads`
- [ ] `ext_fleetHandUp` — offering a better configuration `loads`
- [ ] `ext_fleetLostCoord` — marking a lost coordinator offline `loads`
- [ ] `ext_fleetSuccessor` escalation — passing over a dead candidate `loads`
- [ ] `ext_fleetReplicate` re-reading disk versions on a change of role `loads`

A test that drove two real macros instead of two pretend ones would close
this, and would need two AutoHotkey processes with their own settings folders.
Worth doing before trusting failover.

---

## Proven as layout

Control rectangles and text read out of the built window. Geometry and content
only - **no colour in this fork has ever been looked at**.

- [x] Fleet window: seat cards, their three lines, the three bands, no overflow
- [x] Fleet settings: section 2 summary, section 3 table, the disabled state off
      the coordinator and the line naming who to go to
- [x] Servers window: the table, the owner dropdown and the rows behind it,
      selecting a row filling the fields
- [x] One account: all ten rows, including an account owning two servers
- [x] Advanced: the four follow switches, their checked state, the group box and
      hint not overlapping

Never dumped:

- [ ] the join dialog (`ext_FleetJoinGUI`) `loads`
- [ ] the Extensions tab and its two live strip lines `loads`
- [ ] the Git Sync window `loads`

---

## Never run at all

Everything below has `sieve` and `loads` and nothing more. Grouped by what you
would sit and watch.

The numbers in these windows are now checked by the extension self-test, so
what is left in each line is the half a table of values cannot reach: that the
macro notices the window, presses the right key, and goes to the right place.

### Boost lease - Glitter Extend

The windows are DefinetlyNotRay's measured values and are deliberately kept.

- [ ] glitter fires in the **last 30 seconds** of a lease while gathering
      (870-900s after the boost was detected)
- [ ] glitter fires in the **last minute** when about to leave and convert
      (840-900s), because the trip would outlast the lease otherwise
- [ ] **one renewal per lease** and no more - a second would throw away whatever
      is left of the first
- [ ] the status line says `Boosted / Glitter Extend` when it fires
- [ ] 30 minutes of continuous boost from one booster plus one renewal
- [ ] the lease is handed back when it expires, so the next boost gets its own
      renewal (`ext_boostLeaseExpire`)
- [ ] nothing fires with no glitter hotbar key set

Needs: Extensions tab, Glitter Extend on; a glitter key in the Boost tab.

### Pre-Glitter

- [ ] fires only on **Pine Tree**
- [ ] fires when the blue booster is **10 to 11 minutes** away and not otherwise
- [ ] the macro still collects, does quests and tends planters while it runs -
      the whole point, since locking them out for 15 minutes costs more than the
      boost is worth
- [ ] it stops counting as a boost once the booster comes due
- [ ] pressing the blue booster clears it (`ext_preGlitterClear`)

Needs: Pre-Glitter on **and** Blue Booster Interrupt on, which is what tracks
the cooldown.

### Blue booster interrupt

- [ ] the macro breaks off a gathering trip **40 seconds before** the 45 minute
      cooldown is up (2660s), rather than waiting for the trip to end
- [ ] it arrives as the booster becomes available instead of standing there
- [ ] pressing it starts a fresh lease owed its own renewal
- [ ] a trip that never reached the booster retries in **5 minutes**, not at once
      (`ext_blueBoosterFailed`)

### Sticker stack interrupt

- [ ] the macro breaks off as soon as the timer is up and places the stack
- [ ] it then returns to the hive to convert **under** the stack - the second
      half is the point of the first
- [ ] a placement that failed retries after 15 seconds, and never twice inside a
      minute whatever the timers say
- [ ] a failure says so in the status line rather than passing silently
- [ ] re-entry is impossible: the reset passes back through interrupt checks and
      a stack placed twice is a stack wasted

Needs: Sticker Stack enabled in the Boost tab, where the timer and item live.

### Mondo interrupt

- [ ] the macro leaves at **:59** and is standing at Mountain Top as the chick
      appears
- [ ] the field boost is renewed **before** leaving when the lease is in its last
      105 seconds
- [ ] arriving between **:00 and :14** still counts, for the times it was
      mid-pattern with a full backpack
- [ ] one spawn is never claimed twice (the 3300s guard)
- [ ] it runs for `MondoSecs` and goes home
- [ ] a spawn that never appears is reported, not waited on for ever
- [ ] it does nothing unless Mondo is set to **Buff**

Not implemented and deliberately so: the **Kill** path, which is what an `atk`
account is for. It waits for the queue - see the note above `ext_mondoDue`.

### Limits and process lifecycle

These are the two that can take a process down, and neither is cheaply testable
with the harness that exists - which is a reason to write it down, not a reason
to pretend otherwise.

- [ ] a peer that stops reading is dropped once its send queue passes 1 MB
      `loads` — needs a peer that does not drain its socket, and this library's
      dispatcher always drains, so the harness cannot build one
- [ ] a stream with no end of frame in 64 KB is dropped `loads` — testable only
      by sending raw bytes with no newline, which would mean adding a raw send
      to a library that is deliberately line-only, for the test's sake alone
- [ ] closing the macro ends the coordinator it started (`OnExit`) `loads`
- [ ] a coordinator whose macro was killed exits after 5 minutes alone `loads` —
      correct by reading, and a test would have to wait out the 5 minutes
- [ ] a macro does not start a second coordinator while its own still runs
      `loads`
- [ ] a coordinator that fails to launch says so instead of being retried in
      silence `loads`

The quickest real check for all six: open the macro, look in Task Manager for
one `AutoHotkey64.exe` more than you started, close the macro, and look again.

### Enzymes, boosted only

- [ ] ticked, an enzyme is held back until the field is boosted
- [ ] unticked, one is used whenever the 10 minute cooldown is up
- [ ] the boost is read through the **lease**, so a glitter renewal counts
- [ ] the status line says `Converting / Balloon - Used Enzyme`

---

## Never run across machines

This is the half that matters most and the half with no evidence at all. Two
PCs, two macros, and a network you can unplug.

### Binding and discovery

- [ ] a second machine finds the fleet by beacon with **nothing typed**
- [ ] the door opens for two minutes and shuts itself
- [ ] clicking the button again shuts it early
- [ ] a macro bound once rejoins by itself after a restart
- [ ] a beacon from a different fleet on the same network is ignored
- [ ] a hand-typed address works where broadcasts are blocked

### Following

- [ ] a fuzzy or tad gathers the field the main is farming
- [ ] it switches at the **top of a gather trip**, never mid-pattern
- [ ] it farms that field exactly as one of its own - boost detection and
      gather-start hotkeys included
- [ ] a `guid` or an `atk` never follows
- [ ] the four Advanced switches decide which of the main's trips are followed,
      and only the **main's** switches matter
- [ ] a suppressed trip leaves the residents where they are rather than recalling
      them
- [ ] a resident re-roled away from fuzzy/tad stops following without a restart

### Failover - the dangerous one

Everything here is reasoning and a self-test against a pretend macro. None of
it has been watched happen.

- [ ] the host's coordinator comes up at startup
- [ ] killing the coordinator's **process** gets a replacement within the grace
      period
- [ ] killing the whole **machine** does too - this is the case the election
      escalation exists for, since one machine carries several rows
- [ ] the replacement serves a **current** configuration, because it had a replica
- [ ] the designated host takes the job back when it returns
- [ ] accounts do not bounce between servers while that happens
- [ ] a macro that loses the fleet entirely **carries on farming alone** - the
      governing rule of the whole subsystem
- [ ] two coordinators cannot both serve: the port is the lock on one machine,
      and the term is supposed to settle it across machines (**P3, not written**)

### Configuration, shared

- [ ] an account bound on machine B appears in the table on machine A
- [ ] editing the roster on the coordinator reaches every macro
- [ ] a server added on the coordinator reaches every macro
- [ ] a server deleted disappears everywhere within a beat
- [ ] the owner dropdown lists accounts that have never connected
- [ ] the table and the servers window are read-only off the coordinator, and say
      where to go
- [ ] **the stale-copy case**: unplug two machines, change the configuration on
      the rest, plug the two back in first so one takes over, and check that the
      good configuration wins and nobody's file was overwritten
- [ ] a tie leaves a `.conflict` file and a line in the log
- [ ] the macro that loses a tie says so on its own screen too, not only in the
      coordinator's log
- [ ] a settings folder made read-only is reported rather than silently costing
      the fleet its replica

### The panel, live

- [ ] seat colours mean what they claim: offline grey, stale pink, guiding amber,
      online blue - **the only check in this file that a dump cannot do**
- [ ] a card repaints correctly when a macro quits and comes back
- [ ] response time and "last heard from" tick along on their own
- [ ] the log says why seats changed hands
- [ ] clicking a card opens the right account
- [ ] the two strip lines on the main window track the fleet
- [ ] the summary names the configuration version, and says so loudly when this
      macro holds a different one
- [ ] the account panel's Configuration row shows a macro out of step

---

## Git tooling

From earlier commits, and partly used in anger already.

- [x] `nm-git-adopt.ps1` turns a plain Natro install into this fork - done once
      on a real machine, `safe.directory` problem and all
- [ ] `nm-git-update.ps1` updates in place without losing settings `loads`
- [ ] `nm-new-instance.ps1` makes a second instance `loads`
- [ ] `nm-update-all.ps1` updates every instance on a machine `loads`
- [ ] the Git Sync window in the GUI `loads`

---

## Known holes, written down rather than forgotten

Not bugs to find - bugs already known about, with no fix yet.

- **P3, split brain across machines.** `SO_EXCLUSIVEADDRUSE` stops two
  coordinators on one machine. Two machines can still each run one, and
  `ext_fleetOnBeacon` latches onto the first beacon whose fingerprint matches
  without comparing terms. A macro can therefore attach to a stale coordinator
  and obey it. The fix is small: highest term wins, on the beacon as well as the
  heartbeat, and a coordinator that sees a higher term stands down.
- **P4, editing from anywhere.** The roster and the servers are read everywhere
  and editable only where the coordinator runs. `SETROW` and `SETSERVER` already
  carry a whole configuration at a bumped version, so what is left is a gate on
  who may bump and the interface around it.
- **More than six offline macros** and the extra cards are not drawn. The count
  still tells the truth.
- **Colour has never been seen.** Every palette decision in the Fleet window is
  unverified.
- **Absolute timestamps cross machines.** `until` on a guiding star comes from
  the reporting macro's clock and is counted down against the viewer's. Two
  minutes of drift between PCs makes the countdown two minutes wrong, and ten
  makes "last heard from" meaningless. Durations should travel as seconds
  remaining. Not fixed.
- **The configuration is rebroadcast every beat** even when nothing changed. The
  version makes it free for the receiver, not for the network. It should go out
  on change and on a join only - which it already does, so what is left is to
  stop sending it on the beat as well.
