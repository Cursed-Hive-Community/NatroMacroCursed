/***********************************************************
* @description: Functions for automating the Roblox window
* @author SP
***********************************************************/

#Include "%A_LineFile%\..\nm_OCR.ahk"

; Updates global variables windowX, windowY, windowWidth, windowHeight
; Optionally takes a known window handle to skip GetRobloxHWND call
; Returns: 1 = successful; 0 = TargetError
GetRobloxClientPos(hwnd?)
{
    global windowX, windowY, windowWidth, windowHeight
    if !IsSet(hwnd)
        hwnd := GetRobloxHWND()

    try
        WinGetClientPos &windowX, &windowY, &windowWidth, &windowHeight, "ahk_id " hwnd
    catch TargetError
        return windowX := windowY := windowWidth := windowHeight := 0
    else
        return 1
}

; Returns: hWnd = successful; 0 = window not found
GetRobloxHWND()
{
	if (hwnd := WinExist("Roblox ahk_exe RobloxPlayerBeta.exe"))
		return hwnd
	else if (WinExist("Roblox ahk_exe ApplicationFrameHost.exe"))
    {
        try
            hwnd := ControlGetHwnd("ApplicationFrameInputSinkWindow1")
        catch TargetError
		    hwnd := 0
        return hwnd
    }
	else
		return 0
}

; Finds the y-offset of GUI elements in the current Roblox window
; Uses OCR to find BSS's "Pollen" label (see nm_OCR.ahk), so it survives Roblox font changes
; Optionally takes a known window handle to skip GetRobloxHWND call
; Returns: offset (integer), defaults to 0 on fail (ByRef param fail is then set to 1, else 0)
GetYOffset(hwnd?, &fail?)
{
	static hRoblox := 0, offset := 0, failHwnd := 0, failTick := 0
	if !IsSet(hwnd)
		hwnd := GetRobloxHWND()

	if (hwnd = hRoblox)
	{
		fail := 0
		return offset
	}
	else if WinExist("ahk_id " hwnd)
	{
		; detection failed for this window moments ago (e.g. still on the loading screen): don't repeat the
		; OCR search on every call, which would make every script that asks for the offset slow and keep
		; pulling Roblox to the front
		if (hwnd = failHwnd) && (A_TickCount - failTick < 20000)
		{
			fail := 1
			return 0
		}
		if !WinActive("ahk_id " hwnd)
		{
			try WinActivate "ahk_id " hwnd
			try WinWaitActive "ahk_id " hwnd, , 1
			Sleep 150 ; give Roblox a moment to redraw after being brought to the front
		}
		Loop 6 ; retries cover the red vignette effect / UI still loading; passes alternate normal, inverted and wider reads
		{
			GetRobloxClientPos(hwnd)
			if ((centre := nm_OCRFindPollenLabel(windowX, windowY, windowWidth, Mod(A_Index - 1, 3) + 1, A_Index = 6)) != "")
				&& (centre - 18.5 >= -20) && (centre - 18.5 <= 90) ; the top bar is never further down than this
			{
				hRoblox := hwnd, fail := 0
				offset := Round(centre - 18.5) + nm_OCRConfig.OffsetCorrection
				nm_OCR_SaveOffset(offset, windowWidth, windowHeight)
				return offset
			}
			Sleep 100
		}
		; OCR found nothing (or isn't available): try the original bitmap method, which still works on setups
		; where the old font image happens to match
		if ((y := nm_OffsetFromBitmap(windowX, windowY, windowWidth)) != "")
		{
			hRoblox := hwnd, fail := 0
			offset := y - 14
			nm_OCR_SaveOffset(offset, windowWidth, windowHeight)
			return offset
		}
		; not readable right now: reuse the last offset detected (or set with tools\Set_GUI_Offset.ahk) at this exact window size
		if ((saved := nm_OCR_SavedOffset(windowWidth, windowHeight)) != "")
		{
			hRoblox := hwnd, fail := 0
			return offset := saved
		}
		failHwnd := hwnd, failTick := A_TickCount
		fail := 1
		return 0 ; default offset, change this if needed
	}
	else
	{
		fail := 1
		return 0
	}
}

; Original Natro offset detection: the "toppollen" bitmap (needs nm_image_assets\offset\bitmaps.ahk loaded)
; Returns the y of the label in the client area, or "" if not found / bitmaps not loaded
nm_OffsetFromBitmap(winX, winY, winW)
{
	global bitmaps
	try
	{
		if !(IsSet(bitmaps) && bitmaps.Has("toppollen") && bitmaps.Has("toppollenfill"))
			return ""
		Loop 3
		{
			pBMScreen := Gdip_BitmapFromScreen(winX+winW//2 "|" winY "|60|100")
			if ((Gdip_ImageSearch(pBMScreen, bitmaps["toppollen"], &pos, , , , , 20) = 1)
				&& (Gdip_ImageSearch(pBMScreen, bitmaps["toppollenfill"], , x := SubStr(pos, 1, (comma := InStr(pos, ",")) - 1), y := SubStr(pos, comma + 1), x + 41, y + 10, 20) = 0))
			{
				Gdip_DisposeImage(pBMScreen)
				return Integer(y)
			}
			Gdip_DisposeImage(pBMScreen)
			Sleep 50
		}
	}
	return ""
}

; Returns: 1 = successful; 0 = TargetError
ActivateRoblox()
{
	try
		WinActivate "Roblox"
	catch
		return 0
	else
		return 1
}

; Waits until the camera has finished turning. Roblox can take a frame or two to start a turn after the key
; press, so first it waits (up to 450 ms) to see the view start changing, then until two checks in a row
; show it has stopped. "Changing" is measured on the middle of the Roblox window shrunk to 8x8: bees and
; particles barely move that average, a turning camera moves it a lot. Returns after timeout ms at the latest.
nm_WaitCameraStill(minWait := 40, timeout := 1500) {
	Sleep minWait
	start := A_TickCount, prev := 0, still := 0, moved := 0
	while (A_TickCount - start < timeout)
	{
		GetRobloxClientPos()
		if (windowWidth < 100 || windowHeight < 100)
			return
		pBM := Gdip_BitmapFromScreen(windowX + windowWidth//4 "|" windowY + windowHeight//4 "|" windowWidth//2 "|" windowHeight//2)
		pSmall := Gdip_ResizeBitmap(pBM, 8, 8, 6)
		Gdip_DisposeImage(pBM)
		if !pSmall
			return
		cur := []
		Loop 64
			cur.Push(Gdip_GetPixel(pSmall, Mod(A_Index - 1, 8), (A_Index - 1)//8))
		Gdip_DisposeImage(pSmall)
		if prev {
			diff := 0
			for i, c in cur
				diff += Abs(((c >> 16) & 255) - ((prev[i] >> 16) & 255)) + Abs(((c >> 8) & 255) - ((prev[i] >> 8) & 255)) + Abs((c & 255) - (prev[i] & 255))
			if (diff / 64 >= 12)
				moved := 1, still := 0
			else if (moved || A_TickCount - start > 450) ; only count stillness once the turn has started (or clearly never will)
				still++
			if (still >= 2)
				return
		}
		prev := cur
		Sleep 30
	}
}
