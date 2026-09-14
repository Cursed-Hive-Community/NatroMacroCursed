;Gather interrupts - breaking off what the macro is doing for something worth
;more than finishing it.
;
;Natro's own interrupts are checked between gathering trips. That is fine for
;anything on a loose schedule, and useless for anything on a clock: a blue
;booster that came off cooldown two minutes into a twenty minute trip is worth
;nothing until someone goes and presses it.

;The blue field booster has a forty-five minute cooldown and is the strongest
;boost on a schedule, so the macro leaves for it the moment the cooldown is
;nearly up.
;
;Nearly, rather than exactly: the walk there takes longer than the forty seconds
;this leaves early, so arriving as it comes off cooldown beats arriving and
;standing about. 2660 is DefinetlyNotRay's measured value.
ext_blueBoosterReady() {
	global BlueBoosterInterruptCheck, LastBlueBoostUse

	if !BlueBoosterInterruptCheck
		return 0
	return ((nowUnix() - ((LastBlueBoostUse = "") ? 0 : LastBlueBoostUse)) >= 2660)
}
;The booster was pressed. Start the clock again, and start a fresh boost lease
;with it - this is a new boost, so it is owed a renewal of its own.
ext_blueBoosterUsed() {
	global LastBlueBoostUse, GatherFieldBoostedStart, ext_boostLeaseRenewed, PFieldBoostExtend

	LastBlueBoostUse := nowUnix()
	GatherFieldBoostedStart := LastBlueBoostUse
	;the wait a pre-glitter was covering is over
	ext_preGlitterClear()
	ext_boostLeaseRenewed := 0, PFieldBoostExtend := 0
	IniWrite LastBlueBoostUse, "settings\nm_config.ini", "Boost", "LastBlueBoostUse"
	return 1
}
;The trip never reached the booster. Worth retrying, but not at once: a route
;that fails once tends to fail again, and retrying on the spot would spend the
;night walking. Five minutes, then try again.
ext_blueBoosterFailed() {
	global LastBlueBoostUse

	LastBlueBoostUse := nowUnix() - 2660 + 300
	IniWrite LastBlueBoostUse, "settings\nm_config.ini", "Boost", "LastBlueBoostUse"
	return 1
}
;A sticker stack runs on a timer, and what it is worth is whatever gets
;converted underneath it. Natro offers one only in nm_Boost, between gathering
;trips, so a stack that came due early in a trip waits out the rest of it and
;the stack is spent on that much less honey.
;
;This breaks off when it comes due, places the stack, and goes to the hive to
;convert under it - the second half being the point of the first.
ext_stickerStackDue() {
	global StickerStackCheck, StickerStackInterruptCheck, LastStickerStack, StickerStackTimer
	global ext_stickerStackFailedAt, ext_stickerStackUsedAt

	if (!StickerStackCheck || !StickerStackInterruptCheck)
		return 0
	if ((nowUnix() - LastStickerStack) <= StickerStackTimer)
		return 0
	;a placement that failed is worth retrying, but not on the next tick
	if (ext_stickerStackFailedAt && ((nowUnix() - ext_stickerStackFailedAt) < 15))
		return 0
	;and never twice inside a minute, whatever the timers say
	return ((nowUnix() - ext_stickerStackUsedAt) >= 60)
}
;nm_StickerStack returns nothing, but it records the moment it succeeds, so
;that is what tells a placement from a failure here. Reading the clock it
;already keeps leaves the shared routine untouched.
;
;handling guards against re-entry: the reset below can pass through code that
;checks interrupts again, and a stack placed twice is a stack wasted.
ext_stickerStackInterrupt(convertAfter := 1) {
	global LastStickerStack, ext_stickerStackFailedAt, ext_stickerStackUsedAt
	static handling := 0
	local before

	if (handling || !ext_stickerStackDue())
		return 0
	handling := 1
	nm_setStatus("Priority", "Sticker Stack Ready")
	before := LastStickerStack
	nm_StickerStack()
	if (LastStickerStack = before) {
		ext_stickerStackFailedAt := nowUnix()
		nm_setStatus("Failed", "Sticker Stack")
		handling := 0
		return 1
	}
	ext_stickerStackFailedAt := 0, ext_stickerStackUsedAt := nowUnix()
	nm_setStatus("Traveling", convertAfter ? "Hive, to convert under the stack" : "Hive")
	nm_Reset(2, 2000, 0, 1)
	if (convertAfter && !nm_findHiveSlot())
		nm_setStatus("Failed", "Could not confirm the hive after the stack")
	handling := 0
	return 1
}
;Mondo Chick spawns at the top of the hour at Mountain Top, and the buff is
;worth more than the few minutes of gathering it costs. Natro goes for it only
;once the hour has already turned, only while the macro is not boosted, and only
;when it next looks between trips - so it regularly arrives to find the spawn
;gone, or does not go at all.
;
;This leaves at :59, a minute early, so the macro is standing at Mountain Top as
;the chick appears. Being boosted no longer rules the trip out: the boost is
;renewed before leaving instead.
;
;:00 to :14 is a catch-up window. The macro can easily be mid-pattern with a
;full backpack at :59, and arriving late still beats not going.
;
;Buff only. Killing Mondo is a different job with its own routine, and Natro
;already handles it.
ext_mondoDue() {
	global MondoInterruptCheck, MondoBuffCheck, MondoAction, LastMondoBuff
	local utcMin

	if (!MondoInterruptCheck || (MondoBuffCheck != 1) || (MondoAction != "Buff"))
		return 0
	utcMin := FormatTime(A_NowUTC, "m") + 0
	if !((utcMin = 59) || (utcMin <= 14))
		return 0
	;fifty-five minutes, so one spawn is never claimed twice
	return ((nowUnix() - LastMondoBuff) > 3300)
}
;A chick nobody has touched reads exactly 100, so the spawn counts as found once
;a bar is showing below full - which is what a fight underway looks like, and
;the fight is what the macro came to stand next to.
ext_mondoSpawned() {
	local bar

	for bar in nm_HealthDetection()
		if (bar != 100.00)
			return 1
	return 0
}
;handling guards re-entry: the hive return below passes back through code that
;checks interrupts, and a second trip would arrive at an empty Mountain Top.
ext_mondoInterrupt() {
	global youDied, MondoSecs, CurrentField, LastMondoBuff
	global AFBrollingDice, AFBuseGlitter, AFBuseBooster
	static handling := 0
	local found

	if (handling || !ext_mondoDue())
		return 0
	handling := 1
	nm_updateAction("Mondo Interrupt")
	;the round trip runs to a few minutes, so a lease in its last 105 seconds
	;would not survive it - renew now rather than come back to nothing
	if ext_boostLeaseNearEnd(105)
		ext_boostLeaseRenew(CurrentField, "Mondo Interrupt")
	nm_setStatus("Traveling", "Mondo Interrupt`nMountain Top")
	nm_Reset(0, 2000, 0)
	nm_gotoField("Mountain Top")

	;arrived before the hour turned, which is the point - wait it out on the spot
	while ((FormatTime(A_NowUTC, "m") + 0) = 59) {
		if youDied
			break
		Sleep 200
	}

	nm_setStatus("Searching", "Mondo Chick")
	found := 0
	;a minute of looking, or until the clock says the spawn has been and gone
	Loop 240 {
		if ext_mondoSpawned() {
			found := 1
			break
		}
		if ((FormatTime(A_NowUTC, "m") + 0) > 1)
			break
		Sleep 250
	}
	if found {
		nm_setStatus("Attacking", "Mondo Chick")
		Loop MondoSecs {
			nm_autoFieldBoost(CurrentField)
			if (youDied || AFBrollingDice || AFBuseGlitter || AFBuseBooster || nm_NightInterrupt())
				break
			Sleep 1000
		}
	} else
		nm_setStatus("Failed", "Mondo Chick not found")
	;found or not, this hour's attempt is spent - otherwise the catch-up window
	;would send the macro back every few seconds until :14
	LastMondoBuff := nowUnix()
	IniWrite LastMondoBuff, "settings\nm_config.ini", "Collect", "LastMondoBuff"
	nm_setStatus("Traveling", "Hive, after Mondo")
	nm_Reset(2, 2000, 0, 1)
	nm_findHiveSlot()
	handling := 0
	return 1
}
