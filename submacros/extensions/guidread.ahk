;Guid read - the guiding star's charge, for the fleet
;
;Runs in background.ahk, on a guid only - natro_macro switches it on through
;GuidRead when the fleet says this account is one. Every five seconds it reads
;the passive row (extensions\passives.ahk) and tells natro_macro, which tells
;the coordinator: the charge decides when a guid stops farming in the reserve
;and asks for a seat in the main.
;
;Only the lower part of the window is captured: the row sits above the
;hotbar, and the ring search costs by the pixel. The remembered place of the
;star is relative to that capture, which moves with the window, so it holds
;as long as the window keeps its size.
;
;A read is passed on only when two in a row agree. A wrong charge is worse
;than a late one: it would stop a guid early, or let its star go off in the
;reserve. The macro waits for the next read either way.
ext_guidRead() {
	global GuidRead, windowX, windowY, windowWidth, windowHeight
	static last := 0, mem := {}, prev := ""
	local y0, pBM, st, text

	if (!GuidRead || (windowWidth <= 0) || (nowUnix() - last < 5))
		return 0
	last := nowUnix()
	y0 := windowY + (windowHeight * 55) // 100
	pBM := Gdip_BitmapFromScreen(windowX "|" y0 "|" windowWidth "|" (windowY + windowHeight - y0))
	try st := ext_passiveGuidingStar(pBM, ext_passiveAssets(), mem)
	Gdip_DisposeImage(pBM)
	if (!IsSet(st) || ((st.state != "unseen") && (st.value = "")))
		return 0
	text := st.state " " st.value
	if (text != prev) {
		prev := text
		return 0
	}
	if WinExist("natro_macro ahk_class AutoHotkey")
		Send_WM_COPYDATA(Trim(text), "natro_macro ahk_class AutoHotkey", 3)
	return 1
}
