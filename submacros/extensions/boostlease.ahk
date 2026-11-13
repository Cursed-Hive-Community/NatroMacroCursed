;Boost Lease - keeping a field boost alive with Glitter
;
;A field boost runs for fifteen minutes. Stock Natro treats a glitter press as a
;second, independent boost: nm_GatherBoostInterrupt asks whether either the
;detected boost or the last glitter is under fifteen minutes old. Two windows
;that each start from their own event drift apart, and between them the macro
;can believe it is boosted well after the boost on screen has ended.
;
;A lease is those same fifteen minutes expressed as one deadline that a glitter
;press moves forward. Pressing glitter in the closing seconds of a lease renews
;it instead of opening a rival window, so one detected boost plus one renewal
;covers half an hour of continuous boost - which is why a lease with Glitter
;Extend on is thirty minutes long, not fifteen.
;
;One renewal per lease. A second would not help: glitter grants fifteen minutes
;from the moment it is pressed, so pressing it again before the first fifteen
;are up would throw away whatever is left of them.
;
;Reimplemented from DefinetlyNotRay's Glitter Extend patch. The window sizes are
;his measured values and are deliberately kept as they are.

;The lease runs from whichever came last: the boost the macro detected, or the
;glitter press that renewed it. Every other check reads the boost through this
;one deadline, which is the whole point of the lease.
ext_boostLeaseDeadline() {
	global GatherFieldBoostedStart, LastGlitter
	return Max(GatherFieldBoostedStart, LastGlitter) + 900
}
;Seconds since the detected boost. This is measured from the boost rather than
;from the deadline on purpose: the renewal windows below describe where they sit
;inside the original fifteen minutes.
ext_boostLeaseAge() {
	global GatherFieldBoostedStart
	return (GatherFieldBoostedStart > 0) ? (nowUnix() - GatherFieldBoostedStart) : 0
}
;Hand the lease back once its deadline has passed, so the next boost starts
;clean and gets a renewal of its own. Called from nm_GatherBoostInterrupt,
;which runs several times a second, so it has to be cheap and it has to be
;idempotent: once the flags are down there is nothing left to hand back.
ext_boostLeaseExpire() {
	global ext_boostLeaseRenewed, PFieldBoostExtend

	if (!ext_boostLeaseRenewed || (nowUnix() < ext_boostLeaseDeadline()))
		return 0
	ext_boostLeaseRenewed := 0, PFieldBoostExtend := 0
	return 1
}
;What every renewal window agrees on: the feature is on, there is a glitter key
;to press, a lease is running, this lease has not been renewed already, and the
;macro is not off doing something that overrides the field it is standing in.
ext_boostLeaseCanRenew() {
	global PFieldBoosted, GlitterKey, GatherFieldBoostedStart, LastGlitter
	global ext_boostLeaseRenewed, fieldOverrideReason

	if (!PFieldBoosted || (GlitterKey = "none") || (GatherFieldBoostedStart <= 0))
		return 0
	if (ext_boostLeaseRenewed)
		return 0
	;a glitter press inside the last fifteen minutes is the renewal itself
	if ((nowUnix() - LastGlitter) <= 900)
		return 0
	return ((fieldOverrideReason = "None") || (fieldOverrideReason = "Boost"))
}
;The window arithmetic, with nothing read from anywhere.
;
;opens is how many seconds before the end of the lease the window opens. Three
;functions used to carry three copies of this comparison with three different
;numbers in them; one piece of arithmetic with the number as an argument is
;both shorter and the only version that can be asserted against a table of
;values. Before this, the whole behaviour of the feature could be checked only
;by boosting a field and watching for fifteen minutes.
ext_boostLeaseWindowAt(age, opens) {
	return ((age >= (900 - opens)) && (age < 900))
}
;Gathering: renew in the last thirty seconds. The macro is standing in the field
;with nothing else to do, so it can afford to wait for the latest possible
;moment and carry the most boost forward.
ext_boostLeaseGatherWindow() {
	return ext_boostLeaseCanRenew() && ext_boostLeaseWindowAt(ext_boostLeaseAge(), 30)
}
;Converting: renew in the last minute. Thirty seconds is not enough here - the
;macro still has to break off the convert and walk back to the field - so the
;window opens earlier and accepts losing half a minute of boost.
ext_boostLeaseConvertWindow() {
	return ext_boostLeaseCanRenew() && ext_boostLeaseWindowAt(ext_boostLeaseAge(), 60)
}
;A full bag: the last moment to glitter standing in the field before the walk
;to the hive. Ten seconds wider than the converting window - DefinetlyNotRay's
;830 - because the convert that follows will not be back in time otherwise.
ext_boostLeaseBackpackWindow() {
	return ext_boostLeaseCanRenew() && ext_boostLeaseWindowAt(ext_boostLeaseAge(), 70)
}
;Renew from the middle of a convert: walk to the field, glitter, walk back and
;carry on converting. Breaking the convert off instead, as this used to, came
;back to the field to gather - and lost the half-converted balloon.
ext_boostLeaseConvertRenew(fieldName) {
	if (!ext_boostLeaseConvertWindow() || (fieldName = "") || (fieldName = "None"))
		return 0
	nm_setStatus("Traveling", "Glitter Renewal`n" fieldName)
	nm_gotoField(fieldName)
	Sleep 1000
	ext_boostLeaseRenew(fieldName, "Glitter Renewed - Returning to Convert")
	nm_walkFrom(fieldName)
	nm_findHiveSlot()
	return 1
}
;Glitter is spammed rather than pressed once. The press is only registered while
;the character is idle enough for the game to accept a hotbar key, and five
;seconds of pressing costs nothing next to losing the renewal.
ext_spamGlitter(durationMs := 5000, intervalMs := 100) {
	global GlitterKey
	local startTick

	if ((GlitterKey = "none") || (durationMs <= 0))
		return 0
	startTick := A_TickCount
	Loop {
		SendInput "{" GlitterKey "}"
		Sleep Max(intervalMs, 1)
	} until ((A_TickCount - startTick) >= durationMs)
	return 1
}
;Renew the lease: press glitter, move the deadline, and remember that this lease
;has had its one renewal. fieldName only names the field in the status line.
ext_boostLeaseRenew(fieldName, source := "Boost Lease") {
	global LastGlitter, GatherFieldBoosted, fieldOverrideReason
	global ext_boostLeaseRenewed, PFieldBoostExtend

	ext_boostLeaseRenewed := 1
	PFieldBoostExtend := 1
	ext_spamGlitter()
	LastGlitter := nowUnix()
	GatherFieldBoosted := 1
	fieldOverrideReason := "Boost"
	IniWrite LastGlitter, "settings\nm_config.ini", "Boost", "LastGlitter"
	nm_setStatus("Boosted", source ((fieldName != "") ? "`n" fieldName : ""))
	return 1
}
;Pre-Glitter - covering the wait for the blue booster
;
;The blue booster is worth more than glitter, so glitter is never spent while
;one is nearly due; the macro would rather stand in an unboosted field than
;overlap the two. That wastes the last ten minutes of every cooldown.
;
;Glitter runs fifteen minutes. Pressed when the booster is ten to eleven minutes
;away, it boosts the field right up to the trip that presses the booster, and
;the overlap left over is small. Pine Tree only, which is DefinetlyNotRay's
;choice - it is the blue field the macro waits in.
;
;A pre-glitter deliberately does not count as being boosted. nm_GatherBoostInterrupt
;means "we are boosted, do not wander off", and it blocks collecting, quests,
;planters and bug runs while it is true. Locking the macro out of all of them for
;fifteen minutes to protect a filler boost costs more than the boost is worth,
;so the lease is held open for errands until the booster is due.
ext_preGlitterDue(fieldName) {
	global PreGlitterCheck, GlitterKey, LastGlitter, LastBlueBoostUse
	local untilBlue

	if (!PreGlitterCheck || (GlitterKey = "none") || (fieldName != "Pine Tree"))
		return 0
	if ((LastBlueBoostUse = "") || (LastBlueBoostUse <= 0))
		return 0
	untilBlue := 2700 - (nowUnix() - LastBlueBoostUse)
	return ext_preGlitterDueAt(untilBlue, nowUnix() - LastGlitter)
}

;Ten to eleven minutes before the booster, and no glitter already running.
;
;Taken apart from the clocks for the same reason as the lease windows: this is
;the whole of the decision, and three numbers deserve a test rather than a
;quarter of an hour of watching. A glitter pressed inside the last fifteen
;minutes is still running, which is what the second argument is for.
ext_preGlitterDueAt(untilBlue, sinceGlitter) {
	if (sinceGlitter <= 900)
		return 0
	return ((untilBlue <= 660) && (untilBlue > 600))
}
;Press it, and remember when - the window that follows is what keeps the macro
;free to run errands until the booster is due.
ext_preGlitterFire(fieldName) {
	global LastGlitter, PreGlitterStart, PFieldBoostExtend, fieldOverrideReason

	ext_spamGlitter()
	LastGlitter := nowUnix()
	PreGlitterStart := LastGlitter
	PFieldBoostExtend := 1
	fieldOverrideReason := "Boost"
	IniWrite LastGlitter, "settings\nm_config.ini", "Boost", "LastGlitter"
	IniWrite PreGlitterStart, "settings\nm_config.ini", "Boost", "PreGlitterStart"
	nm_setStatus("Boosted", "Pre-Glitter`n" fieldName)
	return 1
}
;Eleven minutes, which is where the window was opened - so it closes as the
;booster comes due and the macro goes back to treating a boost as a boost.
ext_preGlitterActive() {
	global PreGlitterStart

	if (PreGlitterStart <= 0)
		return 0
	if ((nowUnix() - PreGlitterStart) < 660)
		return 1
	ext_preGlitterClear()
	return 0
}
ext_preGlitterClear() {
	global PreGlitterStart

	if (PreGlitterStart <= 0)
		return 0
	PreGlitterStart := 0
	IniWrite PreGlitterStart, "settings\nm_config.ini", "Boost", "PreGlitterStart"
	return 1
}
;True while the lease is close enough to its end that an errand about to take
;the macro out of the field should renew before it goes, rather than come back
;to a boost that ran out on the way.
ext_boostLeaseNearEnd(sec := 60) {
	return ext_boostLeaseCanRenew() && ext_boostLeaseWindowAt(ext_boostLeaseAge(), sec)
}
;Boost Chase - staying with the boosted field
;
;Natro works out which field is boosted afresh at the start of every trip, by
;finding the boost's icon in the buff bar, and a trip that does not recognise
;it goes to the macro's own field instead. With the boost's whole duration no
;longer held inside one trip - Glitter Extend ends a trip on its own clock -
;that check is made several times per boost, and every miss is a trip out of
;the boost.
;
;So the field is remembered from the moment the boost is seen, and every trip
;goes back to it until the boost ends. The buff bar is then only how a boost
;nobody remembered gets found. Reimplemented from DefinetlyNotRay's boosted
;field override (LastBoostedField and LastBoostedTime in his version).
;
;On with Glitter Extend or the blue booster interrupt: those are the two that
;took the boost out of the gather loop, so plain Natro is left exactly as it is.
ext_boostChaseOn() {
	global PFieldBoosted, BlueBoosterInterruptCheck
	return (PFieldBoosted || BlueBoosterInterruptCheck)
}
;Still running: fifteen minutes from whichever came last, the boost or the
;glitter that renewed it - the lease's own deadline, with nothing read.
ext_boostChaseLiveAt(start, glitter, now) {
	return ((start > 0) && (now < (Max(start, glitter) + 900)))
}
;Saved, so a macro restarted halfway through a boost goes back to it as well.
ext_boostChaseRemember(fieldName, start) {
	global BoostChaseField, BoostChaseStart

	if (!ext_boostChaseOn() || (fieldName = "") || (fieldName = "None"))
		return 0
	if ((BoostChaseField = fieldName) && (BoostChaseStart = start))
		return 1
	BoostChaseField := fieldName, BoostChaseStart := start
	IniWrite BoostChaseField, "settings\nm_config.ini", "Boost", "BoostChaseField"
	IniWrite BoostChaseStart, "settings\nm_config.ini", "Boost", "BoostChaseStart"
	return 1
}
ext_boostChaseForget() {
	global BoostChaseField, BoostChaseStart

	if (BoostChaseField = "None")
		return 0
	BoostChaseField := "None", BoostChaseStart := 0
	IniWrite BoostChaseField, "settings\nm_config.ini", "Boost", "BoostChaseField"
	IniWrite BoostChaseStart, "settings\nm_config.ini", "Boost", "BoostChaseStart"
	return 1
}
;The field to farm, or "None". Called once at the start of a trip.
;
;The field's own box in the Boost tab still decides whether it is chased at
;all, exactly as it does for a boost found on the buff bar. The lease is taken
;back to the boost's real start, which a restart would otherwise lose.
ext_boostChaseField() {
	global BoostChaseField, BoostChaseStart, LastGlitter, GatherFieldBoostedStart

	if (!ext_boostChaseOn() || (BoostChaseField = "None"))
		return "None"
	if !ext_boostChaseLiveAt(BoostChaseStart, LastGlitter, nowUnix()) {
		ext_boostChaseForget()
		return "None"
	}
	if !ext_boostChaseBox(BoostChaseField)
		return "None"
	GatherFieldBoostedStart := Max(GatherFieldBoostedStart, BoostChaseStart)
	return BoostChaseField
}
;PineTreeBoosterCheck and its neighbours. Mountain Top has no box and is always
;chased, as Natro has it.
ext_boostChaseBox(fieldName) {
	global
	local name := StrReplace(fieldName, " ") "BoosterCheck"

	try return %name%
	return 1
}
