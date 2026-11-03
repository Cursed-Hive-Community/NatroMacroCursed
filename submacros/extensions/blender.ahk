;Blender - the timing behind Natro's three blender slots
;
;Stock Natro crafts each slot as soon as the blender is free and has no other
;notion of time. Left on Repeat infinite, it therefore goes back every few
;minutes whether or not the ingredients have come in, and the first visit that
;finds them short wipes the slot. The user's case is a planter that brings in
;about ten coconuts every two hours: crafting has to keep pace with that, not
;with the blender.
;
;So each slot carries a wait, in minutes, between two of its attempts. A slot
;with no wait behaves as it always has. One that is short of ingredients is
;skipped and tried again later instead of being cleared.
;
;Nothing here reads the screen: what is left of a craft is not shown anywhere
;the macro can read, so every time below is worked out from Natro's own figure
;of five minutes an item, which the user confirmed.
;
;The functions take their numbers as arguments so ExtensionSelfTest can check
;them without a clock or a game.

;A slot takes part while it holds an item and has repeats left. The index is a
;count, or "Infinite" - "∞" too, as the remote control and older settings write
;it.
ext_blenderSlotLive(item, index) {
	if (item = "None" || item = "")
		return 0
	return (index = "Infinite" || index = "∞" || (IsNumber(index) && index > 0))
}
;The first live slot that is due, counting from rot in Natro's 1, 2, 3 order,
;or 0 for none. live and next are three-element arrays.
ext_blenderPickAt(rot, live, next, now) {
	loop 3 {
		i := Mod(rot + A_Index - 2, 3) + 1
		if (live[i] && (now >= next[i]))
			return i
	}
	return 0
}
;When a slot may be tried again. After a craft, once its wait is over; with no
;wait it is due at once and the blender being busy is what holds it back, as in
;stock Natro. After a skip for want of ingredients, once its wait is over too,
;or with no wait as long as the batch would have taken: going back on every
;collect round would cost a trip each time for a craft that cannot happen.
ext_blenderNextAt(now, waitMin, amount, crafted) {
	if (waitMin > 0)
		return now + waitMin * 60
	return crafted ? now : now + amount * 300
}
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
;When the other two slots' next batches will be ready, for the timers window:
;in rotation order after slot c, whose batch ends at t, each one starting when
;the blender frees up or its wait is over, whichever comes later. A slot that is
;not live gets 0. c's own entry is left at t.
ext_blenderPlanAfter(c, t, live, next, amount) {
	plan := [0, 0, 0], plan[c] := t
	loop 2 {
		i := Mod(c + A_Index - 1, 3) + 1
		if live[i]
			plan[i] := t := Max(t, next[i]) + amount[i] * 300
	}
	return plan
}
;The slot's line under its picture: amount, repeats, and the wait when there is
;one.
ext_blenderLabel(amount, index, waitMin) {
	return "(" amount ") [" ((index = "Infinite") ? "∞" : index) "]" ((waitMin > 0) ? " " waitMin "m" : "")
}
