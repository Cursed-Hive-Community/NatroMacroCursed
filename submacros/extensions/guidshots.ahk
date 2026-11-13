;Guid shots - screenshots of the Guiding Star's cooldown, for training data
;
;Temporary, asked for by the user. The passive reader refuses 3 of 32 labelled
;cooldown timers for want of salmon examples of some digits. When the star's
;landing notice is seen, this takes the Roblox window at once and ten more
;times during the five minute cooldown, and each goes to Discord as
;"DataModelScreen" for the user to collect. To be removed once there are
;enough.
;
;Runs in background.ahk, which already watches for the notice once a second,
;so the shots are taken when they fall due and not whenever the macro next
;looks up from what it is doing.

;When the shots fall: the landing, then ten moments inside the 300 second
;cooldown, in order. Random, and drawn again for every star, because the point
;is digits the examples do not have yet: the same ten moments every time would
;give the same ten timers.
ext_guidShotTimes(start) {
	out := []
	loop 10
		out.Push(start + Random(5, 295))
	loop out.Length - 1 {
		i := A_Index + 1
		while (i > 1 && out[i - 1] > out[i]) {
			t := out[i], out[i] := out[i - 1], out[i - 1] := t, i--
		}
	}
	out.InsertAt(1, start)
	return out
}
;Called once a second; with a field, the star has just been seen landing there.
;A star seen again within its cooldown is the same notice still on screen, not
;a new one.
ext_guidShots(field := "") {
	static due := [], from := 0, where := "", n := 0
	now := nowUnix()
	if (field != "" && now - from > 300)
		from := now, where := field, due := ext_guidShotTimes(now)
	;one a call: a late tick catches up over the next seconds rather than
	;taking the same picture twice
	if (due.Length && now >= due[1]) {
		due.RemoveAt(1)
		ext_guidShotTake(where, now - from, Mod(n++, 50))
	}
}
;The window to settings\passive_debug_NN.png, then a status naming the file for
;Status to send. Fifty names, reused in turn, so a long run does not fill the
;disk when Discord screenshots are off and nothing deletes them.
ext_guidShotTake(field, after, slot) {
	global windowX, windowY, windowWidth, windowHeight
	if (windowWidth <= 0 || windowHeight <= 0)
		return
	path := "settings\passive_debug_" Format("{:02}", slot) ".png"
	pBM := Gdip_BitmapFromScreen(windowX "|" windowY "|" windowWidth "|" windowHeight)
	Gdip_SaveBitmapToFile(pBM, A_WorkingDir "\" path)
	Gdip_DisposeImage(pBM)
	if WinExist("natro_macro ahk_class AutoHotkey")
		Send_WM_COPYDATA("DataModelScreen " field " +" after "s " path, "natro_macro ahk_class AutoHotkey", 2)
}
