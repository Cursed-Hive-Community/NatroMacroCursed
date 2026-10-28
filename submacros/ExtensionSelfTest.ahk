#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon
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
#Include "%A_ScriptDir%\extensions\boostlease.ahk"
#Include "%A_ScriptDir%\extensions\interrupts.ahk"

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
