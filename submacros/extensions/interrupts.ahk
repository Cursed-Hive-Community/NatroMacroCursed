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
