#Include "%A_LineFile%\..\nm_OCR.ahk"

; Searches the item menu for an item by reading item names with OCR (nm_OCR.ahk), so it keeps working
; when Roblox changes its font. Same parameters and return value as the old bitmap version.
nm_InventorySearch(item, direction:="down", prescroll:=0, prescrolldir:="", scrolltoend:=1, max:=70){ ;~ item: string of item; direction: down or up; prescroll: number of scrolls before direction switch; prescrolldir: direction to prescroll, set blank for same as direction; scrolltoend: set 0 to omit scrolling to top/bottom after prescrolls; max: number of scrolls in total
	nm_OpenMenu("itemmenu")

	if !(hwnd := GetRobloxHWND())
		return 0 ; no roblox
	ActivateRoblox()
	offsetY := GetYOffset(hwnd)

	; wait for the item menu to draw (replaces the old bitmaps["item"] / red vignette check)
	if !nm_InventoryWaitReady(hwnd, offsetY)
		return 0

	; search inventory
	found := 0, y := 0
	Loop max
	{
		ActivateRoblox()
		if ((y := nm_InventoryLocate(item, hwnd, offsetY)) != "") {
			found := 1
			break ; item found
		}
		GetRobloxClientPos(hwnd)

		switch A_Index
		{
			case (prescroll+1): ; scroll entire inventory on (prescroll+1)th search
			if (scrolltoend = 1)
			{
				Loop 100
				{
					SendEvent "{Click " windowX+30 " " windowY+offsetY+200 " 0}"
					SendInput "{Wheel" ((direction = "down") ? "Up" : "Down") "}"
					Sleep 50
				}
			}
			default: ; scroll once
			SendEvent "{Click " windowX+30 " " windowY+offsetY+200 " 0}"
			SendInput "{Wheel" ((A_Index <= prescroll) ? (prescrolldir ? ((prescrolldir = "Down") ? "Down" : "Up") : ((direction = "down") ? "Down" : "Up")) : ((direction = "down") ? "Down" : "Up")) "}"
			Sleep 50
		}
		Sleep 500 ; wait for scroll to finish
	}
	return (found ? [30, y+190] : 0) ; return list of coordinates for dragging
}

; Screenshot of the inventory column (306 px wide, from 150 px below the GUI offset to the bottom of the window)
nm_InventoryCapture(hwnd, offsetY) {
	GetRobloxClientPos(hwnd)
	nm_InventoryMouseAway()
	return Gdip_BitmapFromScreen(windowX "|" windowY+offsetY+150 "|306|" Max(40, windowHeight-offsetY-150))
}

; Returns the y of the item's name relative to the inventory capture (windowY+offsetY+150), or "" if not visible
nm_InventoryLocate(item, hwnd, offsetY) {
	pBMScreen := nm_InventoryCapture(hwnd, offsetY)
	y := nm_OCRFindItem(pBMScreen, item)
	Gdip_DisposeImage(pBMScreen)
	return y
}

; Waits until item names are readable in the inventory column. Returns 1 when ready, 0 on timeout.
nm_InventoryWaitReady(hwnd, offsetY, tries:=20) {
	Loop tries
	{
		pBMScreen := nm_InventoryCapture(hwnd, offsetY)
		ready := nm_OCRHasText(pBMScreen)
		Gdip_DisposeImage(pBMScreen)
		if ready
			return 1
		Sleep 100
	}
	return 0
}

; In the item menu, the item under the mouse shows its description instead of its name, so OCR can't find it
; by name. Moves the mouse just right of the item list (same height) if it's over the list.
nm_InventoryMouseAway() {
	GetRobloxClientPos()
	CoordMode "Mouse", "Screen"
	MouseGetPos &mx, &my
	if (mx >= windowX - 5) && (mx < windowX + 330) {
		MouseMove windowX + 350, my, 0
		Sleep 120
	}
}
