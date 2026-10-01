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
;Gathering: renew in the last thirty seconds. The macro is standing in the field
;with nothing else to do, so it can afford to wait for the latest possible
;moment and carry the most boost forward.
ext_boostLeaseGatherWindow() {
	local age
	if !ext_boostLeaseCanRenew()
		return 0
	age := ext_boostLeaseAge()
	return ((age >= 870) && (age < 900))
}
;Converting: renew in the last minute. Thirty seconds is not enough here - the
;macro still has to break off the convert and walk back to the field - so the
;window opens earlier and accepts losing half a minute of boost.
ext_boostLeaseConvertWindow() {
	local age
	if !ext_boostLeaseCanRenew()
		return 0
	age := ext_boostLeaseAge()
	return ((age >= 840) && (age < 900))
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
	;a glitter pressed inside the last fifteen minutes is still running
	if ((nowUnix() - LastGlitter) <= 900)
		return 0
	untilBlue := 2700 - (nowUnix() - LastBlueBoostUse)
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
	local age

	if !ext_boostLeaseCanRenew()
		return 0
	age := ext_boostLeaseAge()
	return ((age >= (900 - sec)) && (age < 900))
}
