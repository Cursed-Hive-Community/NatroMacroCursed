#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon

;A runtime error fails the test rather than hanging it: over SSH there is no
;desktop for AutoHotkey's error dialog, so the process waited for ever while
;the runner timed out and left it behind - one did, for ten minutes.
OnError(SelfTestError)
#Warn All, Off

;The decisions the extensions make, checked against a table of values.
;
;	.\submacros\AutoHotkey64.exe /script .\submacros\ExtensionSelfTest.ahk
;
;Every feature in extensions\ comes down to a handful of windows in time: renew
;the boost in the last thirty seconds, press glitter when the booster is ten to
;eleven minutes away, leave for Mondo at :59, wait fifteen seconds after a
;failed sticker. Those numbers are the whole of the behaviour, and until this
;file they could be checked only by boosting a field and watching for a quarter
;of an hour - so in practice they were not checked at all.
;
;A window that is wrong by one second is the kind of fault that never announces
;itself. It costs a boost an hour, or sends the macro on a trip every five
;seconds for a quarter of an hour, and looks like bad luck either way. Every
;edge below therefore has three rows: one outside, one exactly on it, and one
;inside.
;
;This runs in well under a second. There is no socket, no sleep and no clock
;read: the functions it calls are the ones that were deliberately separated
;from the state they used to read, so they take their numbers as arguments.
;
;It is not a test of the features. It is a test of their arithmetic, which is
;the part a person cannot check by looking.
;
;The helpers are not called Is or Win: Is is a reserved word in AutoHotkey and
;Win collides with nothing today but reads like the twenty functions that start
;with it. nm-check.py catches neither - only /Validate does.

#Include "%A_ScriptDir%\..\lib"
#Include "nowUnix.ahk"
#Include "FleetHop.ahk"
#Include "FleetProtocol.ahk"
#Include "FleetRoster.ahk"
#Include "FleetServers.ahk"
#Include "%A_ScriptDir%\extensions\boostlease.ahk"
#Include "%A_ScriptDir%\extensions\interrupts.ahk"
#Include "%A_ScriptDir%\extensions\blender.ahk"
#Include "%A_ScriptDir%\extensions\guidshots.ahk"

;The extensions call into Natro for the half of their work that moves the
;character about. None of that is reached from here, but AutoHotkey resolves
;every call at load time, so the names have to exist.
nm_setStatus(*) {
}
nm_updateAction(*) {
}
nm_Reset(*) {
}
nm_gotoField(*) {
}
nm_findHiveSlot(*) {
}
nm_StickerStack(*) {
}
nm_endWalk(*) {
}
nm_setShiftLock(*) {
}
nm_walkFrom(*) {
}
nm_fieldBoostGlitter(*) {
}
nm_HealthDetection(*) {
	return []
}
nm_autoFieldBoost(*) {
}
nm_NightInterrupt(*) {
	return 0
}
Gdip_BitmapFromScreen(*) {
	return 0
}
Gdip_SaveBitmapToFile(*) {
}
Gdip_DisposeImage(*) {
}
Send_WM_COPYDATA(*) {
}

lines := [], failed := 0

;--- the lease window -------------------------------------------------------
;
;900 seconds of boost, and opens says how many of its last seconds the window
;covers. The upper edge is exclusive on purpose: at 900 the lease is over and
;renewing would buy fifteen minutes from now rather than extending anything.
Lease(age, opens, want, what) {
	Expect(ext_boostLeaseWindowAt(age, opens), want, what)
}
Lease(869, 30, 0, "gathering: one second before the window")
Lease(870, 30, 1, "gathering: exactly on the edge")
Lease(899, 30, 1, "gathering: the last second of the lease")
Lease(900, 30, 0, "gathering: the lease is over")
Lease(839, 60, 0, "converting: one second before the window")
Lease(840, 60, 1, "converting: exactly on the edge")
Lease(899, 60, 1, "converting: the last second")
;a full bag is the last chance to glitter before walking off to convert, so
;its window opens ten seconds before the converting one - DefinetlyNotRay's 830
Lease(829, 70, 0, "backpack full: one second before the window")
Lease(830, 70, 1, "backpack full: exactly on the edge")
Lease(794, 105, 0, "mondo trip: one second before the window")
Lease(795, 105, 1, "mondo trip: exactly on the edge")
;a lease that never started reads as age zero, and must not look like a window
Lease(0, 60, 0, "no lease at all")

;--- pre-glitter ------------------------------------------------------------
;
;Ten to eleven minutes before the booster. Below ten it would still be running
;when the booster is pressed and the overlap is thrown away; above eleven it
;runs out before the booster arrives and the gap it was covering reopens.
PreG(untilBlue, sinceGlitter, want, what) {
	Expect(ext_preGlitterDueAt(untilBlue, sinceGlitter), want, what)
}
PreG(661, 1000, 0, "pre-glitter: more than eleven minutes to go")
PreG(660, 1000, 1, "pre-glitter: eleven minutes exactly")
PreG(601, 1000, 1, "pre-glitter: just over ten minutes")
PreG(600, 1000, 0, "pre-glitter: ten minutes, too late to be worth it")
;a glitter pressed inside the last fifteen minutes is still running, and a
;second one would throw away whatever is left of the first
PreG(630, 900, 0, "pre-glitter: a glitter from exactly fifteen minutes ago")
PreG(630, 901, 1, "pre-glitter: a glitter that has just run out")

;--- the blue booster -------------------------------------------------------
;
;2660 of the 2700 second cooldown, so the walk finishes as it comes up rather
;than the macro arriving and standing there. A measured value: a typo in it
;costs a boost an hour and never looks wrong.
Blue(sinceUse, want, what) {
	Expect(ext_blueBoosterDueAt(sinceUse), want, what)
}
Blue(2659, 0, "blue booster: one second early")
Blue(2660, 1, "blue booster: exactly on time")
Blue(5000, 1, "blue booster: long overdue")
;A trip that found no booster to press arrived early, and the cooldown ends
;within the minute. It is due again at once, so the next trip leaves straight
;away and lands on it - five minutes later it was six minutes late.
Blue(ext_blueBoosterRetryAge(), 1, "blue booster: a failed trip is retried at once")

;--- the boosted field ------------------------------------------------------
;
;A boost is farmed until it ends, and it ends fifteen minutes after whichever
;came last: the boost itself or the glitter that renewed it. start is when the
;boost was seen, zero for none.
Chase(start, glitter, now, want, what) {
	Expect(ext_boostChaseLiveAt(start, glitter, now), want, what)
}
Chase(0, 0, 1000, 0, "boosted field: nothing remembered")
Chase(1000, 0, 1899, 1, "boosted field: the last second of the boost")
Chase(1000, 0, 1900, 0, "boosted field: the boost is over")
;a glitter from before the boost is not a renewal of it
Chase(1000, 500, 1899, 1, "boosted field: an older glitter changes nothing")
Chase(1000, 500, 1900, 0, "boosted field: and does not stretch it")
Chase(1000, 1880, 2779, 1, "boosted field: renewed, the last second")
Chase(1000, 1880, 2780, 0, "boosted field: renewed, and now over")
;the field's box in the Boost tab, read by name - a lookup /Validate cannot
;check, because the name is only built when it runs
global PineTreeBoosterCheck := 0, BlueFlowerBoosterCheck := 1
Expect(ext_boostChaseBox("Pine Tree"), 0, "boosted field: an unticked field is not chased")
Expect(ext_boostChaseBox("Blue Flower"), 1, "boosted field: a ticked field is")
Expect(ext_boostChaseBox("Mountain Top"), 1, "boosted field: Mountain Top has no box and is")

;--- the sticker stack ------------------------------------------------------
;
;Past its timer, not within fifteen seconds of a failure, and never twice
;inside a minute. sinceFail is -1 for "nothing has ever failed".
Stick(sinceStack, timer, sinceFail, sinceUse, want, what) {
	Expect(ext_stickerStackDueAt(sinceStack, timer, sinceFail, sinceUse), want, what)
}
Stick(1800, 1800, -1, 9999, 0, "sticker: the timer is exactly up, not past")
Stick(1801, 1800, -1, 9999, 1, "sticker: one second past the timer")
Stick(9999, 1800, 14, 9999, 0, "sticker: a failure fourteen seconds ago")
Stick(9999, 1800, 15, 9999, 1, "sticker: a failure fifteen seconds ago")
Stick(9999, 1800, -1, 59, 0, "sticker: placed fifty-nine seconds ago")
Stick(9999, 1800, -1, 60, 1, "sticker: placed a minute ago")
;a macro that has never placed one reads as a very long time ago, which must
;not be mistaken for having just placed one
Stick(9999, 1800, -1, 99999, 1, "sticker: never placed one")

;--- mondo ------------------------------------------------------------------
;
;:59 to be standing on the spawn as it appears, :00 to :14 to catch up, and
;fifty-five minutes so one spawn is never claimed twice.
Mondo(utcMin, sinceBuff, want, what) {
	Expect(ext_mondoDueAt(utcMin, sinceBuff), want, what)
}
Mondo(58, 9999, 0, "mondo: :58, too early to leave")
Mondo(59, 9999, 1, "mondo: :59, the minute it leaves")
Mondo(0, 9999, 1, "mondo: the hour has just turned")
Mondo(14, 9999, 1, "mondo: the last minute of the catch-up window")
Mondo(15, 9999, 0, "mondo: :15, the spawn has been and gone")
Mondo(30, 9999, 0, "mondo: the middle of the hour")
Mondo(59, 3300, 0, "mondo: this spawn was claimed fifty-five minutes ago")
Mondo(59, 3301, 1, "mondo: the last one was long enough ago")

;--- the errands before mondo -----------------------------------------------
;
;From :55 to :00 the macro starts nothing long - no planter, quest or collect
;round - so it is free when the chick spawns rather than halfway across the map.
Pause(utcMin, want, what) {
	Expect(ext_mondoErrandsPausedAt(utcMin), want, what)
}
Pause(54, 0, "errands: :54, still time for one")
Pause(55, 1, "errands: :55, held for mondo")
Pause(59, 1, "errands: :59, held for mondo")
Pause(0, 1, "errands: :00, the spawn itself")
Pause(1, 0, "errands: :01, back to normal")

;--- the blender ------------------------------------------------------------
;
;Three slots taken in turn, each tried again only once its own wait is over.
;A slot with no wait is the stock behaviour: due at once after a craft, so the
;blender being busy is all that holds it back.
BlendLive(item, index, want, what) {
	Expect(ext_blenderSlotLive(item, index), want, what)
}
BlendLive("TropicalDrink", 1, 1, "blender: one repeat left")
BlendLive("TropicalDrink", 0, 0, "blender: no repeat left")
BlendLive("TropicalDrink", "Infinite", 1, "blender: infinite")
BlendLive("TropicalDrink", "∞", 1, "blender: infinite as the remote writes it")
BlendLive("None", "Infinite", 0, "blender: an empty slot")
BlendLive("", 5, 0, "blender: a slot never set")

BlendTurn(rot, live, next, now, want, what) {
	ExpectEq(ext_blenderPickAt(rot, live, next, now), want, what)
}
BlendTurn(1, [1, 1, 0], [0, 0, 0], 100, 1, "blender pick: the slot whose turn it is")
BlendTurn(2, [1, 1, 0], [0, 0, 0], 100, 2, "blender pick: the turn has moved on")
BlendTurn(3, [1, 1, 0], [0, 0, 0], 100, 1, "blender pick: an empty slot is passed over")
BlendTurn(1, [1, 1, 0], [101, 0, 0], 100, 2, "blender pick: a slot still waiting lets the next go")
BlendTurn(1, [1, 1, 0], [100, 0, 0], 100, 1, "blender pick: a wait that ends now is over")
BlendTurn(1, [1, 0, 0], [101, 0, 0], 100, 0, "blender pick: nothing due, no trip")
BlendTurn(1, [0, 0, 0], [0, 0, 0], 100, 0, "blender pick: nothing live")

BlendNext(waitMin, amount, crafted, want, what) {
	ExpectEq(ext_blenderNextAt(1000, waitMin, amount, crafted), want, what)
}
BlendNext(0, 20, 1, 1000, "blender: no wait, due again at once after a craft")
BlendNext(110, 20, 1, 7600, "blender: a craft waits its 110 minutes")
BlendNext(110, 20, 0, 7600, "blender: so does a skip")
;without a wait, a skip waits as long as the batch would have taken, not one
;collect round
BlendNext(0, 20, 0, 7000, "blender: a skip with no wait, twenty items later")

BlendBusy(tries, want, what) {
	ExpectEq(ext_blenderBusyRetry(tries), want, what)
}
BlendBusy(0, 300, "blender busy: five minutes the first time")
BlendBusy(1, 600, "blender busy: ten the second")
BlendBusy(2, 1200, "blender busy: twenty the third")
BlendBusy(3, 1800, "blender busy: thirty from then on")
BlendBusy(10, 1800, "blender busy: and never more")

BlendVisit(busyUntil, pick, claim, forced, want, what) {
	Expect(ext_blenderVisitAt(1000, busyUntil, pick, claim, forced), want, what)
}
BlendVisit(1000, 1, 0, 0, 0, "blender visit: the craft ends this second, not yet")
BlendVisit(999, 1, 0, 0, 1, "blender visit: free and a slot due")
BlendVisit(999, 0, 0, 0, 0, "blender visit: free but nothing to do")
;the last batch of a run used to stay in the blender for good
BlendVisit(999, 0, 1, 0, 1, "blender visit: free and a batch to claim")
BlendVisit(5000, 0, 0, 1, 1, "blender visit: Ready forces it")

;the timers window's countdowns: slot 1 crafting until 1000, slot 2 due at
;once, slot 3 waiting until 5000
plan := ext_blenderPlanAfter(1, 1000, [1, 1, 1], [0, 0, 5000], [2, 4, 1])
ExpectEq(plan[1], 1000, "blender plan: the crafting slot keeps its end")
ExpectEq(plan[2], 2200, "blender plan: the next starts when the blender frees")
ExpectEq(plan[3], 5300, "blender plan: a slot still waiting starts when it ends")
plan := ext_blenderPlanAfter(3, 1000, [1, 0, 1], [0, 0, 0], [2, 4, 1])
ExpectEq(plan[1], 1600, "blender plan: it wraps round from the third slot")
ExpectEq(plan[2], 0, "blender plan: an empty slot has none")

ExpectEq(ext_blenderLabel(20, "Infinite", 0), "(20) [∞]", "blender label: as stock Natro writes it")
ExpectEq(ext_blenderLabel(20, 3, 110), "(20) [3] 110m", "blender label: with a wait")

;--- the guiding star screenshots --------------------------------------------
;
;The landing, then ten moments inside the five minute cooldown, in order, and
;not the same ten for the next star: the point is timers not seen yet.
shots := ext_guidShotTimes(1000), again := ext_guidShotTimes(1000), inside := 1, sorted := 1, same := 1
loop 10 {
	inside &= (shots[A_Index + 1] >= 1005 && shots[A_Index + 1] <= 1295)
	sorted &= (shots[A_Index + 1] >= shots[A_Index])
	same &= (shots[A_Index + 1] = again[A_Index + 1])
}
ExpectEq(shots.Length, 11, "star shots: eleven in all")
ExpectEq(shots[1], 1000, "star shots: the first at the landing")
Expect(inside, 1, "star shots: the rest inside the cooldown")
Expect(sorted, 1, "star shots: in order")
Expect(same, 0, "star shots: drawn again for the next star")

;--- the guid hop -------------------------------------------------------------
;
;Who sits in the main, as whole situations: six seats, a threshold of 200, Pine
;Tree the one blue field, the time 1000. Each answer is the moves in the order
;they are made, row>server.
HopPeer(row, role, server, charge := 0, star := "", left := 0, since := 0) {
	return {row: row, role: role, online: 1, present: 1, server: server, charge: charge
		, guidingField: star, guidingUntil: left ? 1000 + left : 0, waitSince: since}
}
HopFleet(list*) {
	m := Map()
	for p in list
		m[p.row] := p
	return m
}
HopMoves(fleet, atMondo := 0, state := 0) {
	if !state
		state := {pending: Map(), yielded: Map()}
	opt := {now: 1000, capacity: 6, threshold: 200, blue: fleet_HopBlue("Pine Tree"), mondo: atMondo}
	s := ""
	for o in fleet_HopPlan(fleet, opt, state)
		s .= (s = "" ? "" : " ") o.row ">" o.to
	return s
}
;A full main: the main, a tad, a fuzzy, two guids ready to fire and one whose
;star is running on Pine Tree. A guid is in the main for nothing else.
FullMain(extra*) {
	f := HopFleet(HopPeer(1, "main", "main"), HopPeer(2, "tad", "main"), HopPeer(3, "fuzzy", "main")
		, HopPeer(4, "guid", "main", 205), HopPeer(5, "guid", "main", 230), HopPeer(6, "guid", "main", 0, "Pine Tree", 300))
	for p in extra
		f[p.row] := p
	return f
}
;An account told to leave says it is out the moment it has closed Roblox: in
;none of the fleet's servers, until it lands in the reserve.
HopOut(f, rows*) {
	for r in rows
		f[r].server := ""
}
ExpectEq(HopMoves(FullMain(HopPeer(7, "guid", "reserve", 210))), ""
	, "hop: a ready guid waits for a free seat - nobody is pushed out for it")
ExpectEq(HopMoves(HopFleet(HopPeer(1, "main", "main"), HopPeer(4, "guid", "reserve", 150))), ""
	, "hop: a guid still charging never takes a free seat - the main holds as few as it can")
ExpectEq(HopMoves(HopFleet(HopPeer(1, "main", "main"), HopPeer(4, "guid", "main", 50))), "4>reserve"
	, "hop: a guid in the main that is not ready to fire goes back")
;the leave and the join go out together: Roblox queues a player joining a full
;private server and lets them in as soon as somebody leaves
f := HopFleet(HopPeer(1, "main", "main"), HopPeer(4, "guid", "main", 0, "Rose", 300), HopPeer(7, "guid", "reserve", 210))
ExpectEq(HopMoves(f), "4>reserve 7>main", "hop: a star on Rose is no use - out at once, and a ready guid in")
f := HopFleet(HopPeer(1, "main", "main"), HopPeer(4, "guid", "reserve", 210, "Rose", 300))
ExpectEq(HopMoves(f), "", "hop: and that guid is not asked back while its star counts down, even read as ready")
f := HopFleet(HopPeer(1, "main", "main"), HopPeer(4, "guid", "main", 30, "Pine Tree", -100))
ExpectEq(HopMoves(f), "4>reserve", "hop: a blue star over, the guid goes back")
f := HopFleet(HopPeer(1, "main", "main"), HopPeer(4, "guid", "main", 220, "Pine Tree", -100))
ExpectEq(HopMoves(f), "", "hop: unless it is ready to fire again")
f := HopFleet(HopPeer(1, "main", "main"), HopPeer(4, "guid", "main", 0, "Pine Tree", 300))
ExpectEq(HopMoves(f), "", "hop: a blue star running keeps its guid, whatever its charge")
f := FullMain(HopPeer(7, "guid", "reserve", 210, , , 50), HopPeer(8, "atk", "reserve"))
ExpectEq(HopMoves(f, 1), "2>reserve 8>main", "hop: at Mondo the tad makes room for the atk, before the ready guid")
f := FullMain(HopPeer(8, "atk", "reserve")), f[3].role := "tad"
ExpectEq(HopMoves(f, 1), "2>reserve 8>main", "hop: of two tads, the first in the roster")
f := FullMain(HopPeer(8, "atk", "reserve")), f[2].role := "fuzzy"
ExpectEq(HopMoves(f, 1), "2>reserve 8>main", "hop: no tad, a fuzzy")
f := HopFleet(HopPeer(1, "main", "main"), HopPeer(2, "guid", "main", 0, "Pine Tree", 300), HopPeer(3, "guid", "main", 210)
	, HopPeer(4, "guid", "main", 205), HopPeer(5, "guid", "main", 0, "Pine Tree", 300), HopPeer(6, "guid", "main", 230), HopPeer(8, "atk", "reserve"))
ExpectEq(HopMoves(f, 1), "4>reserve 8>main", "hop: no resident, the guid with least and no star")
st := {pending: Map(), yielded: Map(2, 1)}
;the main full again: the atk in the tad's seat
f := FullMain(HopPeer(7, "guid", "reserve", 210), HopPeer(8, "atk", "main")), f[2].server := "reserve"
ExpectEq(HopMoves(f, 0, st), "8>reserve 2>main", "hop: after Mondo the atk goes and the tad is back before the ready guid")
ExpectEq(st.yielded.Count, 0, "hop: and the tad's seat is no longer owed")
f := HopFleet(HopPeer(1, "main", "main"), HopPeer(2, "tad", "reserve"), HopPeer(4, "guid", "reserve", 210))
ExpectEq(HopMoves(f), "2>main 4>main", "hop: a tad restarted into the reserve is let back in before a guid")
ExpectEq(HopMoves(f, 1), "2>main 4>main", "hop: at Mondo too - only a resident that gave its seat to the atk waits")
f := HopFleet(HopPeer(1, "main", "main"), HopPeer(2, "tad", "main"), HopPeer(4, "guid", "reserve", 120)
	, HopPeer(5, "guid", "reserve", 205, , , 50), HopPeer(6, "guid", "reserve", 210, , , 40))
ExpectEq(HopMoves(f), "6>main 5>main", "hop: free seats go to ready guids, the longest waiting first, and to no other")
f := FullMain(HopPeer(7, "guid", "reserve", 210)), f[6].online := 0, f[5].server := "reserve"
ExpectEq(HopMoves(f), "5>main", "hop: a macro gone quiet still holds its seat, and is given no order")
;the main's link changed by hand: whoever is left in the old server is in none
;of the fleet's, and is brought over like one in the reserve
f := HopFleet(HopPeer(1, "main", ""), HopPeer(2, "tad", ""), HopPeer(4, "guid", "", 210), HopPeer(5, "guid", "main", 220))
ExpectEq(HopMoves(f), "1>main 2>main 4>main", "hop: accounts left in a server the fleet no longer has are brought over")
f := HopFleet(HopPeer(1, "main", "main"), HopPeer(4, "guid", "main", 50)), st := {pending: Map(), yielded: Map()}
HopMoves(f, 0, st)
ExpectEq(HopMoves(f, 0, st), "", "hop: a move ordered is not ordered again while it happens")
HopOut(f, 4)
ExpectEq(HopMoves(f, 0, st), "", "hop: nor contradicted - the one leaving is not asked back mid-move")
f := HopFleet(HopPeer(1, "main", "reserve"), HopPeer(2, "tad", "main"), HopPeer(7, "guid", "reserve", 210))
ExpectEq(HopMoves(f), "1>main 7>main", "hop: the main is always let back in")
;the notice images name a field PineTree, the windows Pine Tree
f := FullMain(), f[6].guidingField := "PineTree"
ExpectEq(HopMoves(f), "", "hop: PineTree from the notice is the blue Pine Tree")
ExpectEq(fleet_HopBlue(" Pine Tree|Rose||").Count, 2, "hop: blue fields read from Pine Tree|Rose")
;where an account is, from the link it joined: the coordinator seats only the
;accounts that can say
A32 := "0123456789abcdef0123456789abcdef", B32 := "fedcba9876543210fedcba9876543210"
hopServers := Map(1, servers_Blank(1, "main"), 2, servers_Blank(2))
hopServers[1].link := "https://www.roblox.com/games/1537690962?privateServerLinkCode=" A32
hopServers[2].link := "https://www.roblox.com/share?code=" B32 "&type=Server"
ExpectEq(servers_KindOf(hopServers, "https://www.roblox.com/games/1537690962/Bee-Swarm?privateServerLinkCode=" A32 "&x=1"), "main"
	, "hop: the main's link, pasted another way")
ExpectEq(servers_KindOf(hopServers, "https://www.roblox.com/share?code=" B32 "&type=Server"), "reserve", "hop: a share link")
ExpectEq(servers_KindOf(hopServers, "https://www.roblox.com/games/1537690962?privateServerLinkCode=" B32), "", "hop: some other server")
ExpectEq(servers_KindOf(hopServers, ""), "", "hop: a public server")
ExpectEq(servers_LinkParts("https://www.roblox.com/share?code=" B32 "&type=Server").type, "ShareCode", "hop: read as Natro reads it")
;A server link reaches a macro over the network and ends up on a command line:
;Natro's browser reconnect puts the whole link among the browser's arguments,
;and the deeplink puts the code in a URL it runs. So a code is letters and
;digits, and the link a macro joins is rebuilt from the code alone.
ExpectEq(servers_LinkParts('https://evil.example/?privateServerLinkCode=a" --flag="bcdefghijklmnopqrstuv').type, ""
	, "link: a code with a quote or a space in it is not a code")
ExpectEq(servers_CanonicalLink('https://evil.example/x?privateServerLinkCode=' A32 '&y=" --flag')
	, "https://www.roblox.com/games/1537690962?privateServerLinkCode=" A32, "link: only the code is kept of a link from the wire")
ExpectEq(servers_CanonicalLink("https://www.roblox.com/share?code=" B32 "&type=Server")
	, "https://www.roblox.com/share?code=" B32 "&type=Server", "link: a share link comes back as itself")
ExpectEq(servers_CanonicalLink("https://example.com/"), "", "link: no code, no link")
ExpectEq(servers_KindOf(hopServers, servers_CanonicalLink(hopServers[1].link "&x=1")), "main", "link: the rebuilt link is still the same server")
;and a value read off the wire is one line: the server a macro is sent to is
;written to nm_config.ini, where a second line is a setting of its own
ExpectEq(InStr(fleet_Field(fleet_Parse("SERVER link=a%0D%0AKey=1"), "link"), "`n")
	+ InStr(fleet_Field(fleet_Parse("SERVER link=a%0D%0AKey=1"), "link"), "`r"), 0
	, "wire: a value cannot carry a new line")
ExpectEq(fleet_Field(fleet_Parse("ROW name=fuzzy%201 user=A%25b"), "name") "/" fleet_Field(fleet_Parse("ROW name=fuzzy%201 user=A%25b"), "user")
	, "fuzzy 1/A%b", "wire: a space and a percent still survive")

Report()
return

Expect(got, want, what) {
	global lines, failed

	if (!!got = !!want) {
		lines.Push("PASS  " what)
		return
	}
	failed++
	lines.Push("FAIL  " what " - wanted " (want ? "yes" : "no")
		. ", got " (got ? "yes" : "no"))
}
;the blender's numbers are times and slots, not yes or no
ExpectEq(got, want, what) {
	global lines, failed

	if (got == want) {
		lines.Push("PASS  " what)
		return
	}
	failed++
	lines.Push("FAIL  " what " - wanted " want ", got " got)
}

Report() {
	global lines, failed
	local text := "", v, path

	for _, v in lines
		text .= v "`r`n"
	text := "Extension decisions on AutoHotkey " A_AhkVersion "`r`n`r`n" text
		. "`r`n" lines.Length " checks, " failed " failed`r`n"
	path := A_ScriptDir "\..\settings\extension_diag.txt"
	try FileDelete path
	try FileAppend text, path, "UTF-8"
	;headless over SSH: a verdict on standard output, an exit code, no window
	if ObjHasValue(A_Args, "/quiet") {
		FileAppend (failed ? "FAIL" : "PASS") "`n", "*"
		ExitApp failed ? 1 : 0
	}
	if !failed {
		MsgBox "Every extension decision is right.`n`n" lines.Length " checks."
			, "Extension self-test", 0x40040
		ExitApp 0
	}
	try A_Clipboard := text
	MsgBox failed " of " lines.Length " checks failed.`n`nThe list is on the "
		. "clipboard and in settings\extension_diag.txt.", "Extension self-test", 0x40010
	ExitApp 1
}

ObjHasValue(arr, needle) {
	for _, v in arr
		if (v = needle)
			return 1
	return 0
}

SelfTestError(e, *) {
	try FileAppend "ERROR: " e.Message " - " e.What " (line " e.Line ")`r`n", A_ScriptDir "\..\settings\extension_diag.txt", "UTF-8"
	for a in A_Args
		if (a = "/quiet")
			FileAppend "FAIL`n", "*"
	ExitApp 1
}
