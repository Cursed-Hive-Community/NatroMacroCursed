;Blender - the timing behind Natro's three blender slots
;
;Nothing here reads the screen: what is left of a craft is not shown anywhere
;the macro can read, so every time below is worked out from Natro's own figure
;of five minutes an item, which the user confirmed.
;
;The functions take their numbers as arguments so ExtensionSelfTest can check
;them without a clock or a game.

;How long to leave a blender found already crafting, by how many times in a row
;it has been: five minutes, then ten, twenty, and thirty from then on. What is
;left of somebody else's craft cannot be read, and stock Natro went back on
;every collect round until it was free.
ext_blenderBusyRetry(tries) {
	return Min(300 * 2 ** tries, 1800)
}
;Whether the blender is worth a trip: once it is free, and either a slot is due
;or a finished batch is waiting to be claimed. The timers window's Ready button
;forces one. busyUntil is strict, as stock Natro's was.
ext_blenderVisitAt(now, busyUntil, pick, claim, forced) {
	return forced || ((now > busyUntil) && (pick || claim))
}
