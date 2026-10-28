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
	return ext_blueBoosterDueAt(nowUnix() - ((LastBlueBoostUse = "") ? 0 : LastBlueBoostUse))
}

;Forty seconds before the forty-five minute cooldown is up, which is roughly
;how long the walk takes. Its own function so the number is asserted rather
;than trusted - 2660 is a measured value and a typo in it would cost a boost an
;hour without ever looking wrong.
ext_blueBoosterDueAt(sinceUse) {
	return (sinceUse >= 2660)
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
;The trip found no booster to press. Nearly always that is a trip which left
;early and arrived before the cooldown was up - which is what leaving forty
;seconds early does whenever the walk is quick - so the booster comes up within
;the minute and the next trip lands on it. So it is due again at once, which is
;DefinetlyNotRay's own repair: the next trip leaves straight away.
;
;This used to wait five minutes, on the theory that a route that fails once
;fails again. On a real install that made the booster six minutes late, and
;it threw away the real time of the last press doing so.
;
;Natro's own booster round is put back thirty minutes, as his is, so it does
;not set off for the same booster in between.
ext_blueBoosterFailed() {
	global LastBlueBoostUse, LastBlueBoost

	LastBlueBoostUse := nowUnix() - ext_blueBoosterRetryAge()
	IniWrite LastBlueBoostUse, "settings\nm_config.ini", "Boost", "LastBlueBoostUse"
	LastBlueBoost := nowUnix() - 900
	IniWrite LastBlueBoost, "settings\nm_config.ini", "Collect", "LastBlueBoost"
	return 1
}
;How long ago a failed trip says the booster was pressed: the whole cooldown,
;so it reads as due.
ext_blueBoosterRetryAge() {
	return 2700
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
	return ext_stickerStackDueAt(nowUnix() - LastStickerStack, StickerStackTimer
		, ext_stickerStackFailedAt ? (nowUnix() - ext_stickerStackFailedAt) : -1
		, nowUnix() - ext_stickerStackUsedAt)
}

;Three conditions, and all three have cost something when they were wrong.
;
;sinceFail is -1 when nothing has failed, rather than a large number: a macro
;that has never failed and one that failed an hour ago are the same thing here,
;and saying so with a sentinel beats inventing an age for an event that never
;happened.
ext_stickerStackDueAt(sinceStack, timer, sinceFail, sinceUse) {
	if (sinceStack <= timer)
		return 0
	;a placement that failed is worth retrying, but not on the next tick
	if ((sinceFail >= 0) && (sinceFail < 15))
		return 0
	;and never twice inside a minute, whatever the timers say
	return (sinceUse >= 60)
}
;The gather loop's question. A stack that comes due in the last minute of a
;boost lease waits for the renewal, so the glitter is pressed standing in the
;field rather than lost to the trip - DefinetlyNotRay's order.
ext_stickerStackGatherDue() {
	return ext_stickerStackDue() && !ext_boostLeaseNearEnd(60)
}
;nm_StickerStack records the moment it succeeds, so comparing that clock before
;and after tells a placement from a failure without asking it.
;
;Asked from three places, which is the point: between trips, from the field
;the moment it comes due, and all through a convert - a balloon convert runs
;ten minutes, and a stack that waited for the end of it was a stack spent on
;ten minutes less honey. resetBefore is 0 at the hive, where the trip can start
;from where the macro stands. A balloon convert that was broken off for it is
;picked up again afterwards rather than left half done.
;
;handling guards against re-entry: the reset below can pass through code that
;checks interrupts again, and a stack placed twice is a stack wasted.
ext_stickerStackInterrupt(convertAfter := 1, resetBefore := 1) {
	global LastStickerStack, ext_stickerStackFailedAt, ext_stickerStackUsedAt
	global state, objective, ConvertGatherFlag, AFBuseGlitter
	static handling := 0
	local before, resumeBalloon

	if (handling || !ext_stickerStackDue())
		return 0
	handling := 1
	resumeBalloon := (state = "Converting") && InStr(objective, "Balloon")
	;a glitter Auto Field Boost was about to press would run out while the
	;macro is away, so it goes first
	if AFBuseGlitter {
		nm_setStatus("Priority", "Boosting Field: Glitter")
		nm_fieldBoostGlitter()
	}
	nm_setStatus("Priority", "Sticker Stack Ready")
	before := LastStickerStack
	nm_StickerStack(resetBefore)
	if (LastStickerStack = before) {
		ext_stickerStackFailedAt := nowUnix()
		nm_setStatus("Failed", "Sticker Stack")
		handling := 0
		return 1
	}
	ext_stickerStackFailedAt := 0, ext_stickerStackUsedAt := nowUnix()
	nm_setStatus("Traveling", convertAfter ? "Hive, to convert under the stack" : "Hive")
	nm_Reset(2, 2000, 0, 1)
	if convertAfter {
		if resumeBalloon
			ConvertGatherFlag := 1
		if !nm_findHiveSlot(1, resumeBalloon)
			nm_setStatus("Failed", "Could not confirm the hive after the stack")
	}
	handling := 0
	return 1
}
;Stop gathering where the macro stands, for an interrupt that goes straight
;from the field rather than walking home and converting first: the end of a
;trip without the trip. The gather time is still counted.
ext_gatherAbandon() {
	global GatherStartTime, TotalGatherTime, SessionGatherTime

	Click "Up"
	nm_endWalk()
	nm_setShiftLock(0)
	if GatherStartTime {
		TotalGatherTime += nowUnix() - GatherStartTime
		SessionGatherTime += nowUnix() - GatherStartTime
	}
	GatherStartTime := 0
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
;Buff only, for now, and the "for now" is a decision rather than an oversight.
;
;Killing Mondo is what an atk account exists for: the same departure at :59, so
;that it is standing on the spawn as the chick appears, but handing over to
;Natro's own Kill routine instead of waiting out a buff. The timing here is
;already the hard half and needs nothing from the fleet - the hour is the same
;on every machine, so each atk decides for itself and no order has to travel.
;
;What it does need is for the atk to be in the right server at :59, and an
;account parked in a reserve has to be brought back first. That is the queue,
;which is not written, and a departure for a server the chick does not spawn in
;is worse than no departure at all. So this waits for it.
;
;One thing settled in advance, so it is not re-argued later: the kill path
;breaks off a balloon convert to get there, where the buff path only does so
;when the boost lease is near its end. Ten minutes of convert is a real loss
;and the spawn does not come round again for an hour - and arriving late to
;a chick somebody else has already killed costs the trip for nothing.
ext_mondoDue() {
	global MondoInterruptCheck, MondoBuffCheck, MondoAction, LastMondoBuff
	local utcMin

	if (!MondoInterruptCheck || (MondoBuffCheck != 1) || (MondoAction != "Buff"))
		return 0
	utcMin := FormatTime(A_NowUTC, "m") + 0
	return ext_mondoDueAt(utcMin, nowUnix() - LastMondoBuff)
}

;:59 to leave a minute early, :00 to :14 to catch up, and fifty-five minutes so
;one spawn is never claimed twice.
;
;A minute window that is wrong by one is a trip made every five seconds for a
;quarter of an hour, or none at all, and neither announces itself. Hence its
;own function and a row in the table for each edge.
ext_mondoDueAt(utcMin, sinceBuff) {
	if !((utcMin = 59) || (utcMin <= 14))
		return 0
	return (sinceBuff > 3300)
}
;From :55 to the spawn the macro starts no planter, quest or collect round, so
;it is not halfway across the map when the chick appears. Only on a macro that
;goes to Mondo at all: for one that does not, holding the errands is pure loss.
ext_mondoErrandsPaused() {
	global MondoBuffCheck

	if (MondoBuffCheck != 1)
		return 0
	return ext_mondoErrandsPausedAt(FormatTime(A_NowUTC, "m") + 0)
}
ext_mondoErrandsPausedAt(utcMin) {
	return (utcMin >= 55) || (utcMin = 0)
}
;A lease in its last 105 seconds would not survive the round trip, so glitter
;goes on before leaving. Pressed this way the boost starts again from the press,
;as DefinetlyNotRay has it, rather than counting as the lease's one renewal.
ext_mondoPreExitGlitter(fieldName) {
	global LastGlitter, GatherFieldBoostedStart, fieldOverrideReason

	if !ext_boostLeaseNearEnd(105)
		return 0
	ext_spamGlitter()
	LastGlitter := nowUnix()
	GatherFieldBoostedStart := LastGlitter
	fieldOverrideReason := "Boost"
	IniWrite LastGlitter, "settings\nm_config.ini", "Boost", "LastGlitter"
	nm_setStatus("Boosted", "Mondo Interrupt`n" fieldName)
	return 1
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
	ext_mondoPreExitGlitter(CurrentField)
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
	} else {
		nm_setStatus("Failed", "Mondo Chick not found")
		Sleep 750
	}
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
