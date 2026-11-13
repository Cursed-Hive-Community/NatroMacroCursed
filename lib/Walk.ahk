#Include "%A_LineFile%\..\nm_OCR.ahk"
pToken := Gdip_Startup()
; buff characters for stack detection
buff_characters := Map()
buff_characters[0] := Gdip_BitmapFromBase64("iVBORw0KGgoAAAANSUhEUgAAAAgAAAAKCAAAAACsrEBcAAAAAnRSTlMAAHaTzTgAAAArSURBVHgBY2Rg+MzAwMALxCAaQoDBZyYYmwlMYmXAAFApWPVnBkYIi5cBAJNvCLCTFAy9AAAAAElFTkSuQmCC")
buff_characters[1] := Gdip_BitmapFromBase64("iVBORw0KGgoAAAANSUhEUgAAAAIAAAAMCAAAAABt1zOIAAAAAnRSTlMAAHaTzTgAAAACYktHRAD/h4/MvwAAABZJREFUeAFjYPjM+JmBgeEzEwMDLgQAWo0C7U3u8hAAAAAASUVORK5CYII=")
buff_characters[2] := Gdip_BitmapFromBase64("iVBORw0KGgoAAAANSUhEUgAAAAQAAAALCAAAAAB9zHN3AAAAAnRSTlMAAHaTzTgAAABCSURBVHgBATcAyP8BAPMAAADzAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPMAAADzAAAA8wAAAPMAAAAB8wAAAAIAAAAAtc8GqohTl5oAAAAASUVORK5CYII=")
buff_characters[3] := Gdip_BitmapFromBase64("iVBORw0KGgoAAAANSUhEUgAAAAQAAAAKCAAAAAC2kKDSAAAAAnRSTlMAAHaTzTgAAAA9SURBVHgBATIAzf8BAPMAAAAAAAAAAAAAAAAAAAAAAAAAAADzAAAAAAAAAAAAAAAAAAAAAPMAAAABAPMAAFILA8/B68+8AAAAAElFTkSuQmCC")
buff_characters[4] := Gdip_BitmapFromBase64("iVBORw0KGgoAAAANSUhEUgAAAAQAAAAGCAAAAADBUmCpAAAAAnRSTlMAAHaTzTgAAAApSURBVHgBAR4A4f8AAAAA8wAAAAAAAAAA8wAAAPMAAALzAAAAAfMAAABBtgTDARckPAAAAABJRU5ErkJggg==")
buff_characters[5] := Gdip_BitmapFromBase64("iVBORw0KGgoAAAANSUhEUgAAAAQAAAALCAAAAAB9zHN3AAAAAnRSTlMAAHaTzTgAAABCSURBVHgBATcAyP8B8wAAAAIAAAAAAPMAAAACAAAAAAHzAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHzAAAAgmID1KbRt+YAAAAASUVORK5CYII=")
buff_characters[6] := Gdip_BitmapFromBase64("iVBORw0KGgoAAAANSUhEUgAAAAQAAAAJCAAAAAAwBNJ8AAAAAnRSTlMAAHaTzTgAAAA4SURBVHgBAS0A0v8AAAAA8wAAAPMAAADzAAACAAAAAAEA8wAAAPPzAAAA8wAAAAAA8wAAAQAA8wC5oAiQ09KYngAAAABJRU5ErkJggg==")
buff_characters[7] := Gdip_BitmapFromBase64("iVBORw0KGgoAAAANSUhEUgAAAAQAAAAMCAAAAABgyUPPAAAAAnRSTlMAAHaTzTgAAABHSURBVHgBATwAw/8B8wAAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA8wIAAAAAAgAAAABDdgHu70cIeQAAAABJRU5ErkJggg==")
buff_characters[8] := Gdip_BitmapFromBase64("iVBORw0KGgoAAAANSUhEUgAAAAQAAAAKCAAAAAC2kKDSAAAAAnRSTlMAAHaTzTgAAAA9SURBVHgBATIAzf8BAADzAAAA8wAAAgAAAAABAPMAAAEAAPMAAADzAAAAAAAAAADzAAAAAADzAAABAADzALv5B59oKTe0AAAAAElFTkSuQmCC")
buff_characters[9] := Gdip_BitmapFromBase64("iVBORw0KGgoAAAANSUhEUgAAAAQAAAAKCAAAAAC2kKDSAAAAAnRSTlMAAHaTzTgAAAA9SURBVHgBATIAzf8BAADzAAAA8wAAAPMAAAAAAPMAAAEAAPMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA87TcBbXcfy3eAAAAAElFTkSuQmCC")

; bitmaps for buff identification
(bitmaps := Map()).CaseSense := 0
bitmaps["pBMHaste"] := Gdip_CreateBitmap(10,1)
pGraphics := Gdip_GraphicsFromImage(bitmaps["pBMHaste"]), Gdip_GraphicsClear(pGraphics, 0xfff0f0f0), Gdip_DeleteGraphics(pGraphics)
bitmaps["pBMMelody"] := Gdip_CreateBitmap(3,2)
pGraphics := Gdip_GraphicsFromImage(bitmaps["pBMMelody"]), Gdip_GraphicsClear(pGraphics, 0xff242424), Gdip_DeleteGraphics(pGraphics)
bitmaps["pBMHastePlus"] := Gdip_CreateBitmap(20,1)
pGraphics := Gdip_GraphicsFromImage(bitmaps["pBMHastePlus"]), Gdip_GraphicsClear(pGraphics, 0xffeddb4c), Gdip_DeleteGraphics(pGraphics)
bitmaps["pBMOil"] := Gdip_BitmapFromBase64("iVBORw0KGgoAAAANSUhEUgAAABQAAAABBAMAAAAsvJMWAAAALVBMVEVKRDlNRjlXTTpgVDtwXjhzXzV5ZDaDaziefjutiT3Gm0LWp0XsuEv8xE/+xlCsCySdAAAAFklEQVR4AQELAPT/AO7bl1MQACRorO4cdQTqnFFEXAAAAABJRU5ErkJggg==")
bitmaps["pBMSmoothie"] := Gdip_BitmapFromBase64("iVBORw0KGgoAAAANSUhEUgAAABgAAAABBAMAAAA2gHOYAAAAMFBMVEVKRDlKRTlYTjpjVjtvXjh1YDV2YTV5YzeNcjmkgzywiz3PokTotUr0vk36w0/+xlDRVtQJAAAAGElEQVR4AQENAPL/AP7JcxAAAAACRWir3x4xBISoIvpcAAAAAElFTkSuQmCC")
bitmaps["pBMBearBrown"] := Gdip_BitmapFromBase64("iVBORw0KGgoAAAANSUhEUgAAAAwAAAABBAMAAAAYxVIKAAAAD1BMVEUwLi1STEihfVWzpZbQvKTt7OCuAAAAEklEQVR4AQEHAPj/ACJDEAE0IgLvAM1oKEJeAAAAAElFTkSuQmCC")
bitmaps["pBMBearBlack"] := Gdip_BitmapFromBase64("iVBORw0KGgoAAAANSUhEUgAAAA4AAAABBAMAAAAcMII3AAAAFVBMVEUwLi1TTD9lbHNmbXN5enW5oXHQuYJDhTsuAAAAE0lEQVR4AQEIAPf/ACNGUQAVZDIFbwFmjB55HwAAAABJRU5ErkJggg==")
bitmaps["pBMBearPanda"] := Gdip_BitmapFromBase64("iVBORw0KGgoAAAANSUhEUgAAABAAAAABBAMAAAAlVzNsAAAAGFBMVEUwLi1VU1G9u7m/vLXAvbbPzcXg3dfq6OXkYMPeAAAAFElEQVR4AQEJAPb/AENWchABJ2U0CO4B3TmcTKkAAAAASUVORK5CYII=")
bitmaps["pBMBearPolar"] := Gdip_BitmapFromBase64("iVBORw0KGgoAAAANSUhEUgAAAA4AAAABBAMAAAAcMII3AAAAElBMVEUwLi1JSUqOlZy0vMbY2dnc3NtuftTJAAAAE0lEQVR4AQEIAPf/AFVDIQASNFUFhQFVdZ1AegAAAABJRU5ErkJggg==")
bitmaps["pBMBearGummy"] := Gdip_BitmapFromBase64("iVBORw0KGgoAAAANSUhEUgAAAA4AAAABBAMAAAAcMII3AAAAFVBMVEWYprGDrKWisd+hst+ctNtFyJ4xz5uqDngAAAAAE0lEQVR4AQEIAPf/ACNAFWZRBDIFqwFmOuySwwAAAABJRU5ErkJggg==")
bitmaps["pBMBearScience"] := Gdip_BitmapFromBase64("iVBORw0KGgoAAAANSUhEUgAAAA4AAAABBAMAAAAcMII3AAAAFVBMVEUwLi1TTD+zjUy0jky8l1W5oXHevny+g95vAAAAE0lEQVR4AQEIAPf/ACNGUQAVZDIFbwFmjB55HwAAAABJRU5ErkJggg==")
bitmaps["pBMBearMother"] := Gdip_BitmapFromBase64("iVBORw0KGgoAAAANSUhEUgAAABAAAAABBAMAAAAlVzNsAAAAJFBMVEVBNRlDNxtTRid8b0avoG69r22+sG7Qw4PRw4Te0Jbk153m2Z5VNHxxAAAAFElEQVR4AQEJAPb/AFVouTECSnZVDPsCv+2QpmwAAAAASUVORK5CYII=")

offsetY := 0

Walk(n, hasteCap:=0)
{
	;hasteCap values > 0 will cause all haste values lower than it to be treated as no haste but haste values above it will be treated as the cap value.
	;In otherwords, no haste compensation up to the cap and then 100% compensation after that.
	static freq := 0, init := DllCall("QueryPerformanceFrequency", "Int64*", &freq) ; obtain frequency on first execution
	
	d := freq // 8, l := n * freq * 4 ; 4 studs in a tile
	
	d += (v := DetectMovespeed(&s, &f, hasteCap)) * (f - s)
	while (d < l)
		d += ((v + 0) + (v := DetectMovespeed(&s, &f, hasteCap)))/2 * (f - s)
}

DetectMovespeed(&s, &f, hasteCap:=0)
{
	static chdc := CreateCompatibleDC(), last_width := 0, _deinit := {}.DefineProp("__Delete", {Call: deinit}), hbm := 0, obm := 0
	DllCall("QueryPerformanceCounter", "Int64*", &s := 0)
	
	global hasty_guard, gifted_hasty, base_movespeed, buff_characters, bitmaps, offsetY
	
	; check roblox window exists
	GetRobloxClientPos()
	if (windowWidth = 0)
		return (DllCall("QueryPerformanceCounter", "Int64*", &f := 0), 10000000) ; large number to break walk loop
	
	; get screen bitmap of buff area from client window
	if (!hbm || last_width != windowWidth) {
		if (hbm)
			SelectObject(chdc, obm), DeleteObject(hbm)
		
		hbm := CreateDIBSection(windowWidth, 30, chdc), obm := SelectObject(chdc, hbm)
		last_width := windowWidth
	}
	hhdc := GetDC()
	BitBlt(chdc, 0, 0, windowWidth, 30, hhdc, windowX, windowY+offsetY+48)
	ReleaseDC(hhdc)
	pBMArea := Gdip_CreateBitmapFromHBITMAP(hbm)
	
	; find haste buffs (haste, coconut haste)
	x := 0
	haste := 0 ; initially haste is number of hastes found (since haste = coconut haste icon)
	Loop 3 ; melody, haste, coconut haste
	{
		if (Gdip_ImageSearch(pBMArea, bitmaps["pBMHaste"], &list, x, 14, , , , , 6) != 1)
			break ; no possibility of haste
		
		x := SubStr(list, 1, InStr(list, ",")-1), y := SubStr(list, InStr(list, ",")+1)
		
		if (Gdip_ImageSearch(pBMArea, bitmaps["pBMMelody"], , x+2, , x+Max(16, 2*y-24), y, 12) = 0)
		{
			haste++ ; not melody, so haste
			if (haste = 1)
				x1 := x, y1 := y ; normal haste is always leftmost image
		}
		
		x += 2*y-14 ; skip this buff on next search
	}
	
	; analyse haste stacks (haste: 0=none, 1=haste, 2=haste+coconut)
	coconut_haste := (haste = 2) ? 1 : 0
	if haste
		haste := HasteStack(x1) ; haste now becomes stack number
	else
		HasteStack(0, 1) ; haste gone: read the number straight away next time it appears
	
	; find other movespeed affecting buffs (haste+, bear, oil, super smoothie)
	haste_plus := (Gdip_ImageSearch(pBMArea, bitmaps["pBMHastePlus"], , , 25, , 27, , , 2) = 1) ; SearchDirection 2 is faster for on/off
	oil := (Gdip_ImageSearch(pBMArea, bitmaps["pBMOil"], , , 25, , 27, 4, , 2) = 1)
	smoothie := (Gdip_ImageSearch(pBMArea, bitmaps["pBMSmoothie"], , , 25, , 27, 4, , 2) = 1)
	bear := 0
	for v in ["Brown","Black","Panda","Polar","Gummy","Science","Mother"]
	{
		if (Gdip_ImageSearch(pBMArea, bitmaps["pBMBear" v], , , 25, , 27, 8, , 2) = 1)
		{
			bear := 1
			break
		}
	}
	Gdip_DisposeImage(pBMArea)
	
	; use movespeed formula on obtained values
	v := ((base_movespeed + (coconut_haste ? 10 : 0) + (bear ? 4 : 0)) * (hasty_guard ? 1.1 : 1) * (gifted_hasty ? 1.15 : 1) * (1 + max(0, haste-hasteCap)*0.1) * (haste_plus ? 2 : 1) * (oil ? 1.2 : 1) * (smoothie ? 1.25 : 1))
	
	return (DllCall("QueryPerformanceCounter", "Int64*", &f := 0), v)
	deinit(*) {
		if (hbm && obm)
			SelectObject(chdc, obm)

		if (hbm)
			DeleteObject(hbm)

		if (chdc)
			DeleteDC(chdc)
	}
}

; Haste stack number for DetectMovespeed. The digit images above were captured from the old Roblox font
; and no longer match, so the number is read with OCR (nm_OCRReadStack). DetectMovespeed's own 30 px strip
; starts below the top of the stack number, which cuts the digits off for OCR, so the read uses its own
; screenshot of the full buff bar with the same area Stat Monitor uses (icon x+6 to x+44, y 15-50).
; DetectMovespeed runs many times a second, so OCR runs at most once a second and the value is reused in
; between; the time a read takes is counted by Walk(), so it doesn't throw off distances. A missed read keeps
; the last value for up to 20 s while the icon is showing. Falls back to the old digit images if OCR is unavailable.
HasteStack(hasteX, reset := 0)
{
	global buff_characters, offsetY
	static lastStack := 1, lastTick := 0, lastGood := 0, lastX := -100, lastDump := 0
	if reset
	{
		lastStack := 1, lastTick := 0, lastGood := 0, lastX := -100
		return 1
	}
	; reuse a read from the last second while the haste icon is still in the same place
	if (A_TickCount - lastTick < 1000) && (Abs(hasteX - lastX) <= 6)
		return lastStack
	lastTick := A_TickCount, lastX := hasteX
	GetRobloxClientPos()
	pBM := Gdip_BitmapFromScreen(windowX "|" windowY+offsetY+30 "|" windowWidth "|50")
	if (nm_OCR_Language() = "")
	{
		n := ""
		Loop 9
			if (Gdip_ImageSearch(pBM, buff_characters[10-A_Index], , hasteX+6, 15, hasteX+44, 50) = 1)
			{
				n := (A_Index = 9) ? 10 : 10 - A_Index
				break
			}
	}
	else
		n := nm_OCRReadStack(pBM, hasteX+6, 15, hasteX+44, 50, 10) ; digit pictures for 2-10 first, OCR as a fallback
	; no number read: keep a snapshot (at most every 30 s) in tools\OCR_debug\haste_fail.png for diagnosis.
	; Haste at x1 shows no number, so a snapshot alone doesn't mean something is wrong
	if (n = "") && (A_TickCount - lastDump > 30000)
	{
		lastDump := A_TickCount
		nm_OCR_SaveDebug(pBM, 0, "haste_fail")
		try FileOpen(nm_OCR_RootDir() "\tools\OCR_debug\haste_fail.txt", "a").Write("Haste icon x: " hasteX ", number area x" hasteX+6 "-" hasteX+44 " y15-50`n")
	}
	Gdip_DisposeImage(pBM)
	; one line per OCR read (at most once a second) in tools\OCR_debug\haste_log.txt, to check what walking sees
	try {
		logPath := nm_OCR_RootDir() "\tools\OCR_debug\haste_log.txt"
		DirCreate nm_OCR_RootDir() "\tools\OCR_debug"
		if (FileExist(logPath) && FileGetSize(logPath) > 50000)
			FileDelete logPath
		FileAppend FormatTime(, "HH:mm:ss") "  haste icon x" hasteX "  read: " ((n != "") ? "x" n : "no number") "`n", logPath
	}
	if (n != "")
		lastStack := n, lastGood := A_TickCount
	else if (A_TickCount - lastGood > 20000)
		lastStack := 1 ; no number for 20 s (a full Haste duration): x1 (BSS shows no number at x1)
	; a missed read while the Haste icon is still showing is far more likely than stacks silently dropping,
	; and the stored value is cleared as soon as the icon disappears (HasteStack(0, 1))
	return lastStack
}
