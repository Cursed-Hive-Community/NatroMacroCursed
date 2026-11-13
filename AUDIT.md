# Audit of feature/rays-extensions

Written on 13 November 2026, against commit `647a233` and the eight fixes
that follow it. It answers four questions the user asked of the branch:

- is it safe to give to friends;
- can it become the base version;
- what would break a real night of farming;
- what is wrong, in order of how much it costs.

The user's limits, in their words: no leaked secret, no stranger driving a
macro, no lost night, no broken stock Natro. The fleet may run on one PC, on
several PCs at home, on a shared network, or between friends over the
Internet. The findings are ranked against the worst of those.

# The short answer

- **Tad sync works, and the fleet around it does not hold.** When every
  macro talks to the same coordinator, a tad is gathering in the main's new
  field about three seconds after the main. But on the one real run there
  is evidence for, the macros ended up on two coordinators twice, and the
  tads stopped following for 7 hours and then for 20.
- **It is not safe on a network other people are on.** A macro obeys
  whatever claims to be its coordinator, and hands it the fleet's secret.
- **Guid hop has never run.** It was off in every log. It is reviewed here
  and nothing more.
- **Stock Natro, with every extension off, was skimmed, not read.** Two
  small changes of behaviour were found.

Eight faults were small enough to fix on the spot. They are listed under
"Fixed in this audit". The two that matter most are not among them: both
need a design decision, and both are described under "Open".

# What was looked at, and how

The branch is 97 commits and 22 000 added lines over `main`.

| Part | How |
|---|---|
| Socket, protocol, roster, servers, hop rules | read in full |
| The coordinator (`submacros/Fleet.ahk`) | read in full |
| The macro's side, without its windows | read in full |
| The macro's windows (about 1 700 lines) | searched, not read |
| `natro_macro.ahk` against `main` | hunks from `nm_Start` on, read |
| Boost lease and interrupts | read in full |
| Install and update scripts | read |
| OCR libraries, Auto-Jelly, StatMonitor, passive reader | not read |

Evidence is named with the words `TESTING.md` uses. Two more are used here:

- **read**: the code says so, and nothing ran;
- **logs**: three real macro folders, a main on one PC and two tads on
  another, 28 October to 12 November. All three ran this branch's `HEAD`
  from 11 November 12:03.

The whole VM suite was green before the audit and is green after it. It
failed once in ten runs on the bench self-check: see `TESTING.md`.

# What the real run showed

One fleet, `gm3hrt5c`, created on 11 November at 12:06. Times are the
main's clock; the tads' PC runs about five seconds behind.

| When | What happened |
|---|---|
| 12:07 | A tad starts a coordinator five seconds after joining |
| 12:18 | First order: both tads follow within a second |
| 12:56 | The main's macro restarts; its coordinator restarts at term 1 |
| 13:13 | The main is away 55 s; a tad takes over at term 7 |
| 13:13 | The main comes back and moves to the tad's coordinator |
| 13:13 | That tad itself connects to the main's old coordinator |
| to 20:37 | **One tad follows. The other stays in Pine Tree: 7 h 24** |
| 21:02 | The main takes the job back, then connects to the tad's |
| 21:02 | Both tads move to the main's new coordinator |
| to 17:08 | **Nobody follows: 20 h, 36 changes of field** |

In those 20 hours the main and its tads had swapped coordinators. Each side
was connected, heard nothing wrong, and logged nothing.

The following itself, measured on the tad that stayed with the main: the
main announces Bamboo at 13:25:59, the tad stops gathering the same second,
and it is gathering in Bamboo three seconds after the main.

# Fixed in this audit

One commit each. "Red first" means the check was seen failing before the
change and passing after it.

| Commit | Fault | Evidence |
|---|---|---|
| `87d377d` | A refusal was lost before it was read | logs, wire, red first |
| `151d629` | A stranger's frame raised an error dialog | wire, red first |
| `5d7576a` | A row that went quiet never came back | wire, red first |
| `f4446d1` | A server link could open any site or add settings | wire |
| `fe97446` | A second alt took the first alt's row | logs, wire |
| `9e28809` | A refused macro knocked every two seconds | logs, loads |
| `3f28504` | The frame size limit could be outrun | wire, red first |
| `5a1ed7d` | A macro took over five seconds after starting | logs, loads |

The numbers behind them:

- **Refusals lost.** 4 760 connections refused, the reason read 479 times.
  Windows resets a connection closed with unread bytes, and a reset discards
  what the other end has not read. The message a copied folder is meant to
  show (`647a233`) would mostly not have been shown.
- **Error dialog.** `OPEN secs=abc`, from a connection that never said
  HELLO, raised AutoHotkey's error dialog on the coordinator's PC, over the
  game.
- **Quiet row.** Silent for 36 s, then 16 s of heartbeats: still "not heard
  from". Such a row is sent no field and takes no part in the hop.
- **Server link.** Natro's reconnect puts the link on the browser's command
  line every fifth attempt and writes it to `nm_config.ini`, where Natro
  reads every `key=value` line as a setting. A link from the wire could
  hold a new line.
- **Second alt.** Two alts left on the default name on one PC were bound to
  the same row and threw each other out twenty times in forty seconds.
- **Knocking.** 8 800 refusals in four hours, half a megabyte of log on
  each side, and "connecting" on the panel.
- **Size limit.** A frame of 201 600 characters, three times the limit, was
  delivered whole.

`9e28809` and `5a1ed7d` are on the macro's side, which no test drives: they
load, and nothing more.

# Open: security

Ranked for a shared network. On a home network holding only the user's own
machines, S1 to S4 need somebody already inside it.

## S1 - A macro does not check who its coordinator is

**Critical on a shared network. Read, and the switch itself is in the
logs.**

The coordinator broadcasts a beacon in clear every two seconds. It carries
a fingerprint of the secret and a term. A macro that hears its fingerprint
with a higher term leaves its coordinator and connects to the sender.

So any machine on the network can copy the fingerprint from the air, send
it back with a higher term, and receive every macro of the fleet. Each one
says HELLO **with the secret in clear**, then obeys:

- `GOTO`: which field to farm;
- `MOVE`: Roblox is closed and joins the server it is told;
- `ROW` and `SERVER`: written to disk, with any version, so the real
  configuration loses to it from then on;
- `BYE final=1`: the macro leaves the fleet until it is set up again.

`f4446d1` took away the two worst uses of a `SERVER` frame. The cause is
untouched.

Proposed: both ends prove they hold the secret without sending it. The
coordinator sends a random number, the macro answers with a keyed hash of
it, and the other way round (HMAC-SHA-256, which Windows provides). A macro
that is not answered correctly obeys nothing.

## S2 - The secret crosses the network in clear

**High on a shared network. Read.** In every HELLO, and in the BOUND that
answers a join. S1's proposal removes the first. The second needs S4's.

## S3 - The beacon gives away most of the secret

**Medium. Reasoned, not run.** The secret is ten characters out of 31,
about 50 bits. The fingerprint is a 32-bit FNV-1a hash of it, sent to
everybody. Each step of that hash can be undone, so the secrets matching a
fingerprint can be listed quickly: about 190 000 remain. The coordinator
puts no limit on wrong secrets.

Proposed: the beacon carries the fleet's identity, which is not secret,
instead of anything derived from the secret.

## S4 - An open door admits anybody

**Medium. Read.** For up to five minutes after **Accept new macros**, any
machine that asks is given a row and the secret. A join that names an
existing account's username lands on that account's row and replaces its
name and role.

Proposed: the host shows a short code, the joiner types it, and the secret
is only handed over to a joiner that knew it.

## S5 - The coordinator listens on every network

**Medium. Read.** Even when every macro is on one PC, the port is open to
the whole network, and to the Internet if it is forwarded.

Proposed: a fleet says whether it spans several PCs. If not, it listens on
this PC only and sends no beacon, and none of S1 to S4 can be reached.

## Smaller

- **S6.** Any macro of the fleet may rewrite the roster and the servers.
  That is the user's choice; it means one compromised member is all of them.
- **S7.** A connection that never says HELLO is kept open for ever, and
  there is no limit on how many. Slow memory growth, from outside.
- **S8.** The secret is on the coordinator's command line, where any
  program of the same Windows user can read it, and in `nm_config.ini` in
  clear, as Natro's Discord token already is.

## What is fine

- No secret is in the repository or in its history.
- The branch adds no network call other than the fleet's own sockets and
  the update scripts, which fetch over HTTPS from the fork's repository.
- The fleet's logs hold no secret.

# Open: the fleet splits in two

**This is what cost the 27 hours above. Logs for E1, E3 and E4; read for
E2 and E5.**

Five faults, each small, that only do damage together:

- **E1.** After starting a coordinator, a macro connects to the address in
  `ext_fleetPrefer` before its own. That address is set whenever a higher
  term is heard and is never cleared. So the macro that has just taken over
  goes to the coordinator it replaced.
- **E2.** A coordinator on a lower term is half obeyed. Its heartbeat is
  ignored, but every other frame counts as a sign of life and its orders
  are followed. A macro can stay on it for ever.
- **E3.** The term is not kept across a restart. The host comes back at
  term 1 while the rest of the fleet remembers 6.
- **E4.** The host cannot take its job back while a coordinator it started
  earlier is still running, and says nothing. That lasts until the old one
  gives up, five minutes later: 20:57 to 21:02 on 11 November. On 2 and 3
  November, under an earlier build, the host started a coordinator every
  five minutes: 246 "Starting: Fleet coordinator" statuses.
- **E5.** A host that moves to a higher term leaves its own coordinator
  running and beaconing.

Proposed, as one change: keep the highest term seen in `nm_config.ini`;
leave a coordinator whose term is lower than one already seen; try this
PC's own coordinator first after starting it; stop one's own coordinator
when leaving it for a higher term. It needs a harness that runs the
macro's side of the fleet in the VM, three at a time, which does not exist
yet: the macro's side has no test at all today.

Until then, the one arrangement the logs show working is the one where
nothing restarts: start the main first, the alts after, and do not restart
the main's macro while the alts run.

# Open: guid hop

Never run, and switched off in every log. Read only.

- **G1.** With the hop on, an account whose remembered server is not the
  one it belongs in has its Roblox closed and rejoined as soon as it
  connects. That is the rule as designed; it will surprise somebody who
  joined the right server by hand.
- **G2.** A guid at its threshold waits at the hive and presses nothing.
  Roblox disconnects a player idle for twenty minutes. To check in the
  game: whether that happens, and whether the charge survives it.
- **G3.** A guid waits for a seat without limit. The seats counted are the
  fleet's own accounts: a player from outside is not seen. A capacity set
  one too high leaves every guid waiting, with no warning.
- **G4.** The charge reader refuses 3 labelled timers in 32. A charge not
  read counts as not ready, which fails safe.

# Open: stock Natro and the extensions

Skimmed. With every extension off:

- **B1.** The sticker stack trip no longer converts before leaving, and
  tries five times instead of two (`01e8c56`).
- **B2.** Pressing the blue booster now starts the boost's fifteen minutes
  at the press, whether or not a boosted field is then found.

With extensions on, from the logs:

- **B3.** Mondo interrupt on, action Kill: the main reaches the chick about
  17 s after the hour, before anything has hit it. Natro takes an untouched
  bar for a planter, resets and walks back: 26 wasted trips for 21 kills.
- **B4.** "Hive not recognised by camera": once in 197 resets on that
  install. The capture shows why that once: the square that is sampled
  holds the avatar and a white, decorated hive floor (h184 s9 v78), not
  honeycomb. It does not explain an install where it happens every time.

# What the user needs to decide

1. S1 and S2: mutual proof of the secret. Changes the protocol; an older
   macro and a newer coordinator would not talk.
2. S5: a "one PC" setting, which is the cheapest protection there is.
3. E1 to E5, with the harness first.
4. B1 and B2: keep, or put behind their switches.
