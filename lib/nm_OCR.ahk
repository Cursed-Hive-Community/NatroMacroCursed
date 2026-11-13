/***********************************************************
* @description: OCR-based replacements for the font-dependent
*   GUI offset bitmap (toppollen) and inventory item bitmaps.
*   Uses Windows.Media.Ocr through nm_OCRLib.ahk, so it keeps
*   working when Roblox changes its UI font.
* @requires: Gdip_All.ahk loaded and started by the including script,
*   and an English OCR language pack on Windows (en-US preferred).
***********************************************************/

#Include "%A_LineFile%\..\nm_OCRLib.ahk"

; ---- tunables -------------------------------------------------------------
class nm_OCRConfig {
	static OffsetCorrection := 0  ; px added to the detected GUI offset if it is consistently off by a little
	static OffsetScale := 3       ; upscale for the small "Pollen" label in the top bar
	static InventoryScale := 2    ; upscale for item names in the inventory column
	static ButtonScale := 2       ; upscale for dialog buttons (Yes, Feed)
	static TimerScale := 3        ; upscale for small timer text (Sticker Stack boost time)
	static Debug := 0             ; 1 = send what OCR reads to OutputDebug (view with DebugView)
}
; ---------------------------------------------------------------------------

nm_OCR_Log(msg) {
	if nm_OCRConfig.Debug
		OutputDebug "[Natro OCR] " msg
}

; Returns the OCR language in use, or "" if Windows OCR / an English language pack is unavailable
nm_OCR_Language() {
	static lang := -1
	if (lang != -1)
		return lang
	lang := ""
	try {
		nm_OCRLib.nm_Init()
		Loop Parse nm_OCRLib.GetAvailableLanguages(), "`n", "`r" {
			if (A_LoopField = "")
				continue
			if (A_LoopField = "en-US") {
				lang := A_LoopField
				break
			}
			if (lang = "") && (InStr(A_LoopField, "en-") = 1)
				lang := A_LoopField
		}
		; no English pack: use any installed OCR language. Most read Latin letters and digits well enough for
		; "Pollen", item names and numbers, which beats having no OCR at all
		if (lang = "")
			Loop Parse nm_OCRLib.GetAvailableLanguages(), "`n", "`r"
				if (A_LoopField != "") {
					lang := A_LoopField
					break
				}
		if (lang != "")
			nm_OCRLib.LoadLanguage(lang)
	} catch as e {
		lang := ""
		nm_OCR_Log("Windows OCR unavailable: " e.Message)
	}
	if (lang = "")
		nm_OCR_Log("No OCR language installed. Add English (United States) in Windows language settings.")
	return lang
}

; OCRs a GDI+ bitmap. Word coordinates in the result are relative to the bitmap's top-left corner.
; Returns an nm_OCRLib.Result, or 0 on failure.
nm_OCR_FromBitmap(pBitmap, scale := 1, invert := 0) {
	if ((lang := nm_OCR_Language()) = "")
		return 0
	w := Gdip_GetImageWidth(pBitmap), h := Gdip_GetImageHeight(pBitmap)
	if (w < 1 || h < 1)
		return 0
	scale := Min(scale, (nm_OCRLib.MaxImageDimension - 1) / Max(w, h)) ; Windows OCR rejects oversized images
	try
		return nm_OCRLib.FromBitmap(pBitmap, {lang: lang, scale: scale, invertcolors: invert})
	catch as e {
		nm_OCR_Log("OCR failed: " e.Message)
		return 0
	}
}

nm_OCR_Norm(str) => RegExReplace(StrLower(str), "[^a-z]")

; Levenshtein distance
nm_OCR_Distance(a, b) {
	la := StrLen(a), lb := StrLen(b)
	if !la
		return lb
	if !lb
		return la
	prev := []
	Loop lb + 1
		prev.Push(A_Index - 1)
	Loop la {
		i := A_Index, ca := SubStr(a, i, 1), cur := [i]
		Loop lb {
			j := A_Index
			cur.Push(Min(prev[j+1] + 1, cur[j] + 1, prev[j] + ((ca == SubStr(b, j, 1)) ? 0 : 1)))
		}
		prev := cur
	}
	return prev[lb+1]
}

; Distance between a wanted name and OCR text, tolerating up to 3 junk letters on the end
; (e.g. a misread "x12" amount). Leading junk is NOT tolerated, so "Treat" never matches "Star Treat".
nm_OCR_MatchDistance(target, text) {
	d := nm_OCR_Distance(target, text), lt := StrLen(target)
	if (StrLen(text) > lt) && (StrLen(text) - lt <= 3)
		d := Min(d, nm_OCR_Distance(target, SubStr(text, 1, lt)))
	return d
}

; OCR mistakes allowed for a name of this many letters (short names must match exactly)
nm_OCR_Allowed(len) => (len >= 12) ? 2 : (len >= 6) ? 1 : 0

nm_OCR_WordsRect(words) {
	x1 := y1 := 100000, x2 := y2 := -100000
	for word in words
		x1 := Min(x1, word.x), y1 := Min(y1, word.y), x2 := Max(x2, word.x + word.w), y2 := Max(y2, word.y + word.h)
	return {x: x1, y: y1, w: x2 - x1, h: y2 - y1}
}

; ---------------------------------------------------------------------------
; INVENTORY
; ---------------------------------------------------------------------------

; Names (normalised: lowercase letters only) that an inventory key can appear as on screen.
; By default the key itself is used, e.g. "HeatTreatedPlanter" matches "Heat-Treated Planter".
nm_OCR_ItemNames(item) {
	static aliases := Map(
		"planterofplenty", ["theplanterofplenty"],
		"theplanterofplenty", ["planterofplenty"],
		"sunflowerseed", ["sunflowerseeds"],
		"gumdrops", ["gumdrop"],
		"mooncharm", ["mooncharms"],
		"mooncharms", ["mooncharm"]
	)
	key := nm_OCR_Norm(item), names := [key]
	if aliases.Has(key)
		for n in aliases[key]
			names.Push(n)
	return names
}

; Item name of an OCR line with amount tokens ("x", "x12", "1,234") removed, normalised
nm_OCR_LineName(words) {
	name := ""
	for word in words
		if !RegExMatch(word.Text, "i)^[x×]?[\d,.:]*$")
			name .= word.Text
	return nm_OCR_Norm(name)
}

; Reads the inventory column of pBitmap (left edge = inventory left edge, searchW px wide).
; Returns an array of {name, x, y, w, h} sorted top to bottom, or 0 if OCR failed.
nm_OCR_ReadInventory(pBitmap, searchW := 306) {
	w := Gdip_GetImageWidth(pBitmap), h := Gdip_GetImageHeight(pBitmap)
	if (w > searchW) {
		pCol := Gdip_CloneBitmapArea(pBitmap, 0, 0, searchW, h)
		result := nm_OCR_FromBitmap(pCol, nm_OCRConfig.InventoryScale)
		Gdip_DisposeImage(pCol)
	} else
		result := nm_OCR_FromBitmap(pBitmap, nm_OCRConfig.InventoryScale)
	if !result
		return 0

	lines := []
	for line in result.Lines {
		words := line.Words
		if !words.Length
			continue
		r := nm_OCR_WordsRect(words), entry := {name: nm_OCR_LineName(words), x: r.x, y: r.y, w: r.w, h: r.h}
		i := lines.Length + 1 ; insertion sort by y
		while (i > 1 && lines[i-1].y > entry.y)
			i--
		lines.InsertAt(i, entry)
	}
	if nm_OCRConfig.Debug {
		s := ""
		for row in lines
			s .= row.y ":" row.name " | "
		nm_OCR_Log("inventory: " s)
	}
	return lines
}

; Finds an inventory item by its name.
; Returns the y of the top of the item's name in pBitmap coordinates (same reference point the old
; bitmap searches returned, so callers keep using y+190), or "" if the item isn't visible.
nm_OCRFindItem(pBitmap, item, searchW := 306) {
	if !(lines := nm_OCR_ReadInventory(pBitmap, searchW))
		return ""
	names := nm_OCR_ItemNames(item), found := 0, bestY := 0, bestD := 99
	for i, row in lines {
		texts := [row.name]
		; long names can wrap onto a second line
		if (i < lines.Length) {
			nx := lines[i+1]
			if (nx.y > row.y) && (nx.y - (row.y + row.h) <= row.h) && (Abs(nx.x - row.x) <= 40)
				texts.Push(row.name nx.name)
		}
		for text in texts
			for target in names {
				d := nm_OCR_MatchDistance(target, text)
				if (d <= nm_OCR_Allowed(StrLen(target))) && (!found || d < bestD || (d = bestD && row.y < bestY))
					found := 1, bestY := row.y, bestD := d
			}
	}
	nm_OCR_Log("find " item ": " (found ? "y=" bestY " (distance " bestD ")" : "not found"))
	return found ? bestY : ""
}

; Returns 1 if the inventory column shows any readable text (i.e. the item menu has drawn)
nm_OCRHasText(pBitmap, searchW := 306) {
	if !(lines := nm_OCR_ReadInventory(pBitmap, searchW))
		return 0
	for row in lines
		if (StrLen(row.name) >= 3)
			return 1
	return 0
}

; ---------------------------------------------------------------------------
; GUI OFFSET
; ---------------------------------------------------------------------------

; The top bar labels ("Pollen", "Honey") are dark text on a light box. The exact colour differs between PCs
; (#121517 on one, #1B2A35 on another), so any dark pixel counts
nm_OCR_IsLabelColor(argb) {
	r := (argb >> 16) & 0xFF, g := (argb >> 8) & 0xFF, b := argb & 0xFF
	return (0.299*r + 0.587*g + 0.114*b < 80)
}

; Finds the "Pollen" label at the top of the BSS window.
; Returns the vertical centre of the label's letters in px from the top of the client area, or "".
; The old bitmap put the top of the label at y=14 with 10 px letters at offset 0, i.e. centre 18.5.
; pass 1 = normal read, 2 = inverted colours, 3 = wider and taller area. dump = save what was seen on failure.
nm_OCRFindPollenLabel(winX, winY, winW, pass := 1, dump := 0) {
	if (pass = 3)
		x0 := Max(0, winW//2 - 400), w := Min(800, winW - x0), h := 170
	else
		x0 := Max(0, winW//2 - 120), w := Min(360, winW - x0), h := 130
	if (w < 40)
		return ""
	pBM := Gdip_BitmapFromScreen(winX + x0 "|" winY "|" w "|" h)
	found := 0, bestD := 99, honeyWord := 0, isHoney := 0
	if (result := nm_OCR_FromBitmap(pBM, nm_OCRConfig.OffsetScale, pass = 2)) {
		; The top bar labels start their line ("Pollen 0/35,476,875", "Honey 8,772,..."). The same words also
		; appear in prompts ("Stop Making Honey", "Collect Pollen"), always after another word, and those sit
		; lower down, which would give a far too large offset. So only a line's first word counts, and the
		; topmost one wins.
		for line in result.Lines {
			words := line.Words
			if !words.Length
				continue
			word := words[1]
			; the "Honey" label sits on the same top bar row, so it's a second anchor if "Pollen" isn't read
			if (nm_OCR_MatchDistance("honey", nm_OCR_Norm(word.Text)) <= 1) && (!honeyWord || word.y < honeyWord.y - 4)
				honeyWord := word
			d := nm_OCR_MatchDistance("pollen", nm_OCR_Norm(word.Text))
			if (d <= 1) && (!found || (word.y < found.y - 4) || (Abs(word.y - found.y) <= 4 && d < bestD))
				found := word, bestD := d
		}
	}
	if !found && honeyWord
		found := honeyWord, isHoney := 1
	if !found {
		if dump
			nm_OCR_SaveDebug(pBM, result, "offset_fail")
		Gdip_DisposeImage(pBM)
		nm_OCR_Log("Pollen label not found (pass " pass ")")
		return ""
	}

	; refine with the label's own pixels: OCR boxes can be padded by a pixel or two, the letters can't
	top := "", bottom := ""
	x1 := Max(0, found.x), x2 := Min(w - 1, found.x + found.w - 1)
	y1 := Max(0, found.y - 4), y2 := Min(h - 1, found.y + found.h + 4)
	Loop y2 - y1 + 1 {
		yy := y1 + A_Index - 1, count := 0
		Loop x2 - x1 + 1
			if nm_OCR_IsLabelColor(Gdip_GetPixel(pBM, x1 + A_Index - 1, yy))
				count++
		if (count >= 2) && (count <= (x2 - x1 + 1) * 0.6) { ; skip solid rows (bar edges), keep letter rows
			if (top = "")
				top := yy
			bottom := yy
		}
	}
	Gdip_DisposeImage(pBM)
	if (top = "")
		top := found.y, bottom := found.y + found.h - 1
	nm_OCR_Log((isHoney ? "Honey" : "Pollen") " label rows " top "-" bottom " (pass " pass ", OCR box y=" found.y " h=" found.h ")")
	; "Honey" has a descender (y), so only its top row is comparable: capital letters start 4.5 px above
	; the label centre the offset formula uses
	return isHoney ? top + 4.5 : (top + bottom) / 2
}

; Natro's root folder (the one containing lib, settings, tools)
nm_OCR_RootDir() {
	SplitPath A_LineFile, , &libDir
	SplitPath libDir, , &root
	return root
}

; Remembers the last offset that was actually detected, together with the Roblox client size it was found at
nm_OCR_SaveOffset(offset, w, h) {
	try {
		DirCreate nm_OCR_RootDir() "\settings"
		IniWrite offset "|" w "|" h, nm_OCR_RootDir() "\settings\nm_ocr.ini", "Offset", "Last"
	}
}

; Returns the remembered offset if it was found at exactly this client size, else ""
nm_OCR_SavedOffset(w, h) {
	try
		v := IniRead(nm_OCR_RootDir() "\settings\nm_ocr.ini", "Offset", "Last", "")
	catch
		return ""
	parts := StrSplit(v, "|")
	return (parts.Length = 3 && parts[2] = w && parts[3] = h && IsInteger(parts[1])) ? Integer(parts[1]) : ""
}

; Saves a screenshot and the words OCR read to tools\OCR_debug, so a failed detection can be diagnosed
nm_OCR_SaveDebug(pBM, result, name) {
	try {
		dir := nm_OCR_RootDir() "\tools\OCR_debug"
		DirCreate dir
		Gdip_SaveBitmapToFile(pBM, dir "\" name ".png")
		txt := FormatTime(, "yyyy-MM-dd HH:mm:ss") "`nOCR language: " nm_OCR_Language() "`nWords read:`n"
		if result {
			for word in result.Words
				txt .= word.Text "  (x" Round(word.x) " y" Round(word.y) ")`n"
		} else
			txt .= "(OCR did not run)`n"
		f := FileOpen(dir "\" name ".txt", "w"), f.Write(txt), f.Close()
	}
}

; ---------------------------------------------------------------------------
; DIALOG BUTTONS
; ---------------------------------------------------------------------------

; Finds a button label such as "Yes" or "Feed" in pBitmap with OCR (replaces bitmaps["yes"] / bitmaps["feed"]).
; Returns 1 if found and sets pos to "x,y", the top-left of the word in pBitmap coordinates, which is the
; same format and reference point Gdip_ImageSearch gave, so existing click offsets still work.
; Matches left of minX are ignored. Words that sit alone on their line (button labels) are preferred over
; the same word inside a sentence.
nm_OCRFindWord(pBitmap, word, &pos?, minX := 0) {
	target := nm_OCR_Norm(word), allowed := nm_OCR_Allowed(StrLen(target))
	for invert in [0, 1] ; white button text occasionally reads better inverted
	{
		if !(result := nm_OCR_FromBitmap(pBitmap, nm_OCRConfig.ButtonScale, invert))
			return 0
		best := 0, bestScore := 99
		for line in result.Lines {
			words := line.Words
			for w in words {
				if (w.x < minX)
					continue
				d := nm_OCR_MatchDistance(target, nm_OCR_Norm(w.Text))
				if (d > allowed)
					continue
				score := d + ((words.Length = 1) ? 0 : 10)
				if (score < bestScore)
					best := w, bestScore := score
			}
		}
		if best {
			pos := best.x "," best.y
			nm_OCR_Log("button " word " at " pos (invert ? " (inverted)" : ""))
			return 1
		}
	}
	return 0
}

; ---------------------------------------------------------------------------
; TIMERS
; ---------------------------------------------------------------------------

; Reads a "mm:ss" time (e.g. the Sticker Stack boost time) from pBitmap, ignoring anything left of minX.
; Returns the time in seconds, or "" if no time could be read. On failure a snapshot is saved under
; tools\OCR_debug (name) so the read can be diagnosed.
nm_OCRReadTime(pBitmap, minX := 0, name := "timer_fail") {
	w := Gdip_GetImageWidth(pBitmap), h := Gdip_GetImageHeight(pBitmap)
	pPart := (minX > 0 && minX < w) ? Gdip_CloneBitmapArea(pBitmap, minX, 0, w - minX, h) : pBitmap
	secs := "", lastResult := 0
	for invert in [0, 1] ; light text on blue sometimes reads better inverted
	{
		if !(result := nm_OCR_FromBitmap(pPart, nm_OCRConfig.TimerScale, invert))
			break
		lastResult := result
		for line in result.Lines {
			text := ""
			for word in line.Words
				text .= word.Text " "
			; common OCR digit mix-ups; only ":" counts as a separator so "x1.000" multipliers are never read as times
			fixed := RegExReplace(RegExReplace(text, "[Oo]", "0"), "[lI|!]", "1")
			if RegExMatch(fixed, "(\d{1,2})\s*[:;]\s*(\d{2})(?!\d)", &m) && (m[2] < 60) && (60*m[1] + m[2] <= 3600) {
				secs := 60*m[1] + m[2]
				nm_OCR_Log("time read from '" Trim(text) "' = " secs "s" (invert ? " (inverted)" : ""))
				break 2
			}
		}
	}
	if (secs = "")
		nm_OCR_SaveDebug(pPart, lastResult, name)
	if (pPart != pBitmap)
		Gdip_DisposeImage(pPart)
	return secs
}

; ---------------------------------------------------------------------------
; BUFF STACK NUMBERS
; ---------------------------------------------------------------------------

; Copy of pBM turned black-on-white for OCR. lightToBlack=1: pixels brighter than threshold (0-1) become black
; (white text on dark). lightToBlack=0: pixels darker than threshold become black (dark outlines / dark text).
nm_OCR_Threshold(pBM, threshold, lightToBlack := 1) {
	w := Gdip_GetImageWidth(pBM), h := Gdip_GetImageHeight(pBM), k := lightToBlack ? -12 : 12
	r := k*0.299, g := k*0.587, b := k*0.114, t := (lightToBlack ? 12*threshold : -12*threshold) + 0.5
	matrix := r "|" r "|" r "|0|0|" g "|" g "|" g "|0|0|" b "|" b "|" b "|0|0|0|0|0|1|0|" t "|" t "|" t "|0|1"
	pOut := Gdip_CreateBitmap(w, h), G := Gdip_GraphicsFromImage(pOut)
	Gdip_DrawImage(G, pBM, 0, 0, w, h, 0, 0, w, h, matrix)
	Gdip_DeleteGraphics(G)
	return pOut
}

; Picks a stack number out of OCR words (coordinates in pBM space) whose centre lies in x1,y1-x2,y2.
; Prefers "x5"-style tokens, then bare numbers. Returns 2..maxVal or "".
nm_OCR_StackFromWords(words, x1, y1, x2, y2, maxVal) {
	for pass in [1, 2]
	{
		for word in words
		{
			cx := word.x + word.w/2, cy := word.y + word.h/2
			if (cx < x1 - 6 || cx > x2 + 6 || cy < y1 - 6 || cy > y2 + 6)
				continue
			hasX := RegExMatch(word.text, "i)^[x×*]")
			if ((pass = 1) != !!hasX) || !RegExMatch(word.text, "i)^[x×*]?[0-9OoIlS|B]{1,3}$")
				continue
			t := RegExReplace(word.text, "i)^[x×*]")
			t := StrReplace(StrReplace(StrReplace(t, "O", "0"), "S", "5"), "B", "8")
			t := RegExReplace(t, "[Il|]", "1")
			if IsInteger(t) && (t >= 2) && (t <= maxVal)
				return Integer(t)
		}
	}
	return ""
}

; Reads a buff stack number ("x5", "x10"...) inside x1,y1-x2,y2 of pBM. Attempts, stopping at the first hit:
;  1. a wider strip around the area (OCR does better with some surrounding context), at 3x, normal and inverted
;  2. black-on-white copies of that strip (number, then its outline), at 4x
;  3. a close-up: the area alone on a larger dark canvas (OCR reads tiny isolated images badly), at 5x
; Returns 2..maxVal, or "" if no number was read (BSS shows no number at x1).
nm_OCRReadStack(pBM, x1, y1, x2, y2, maxVal := 10) {
	w := Gdip_GetImageWidth(pBM), h := Gdip_GetImageHeight(pBM)
	; 0. picture match for "10" (only where 10 is the maximum, so "x100" can't be mistaken for it)
	if (maxVal = 10) && nm_OCR_HasX10(pBM, x1, y1, x2, y2)
		return 10
	if (maxVal = 10) && ((n := nm_OCR_BuffDigit(pBM, x1, y1, x2, y2)) != "")
		return n
	; 1. context strip
	sx1 := Max(0, x1 - 120), sx2 := Min(w, x2 + 120)
	if (sx2 - sx1 >= 20) {
		pStrip := Gdip_CloneBitmapArea(pBM, sx1, 0, sx2 - sx1, h)
		for invert in [0, 1]
		{
			if !(result := nm_OCR_FromBitmap(pStrip, 3, invert))
				break
			words := []
			for word in result.Words
				words.Push({text: word.Text, x: word.x + sx1, y: word.y, w: word.w, h: word.h})
			if ((n := nm_OCR_StackFromWords(words, x1, y1, x2, y2, maxVal)) != "") {
				Gdip_DisposeImage(pStrip)
				return n
			}
		}
		; 2. black-on-white copies of the strip: the white number itself, and its dark outline (which stays
		;    readable when the number sits on a bright icon such as Haste)
		for variant in [[0.8, 1], [0.35, 0]]
		{
			pT := nm_OCR_Threshold(pStrip, variant[1], variant[2])
			result := nm_OCR_FromBitmap(pT, 4, 0)
			Gdip_DisposeImage(pT)
			if !result
				break
			words := []
			for word in result.Words
				words.Push({text: word.Text, x: word.x + sx1, y: word.y, w: word.w, h: word.h})
			if ((n := nm_OCR_StackFromWords(words, x1, y1, x2, y2, maxVal)) != "") {
				Gdip_DisposeImage(pStrip)
				return n
			}
		}
		Gdip_DisposeImage(pStrip)
	}
	; 3. close-up on a dark canvas
	cx1 := Max(0, x1 - 10), cy1 := Max(0, y1 - 6), cx2 := Min(w, x2 + 10), cy2 := Min(h, y2 + 4)
	cw := cx2 - cx1, ch := cy2 - cy1
	if (cw < 4 || ch < 4)
		return ""
	pCanvas := Gdip_CreateBitmap(cw + 80, ch + 40), G := Gdip_GraphicsFromImage(pCanvas)
	Gdip_GraphicsClear(G, 0xff202020)
	Gdip_DrawImage(G, pBM, 40, 20, cw, ch, cx1, cy1, cw, ch)
	Gdip_DeleteGraphics(G)
	n := ""
	for invert in [0, 1]
	{
		if !(result := nm_OCR_FromBitmap(pCanvas, 5, invert))
			break
		words := []
		for word in result.Words
			words.Push({text: word.Text, x: word.x - 40 + cx1, y: word.y - 20 + cy1, w: word.w, h: word.h})
		if ((n := nm_OCR_StackFromWords(words, x1, y1, x2, y2, maxVal)) != "")
			break
	}
	Gdip_DisposeImage(pCanvas)
	return n
}

; ---------------------------------------------------------------------------
; PROMPT TEXT
; ---------------------------------------------------------------------------

; Returns 1 if any OCR line in pBM contains one of the phrases (compared as lowercase letters only, so
; "[E] Make Honey" contains "makehoney"), allowing up to `allowed` OCR mistakes. Reads normal, then inverted.
nm_OCRFindPhrase(pBM, phrases, allowed := 2, scale := 2) {
	for invert in [0, 1]
	{
		if !(result := nm_OCR_FromBitmap(pBM, scale, invert))
			return 0
		for line in result.Lines
		{
			text := ""
			for word in line.Words
				text .= word.Text
			n := nm_OCR_Norm(text)
			for ph in phrases
			{
				if InStr(n, ph)
					return 1
				L := StrLen(ph)
				if (StrLen(n) < L - allowed)
					continue
				Loop Max(1, StrLen(n) - L + 1)
					if (nm_OCR_Distance(ph, SubStr(n, A_Index, L)) <= allowed)
						return 1
			}
		}
	}
	return 0
}

; "Make Honey" hive prompt in the top-middle area of pBM (only the first 400x120 px are read)
nm_OCRMakeHoney(pBM) {
	w := Gdip_GetImageWidth(pBM), h := Gdip_GetImageHeight(pBM)
	if (w > 400 || h > 120) {
		pPart := Gdip_CloneBitmapArea(pBM, 0, 0, Min(400, w), Min(120, h))
		r := nm_OCRFindPhrase(pPart, ["makehoney"], 1)
		Gdip_DisposeImage(pPart)
		return r
	}
	return nm_OCRFindPhrase(pBM, ["makehoney"], 1)
}

; ---------------------------------------------------------------------------
; QUEST LOG
; ---------------------------------------------------------------------------

; Smallest number of OCR mistakes between a phrase and any same-length stretch of text (both normalised)
nm_OCR_PhraseDistance(ph, text) {
	if InStr(text, ph)
		return 0
	L := StrLen(ph), best := 99
	if (StrLen(text) <= L)
		return nm_OCR_Distance(ph, text)
	Loop StrLen(text) - L + 1
		best := Min(best, nm_OCR_Distance(ph, SubStr(text, A_Index, L)))
	if (StrLen(text) - L <= 3) ; whole-text comparison catches misreads that change the length, e.g. "rn" for "m"
		best := Min(best, nm_OCR_Distance(ph, text))
	return best
}

; Reads the rectangle x,y,w,h of the Roblox client area (winX, winY = client position) with OCR and looks
; for any of the names (e.g. quest titles), compared as lowercase letters only. Short names must match
; more exactly (up to 1 mistake per 5 letters, max `allowed`).
; Returns [index of the matched name, x, y] with x,y the matched line's top-left in client coordinates, or 0.
nm_OCRMatchNames(names, x, y, w, h, winX, winY, allowed := 2) {
	if (y < 0)
		h += y, y := 0
	if (w < 10 || h < 8)
		return 0
	norms := []
	for n in names
		norms.Push(nm_OCR_Norm(n))
	pBM := Gdip_BitmapFromScreen(winX + x "|" winY + y "|" w "|" h)
	best := 0, bestD := 99
	for invert in [0, 1]
	{
		if !(result := nm_OCR_FromBitmap(pBM, 3, invert))
			break
		for line in result.Lines
		{
			text := "", lx := 100000, ly := 100000
			for word in line.Words
				text .= word.Text, lx := Min(lx, word.x), ly := Min(ly, word.y)
			t := nm_OCR_Norm(text)
			if (t = "")
				continue
			for i, ph in norms
			{
				d := nm_OCR_PhraseDistance(ph, t)
				if (d <= Min(allowed, StrLen(ph)//5)) && (d < bestD)
					best := [i, x + Round(lx), y + Round(ly)], bestD := d
			}
		}
		if best
			break
	}
	Gdip_DisposeImage(pBM)
	nm_OCR_Log("quest names: " (best ? names[best[1]] " at y=" best[3] : "none"))
	return best
}

; "x10" stack number in BSS's current buff font (white digits with a 1 px dark outline), built from a real
; capture of four different buffs at x10. OCR often misses "10" on bright icons such as Haste, so a "10" is
; checked for with this picture first. "." pixels of the template are magenta and ignored in the search.
nm_OCR_X10() {
	static pBM := 0
	if !pBM
		pBM := Gdip_BitmapFromBase64("iVBORw0KGgoAAAANSUhEUgAAAA8AAAAOCAIAAAB/6NG4AAAAcklEQVR4nL2RQRLAIAgDN07//+X0IgJWr+XgIC4YQMZChBkvf8VXUPNiAEmVTjeqDbdyHNDij5q6PUuSQo6DrrrTF8azq6XkpuHb4oW+29+0oG0kZ/BsZPZkpLa7A90yXTYkgFi1M1Q/quikVc6ufx/5C6bBMRVIFFL2AAAAAElFTkSuQmCC")
	return pBM
}

; 1 if a "10" stack number is inside x1,y1-x2,y2 of pBM (Gdip_ImageSearch is called by name so scripts that
; include this file without Gdip_ImageSearch.ahk still load)
nm_OCR_HasX10(pBM, x1, y1, x2, y2) {
	static fn := "Gdip_ImageSearch"
	w := Gdip_GetImageWidth(pBM), h := Gdip_GetImageHeight(pBM)
	try return (%fn%(pBM, nm_OCR_X10(), , Max(0, x1 - 8), Max(0, y1 - 6), Min(w, x2 + 8), Min(h, y2 + 4), 80, 0xFF00FF) = 1)
	return 0
}

; Haste stack digits 2-9 in BSS's current buff font, cut from real captures of the Haste icon (each includes
; the bit of icon around the digit, so they only match on the Haste icon). "." pixels are magenta and ignored
; in the search. Together with the "10" picture this covers every Haste stack; x1 shows no number.
nm_OCR_HasteDigits() {
	static digits := 0
	if !digits
	{
		digits := Map()
		for d, b64 in Map(9, "iVBORw0KGgoAAAANSUhEUgAAAAsAAAAOCAIAAAB2A3HCAAAAaklEQVR4nHWQSRKAQAgDO5T//3I8OAYclRNL0hTImERSdacAIcxUTukBBCPpFhgvUilEMdWJ2uo2pGMs5A/zvaWtu3kwthXhSbJd606PiZf8Kqvh85axdb8lbwjxpRj//mE8x8DRxfsfAJy3IC4QbaeouQAAAABJRU5ErkJggg==", 8, "iVBORw0KGgoAAAANSUhEUgAAAAsAAAAOCAIAAAB2A3HCAAAAaElEQVR4nIWQQQ4AMQgCB9P/f5k9WKtNNiknRUVFxhycUM0EoCRGZ8bJr4vSnrWNt1LwQmkIjD021SkvDaH9iytPplIgdOSqLJoD4vLjD+MOkwK95XS0rMuJwerp+toFwfR0PKjLpT98KkEvFVAnc0oAAAAASUVORK5CYII=", 7, "iVBORw0KGgoAAAANSUhEUgAAAAsAAAAOCAIAAAB2A3HCAAAAZklEQVR4nG2QQQ7AIAzDbLT/fzk7bHSU0UOFgiFtDAGetpcA43TT6nppXdUkO1GS+vqKGDJdXPoEQshvjvqg0EaItVTmaZSAHf0mXZL4WwCDtuZu0ebwyK5E2ssTwZOsbSPANeBj3aUKJRo5H0egAAAAAElFTkSuQmCC", 6, "iVBORw0KGgoAAAANSUhEUgAAAAsAAAAOCAIAAAB2A3HCAAAAbUlEQVR4nG2PwQ3AMAgDz6j7r+w+AiS04YMExj5kjAEQo5w9sutYeChjrbUkN7Ooy5nlqVBfCaF0rNkzuNpK5WeUo0l34mtfasf1BAjPc//c4lwO6o4y1qL5o6gUH5v9C+D1bUFJB2nn2tdHd72afS4OH3HkFAAAAABJRU5ErkJggg==", 5, "iVBORw0KGgoAAAANSUhEUgAAAAsAAAAOCAIAAAB2A3HCAAAAa0lEQVR4nHWRUQ7AIAhD+8zuf+XuY6jUbcQoaKEFsYywrbchWePjIe2KHOih5RPhupQaMlkcDkIsBLUDxTULUsd0oh5NaXQbcjV2JrVIyNgKxPO2OnrCSf8eKaUme+l0M21PbA30qPrzZ81ugAsnJIXx3RAAAAAASUVORK5CYII=", 4, "iVBORw0KGgoAAAANSUhEUgAAAAsAAAAOCAIAAAB2A3HCAAAAY0lEQVR4nG2QwREAIQgDE8f+W957oJwieQFZI2qE0JJ3wW7R0CuStxSEjwAqP5L/5Y6IQBGVK2E59y22pHHZrraseT+C0lo2dV4zeh+ANZ/RX8eObYDmTzM1ioaIH8kklytefQMlKhV7fbGZAAAAAElFTkSuQmCC", 3, "iVBORw0KGgoAAAANSUhEUgAAAAsAAAAOCAIAAAB2A3HCAAAAZklEQVR4nIWQQRKAIAwDdx3+/+V4EJCijjl1mpCGGMLEHL03xwtd50UhiKpeIrEqPtCKs4QRbET58/ChuJIg062tJJDk/ur7FffFUKR3IIprH8JIn/pWxBB/W2+dEKC3WV1NNvcdJ2MNJB4K9NjlAAAAAElFTkSuQmCC", 2, "iVBORw0KGgoAAAANSUhEUgAAAAsAAAAOCAIAAAB2A3HCAAAAZ0lEQVR4nH2QQQ4AIQgDp8b/f7l7gKCwidzAaYvImLui02l1iE4Wt4dUCDBHuM5cCBkbB4cR0tyD5HCmrF94i2hEOadaia/pfO0brWwXPi4RtesLTQ0oPfs9xpKAWDl/1PvZWPbTAD57tzUMjI5PhwAAAABJRU5ErkJggg==")
			digits[d] := Gdip_BitmapFromBase64(b64)
	}
	return digits
}

; Haste stack number from the digit pictures inside x1,y1-x2,y2 of pBM, or "" if none matches
nm_OCR_HasteDigit(pBM, x1, y1, x2, y2) {
	static fn := "Gdip_ImageSearch"
	w := Gdip_GetImageWidth(pBM), h := Gdip_GetImageHeight(pBM)
	for d, pDigit in nm_OCR_HasteDigits()
		try if (%fn%(pBM, pDigit, , Max(0, x1 - 8), Max(0, y1 - 6), Min(w, x2 + 10), Min(h, y2 + 4), 60, 0xFF00FF) = 1)
			return d
	return ""
}

; Focus stack digits 2-9 in BSS's current buff font, cut from real captures of the Focus icon (each includes
; the bit of icon around the digit, so they only match on the Focus icon). "." pixels are magenta and ignored.
nm_OCR_FocusDigits() {
	static digits := 0
	if !digits
	{
		digits := Map()
		for d, b64 in Map(9, "iVBORw0KGgoAAAANSUhEUgAAAAsAAAAOCAIAAAB2A3HCAAAAXElEQVR4nIWQSQ6AMAwDxxb//7I5gEpogsihymqPSkgIHxFybPWzLIQAhVxZ0pS0nnItvTvCLwgNKNbY3q06Zpm75LPcbLEwhXTXbWWde581dc8Cxdwjfw3/fQcnFD8jDo6hMyAAAAAASUVORK5CYII=", 8, "iVBORw0KGgoAAAANSUhEUgAAAAsAAAAOCAIAAAB2A3HCAAAAYElEQVR4nIWQSxKAMAhDXxjvf+W4sFpKP7IiwOQDxsZsyvgquB8LISBaX9YLDLZtzzAOJl61PetjJc4EnaMTCKEMo9y3ddL/V4kmkcSe93wzDQGmLEAMUy16lScopwPgBsOvNfjuarTmAAAAAElFTkSuQmCC", 7, "iVBORw0KGgoAAAANSUhEUgAAAAsAAAAOCAIAAAB2A3HCAAAAV0lEQVR4nIWRQQoAMQgDJ7L//3L2sKVrIW29CBrHoBhzjOdLZqMUdQYA2jVsD0akj6IAShHTpoKPCfiGk1Mv0mp1d09zu35sZzRv93tUJC+KviHeXtfPvVm3IQZLKknhAAAAAElFTkSuQmCC", 6, "iVBORw0KGgoAAAANSUhEUgAAAAsAAAAOCAIAAAB2A3HCAAAAXUlEQVR4nG2OQRKAMAwCl4z//zIeNLXUcEqXhiBjQIjWIs9Qg23wAtRgg/TBcv8/7MUjAzheAWyPTu39Qw2uY28dfWupM3I58iqQO2jPjY1fGUQFVc76Z5BNhyuTbjL4LAyzFGN7AAAAAElFTkSuQmCC", 5, "iVBORw0KGgoAAAANSUhEUgAAAAsAAAAOCAIAAAB2A3HCAAAAY0lEQVR4nH1QQQ7AMAgC0/9/mR2cLZp1HhoRA1gIEoR7rd1JX3tEACD4pzFoskFBS5AvCZWqZjEtNJvwUPmSfL3kWt37yNCvvfxKJDdoDxeDSE6myOY6iqmhhk9fkJ5g2/vwAXKoJR0cukG0AAAAAElFTkSuQmCC", 4, "iVBORw0KGgoAAAANSUhEUgAAAAsAAAAOCAIAAAB2A3HCAAAAXElEQVR4nH2RSxLAIAhDXxjvf+V0UdsRRNlhyAfE2JhzjfbVfCwRgFAPg1AU+B1ZK0qI2S6spDH1lXxjty++UWHVWHXbPdZ2D1/bBNm2gdGePO/S6fw0Y92/DXgA+SctB/wHrN0AAAAASUVORK5CYII=", 3, "iVBORw0KGgoAAAANSUhEUgAAAAsAAAAOCAIAAAB2A3HCAAAAY0lEQVR4nHWQQRLAIAgDN4z//3J60GKLmAMDiZOAGBtzgfEo834shIBYfZGbGUqcbdtAJCs0zQoaatsLobhdcfUwFlomBhFFzpqIIp8YW/tsB8xTISNfn3PJ+LFqepX4/LTkH4y9NvmF9bLrAAAAAElFTkSuQmCC", 2, "iVBORw0KGgoAAAANSUhEUgAAAAsAAAAOCAIAAAB2A3HCAAAAY0lEQVR4nH2RSxYAEQwEuz33v3LNIn4xsEGq4xWEQOg+6rZv6WhxTziWgUnxHhsVWi16oqHA4uGE29lHzSgiAP/x5ntITF9LUnnjOU+bjJPUUNvcqxDOB+SHKwPcfscr8OlqH8KcQ+bFKtdbAAAAAElFTkSuQmCC")
			digits[d] := Gdip_BitmapFromBase64(b64)
	}
	return digits
}

; stack number from the Haste or Focus digit pictures inside x1,y1-x2,y2 of pBM, or "" if none matches
nm_OCR_BuffDigit(pBM, x1, y1, x2, y2) {
	static fn := "Gdip_ImageSearch"
	if ((d := nm_OCR_HasteDigit(pBM, x1, y1, x2, y2)) != "")
		return d
	w := Gdip_GetImageWidth(pBM), h := Gdip_GetImageHeight(pBM)
	for d, pDigit in nm_OCR_FocusDigits()
		try if (%fn%(pBM, pDigit, , Max(0, x1 - 8), Max(0, y1 - 6), Min(w, x2 + 12), Min(h, y2 + 4), 60, 0xFF00FF) = 1)
			return d
	return ""
}

; Reads one quest objective bar (pBM) with OCR and returns which of the keys (e.g. "pinetree", "redpollen")
; it names, "unknown" if text was read but no key fits, or "" if OCR read nothing (then images are tried).
; Keys already in exclude are skipped (an objective can't appear twice). Pollen colours win over fields, so
; "Collect 1,000,000 Blue Pollen" is bluepollen, while "...Pollen from the Blue Flower Field" is blueflower.
nm_OCRQuestObjective(pBM, keys, exclude := "") {
	text := ""
	for invert in [0, 1]
	{
		if !(result := nm_OCR_FromBitmap(pBM, 3, invert))
			return ""
		for line in result.Lines
			for word in line.Words
				text .= word.Text
		text := nm_OCR_Norm(text)
		if (StrLen(text) >= 4)
			break
	}
	if (StrLen(text) < 4)
		return ""
	if (nm_OCR_PhraseDistance("collect", text) > 1) ; only "Collect ..." objectives are handled (like the original images)
		return "unknown"
	best := "", bestD := 99
	for key in keys
	{
		if IsObject(exclude)
			for v in exclude
				if (v = key)
					continue 2
		allowed := (StrLen(key) >= 8) ? 1 : 0
		d := nm_OCR_PhraseDistance(key, text)
		; colour pollen beats a field; otherwise the closest (then longest) name wins
		if (d <= allowed) && ((d < bestD) || (d = bestD && (InStr(key, "pollen") || StrLen(key) > StrLen(best))))
			best := key, bestD := d
	}
	return (best != "") ? best : "unknown"
}
