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

These thirty-three checks run the real coordinator process, the real socket
layer and the real protocol. They are the strongest evidence in the repository.

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
- [x] a bench configuration loses to a real one, in the comparison
- [x] and is refused over the wire, at version 999 against a real 10
- [x] an empty fleet id falls back to the old flat file, and is refused as a
      folder name
- [x] an id carrying a path separator is refused - it arrives from the wire
- [x] two fleets keep two folders, roster and servers
- [x] a new fleet id always opens with a letter, over two hundred draws, so an
      ini cannot read `00123456` back as `123456`
- [x] an old fleet's id is the fingerprint of its secret, so every machine in
      it reaches the same answer without being told
- [x] binding hands the fleet's identity over beside the secret
- [x] only the mandated row may command a coordinator, and a coordinator told
      no mandate obeys the fleet
- [x] a mandate nobody holds any more passes to the rows that are still in the
      roster, and to no others
- [x] a macro without the mandate is refused a handover, on the wire
- [x] the mandated row hands the coordinator on: the order reaches every macro
      carrying the say, and the old process stands down
- [x] the binding door refuses out loud rather than ignoring the request
- [x] the beacon says where to knock, which fleet it is, whether the door is
      open, and what the fleet calls itself

Plus the socket layer: a plain line, an accented line, a line longer than one
read, and a UDP datagram with the sender's address.

And four checks on the bench's own wiring, in `tools/bench-selfcheck.txt`,
which the bench loads and runs because it takes a file of commands as an
argument. Every one of them failed before the seat model was split into the
two sockets a seat has:

- [x] a fake seat keeps its kind when it reaches the bench's own coordinator
- [x] and can still be driven, and still be sent an order as the coordinator
- [x] the coordinator's heartbeat, with its term, reaches a fake seat
- [x] a newcomer that sends only BIND comes back with the bench's secret and
      the bench's fleet identity

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

### The gap inside that, now half closed

The self-test speaks the protocol **directly**. It is a pretend macro, not the
real one. So the coordinator and the wire are proven by it; the macro's own
half is not, and had never run at all.

The bench's coordinator mode closed three of the five. Driven against the real
extension code - the same functions the macro runs, with nothing of Natro
around them - it served a configuration at version 9, then served version 2,
and the macro:

- [x] `ext_fleetReplicate` wrote the replica at v9
- [x] refused to go backwards: the file still said v9 after v2 arrived
- [x] `ext_fleetHandUp` offered its v9 back, and the bench received the SETROW
      frames carrying it

And then the bench staged losing a coordinator - serve a roster where rows 1
and 2 are alive, let a real macro connect as row 3, and stop listening - which
closed two more. Read out of the macro's own state as it happened:

```
+0.5s   connected to the bench
+15.5s  the connection went. row 1 reads offline, row 2 reads online
+15.5s  ext_fleetSuccessor(0) says 2, with one passed over it says 3
+35.0s  TOOK OVER: started a coordinator, pid 11300, term 2
```

- [x] `ext_fleetLostCoord` took the coordinator's row out of the running at
      once, and left row 2 alone - first-hand evidence only, which is the rule
- [x] the election escalated: row 2 was elected, given a whole grace period,
      and passed over. The takeover came 20 seconds after the loss, which is
      two grace periods of ten - not one, and not never.

Still never run:

- [ ] `ext_fleetReplicate` re-reading disk versions on a change of role `loads`
      — needs a macro that coordinates and then stops coordinating, which is
      two benches or two macros rather than one of each

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

## The bench, and what it reaches

`submacros\FleetBench.ahk` is a fleet you drive by hand: it connects as as many
pretend macros as you like, says whatever you tell it to say, and shows every
frame crossing the wire in both directions. One of these and one real macro
with the game running replaces most of "set up six accounts on three machines
first", which is the reason almost nothing below was ever tried.

```
.\submacros\AutoHotkey64.exe /script .\submacros\FleetBench.ahk
```

It has its own port (47700), its own roster file and its own coordinator, and
it cannot reach the real configuration. To use it, point a macro at 47700 in
Fleet settings, Advanced.

It has a console rather than a folder of scripts: the commands are in the
fleet's own idiom, the reference is the box's own opening text, and the
Commands button brings it back if you clear it. `expect` and `reject` make a
sequence of them a test rather than a demonstration.

**It is one fleet with two kinds of member.** The bench always has its fake
macros, which are yours to drive; real macros join the same port and sit in it
beside them. The only choice is who coordinates - nobody, a real `Fleet.ahk`
the bench starts, or the bench itself. Fakes and reals together is the
arrangement that presses on both halves at once: a real coordinator with a
crowd of fakes tests what it does with a crowd, the bench coordinating a real
macro tests what that macro does when it is told something wrong, and both at
the same time tests the crowd and the lie together.

What it has already proven is listed in the two sections above: five fakes
against a real coordinator, and the stale-configuration and lost-coordinator
cases against a real macro.

**What it serves is marked as the bench's**, and a marked configuration loses
to an unmarked one whatever its version. Without that, a real macro pointed
here would replicate the bench's configuration and then hand it up to the real
coordinator, which would take it if the number happened to be higher - a test
tool replacing a real roster. Checked two ways, in the comparison and on the
wire.

The button is on Natro's own **Advanced** tab, the one that appears after
clicking the version several times.

What it turns into a twenty-minute check:

- [ ] **field following**: add a main to the bench, connect it, pick a field and
      press Say the field. A real macro set up as fuzzy or tad should walk
      there on its next gather trip.
- [ ] **the other direction**: let the real macro be the main and watch a GOTO
      arrive at the bench's fuzzy in the log.
- [x] **who follows**: `02-goto-reaches-residents.txt`, above.
- [ ] **leaving**: press Leave the fleet and watch the row vanish from the real
      macro's panel.
- [ ] **a macro out of step**: set Config to a version behind the fleet's and
      press Beat. The real macro's account panel should say so.
- [ ] **the socket ceilings**: paste a very long line into the raw box. The
      connection should be dropped rather than the memory grown.
- [ ] **an unknown verb**: send `WOBBLE x=1` and confirm it is logged and
      ignored rather than breaking anything.

What it does not reach: there is one machine, one network interface, no Roblox
behind the pretend macros, and nothing of theirs ever walks anywhere. It puts
the architecture under pressure from something other than its own self-test,
which is the point, and it is not a fleet.

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

- **One folder per fleet is proven on the wire, not across fleets.** The
  identity reaches a macro during binding and names the folder its
  configuration lives in, so a macro that belongs to the real fleet and to the
  test bench can no longer write one roster over the other. What the self-test
  cannot show is a macro actually moving between two fleets and finding both
  configurations intact afterwards - that needs the bench and a real macro,
  which is the next brick.
- **The coordinator's log moved.** It is derived from the roster path, and the
  roster now lives in a folder per fleet, so it is
  `settings\fleet\<id>\roster.log` rather than `settings\fleet_log.txt`. The
  old file is left where it is; nothing reads it.
- **Leaving a fleet now forgets its secret, reasoned but never driven by a
  test.** Keeping it let one macro create a second fleet carrying the first
  one's secret, and two fleets with one secret share a beacon fingerprint - so
  either one's macros could reach the other's coordinator and replicate its
  configuration into their own folder. Fixed in `ext_FleetLeave` and
  `ext_fleetStartFleet`. No self-test reaches it: both are window code behind a
  confirmation box, and the self-tests only speak the protocol.
- **No real macro has ever joined the bench.** The beacon, the door and the
  binding are all driven and checked, but by the bench's own fake seats
  connecting to its own listener - which is a real socket, a real frame and a
  real roster write, and still not a copy of natro_macro.ahk deciding to
  join. That is the one thing left before the answer to "how do I connect a
  real account" is proven rather than reasoned.
- **Nothing sends `HOST` yet.** The verb, the permission and the macro's
  response to it are proven on the wire, driven by the self-test speaking the
  protocol directly. No window and no button asks for a handover - the bench
  is where the first caller goes, and choosing the coordinator from a macro's
  own settings is part of P4.
- **The mandate is in no window.** It rides on every heartbeat and appears in
  the coordinator's first log line, and the settings window says where new
  macros are accepted when this macro cannot accept them - but nothing names
  the mandated row outright. Deliberate: the interface says who coordinates and
  nothing else, which is the vocabulary that was asked for.
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
