#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon
#Warn All, Off

;The passive row reader, replayed on the user's captures.
;
;	.\submacros\AutoHotkey64.exe /script .\submacros\PassiveSelfTest.ahk
;	.\submacros\AutoHotkey64.exe /script .\submacros\PassiveSelfTest.ahk /build
;
;tools\passive-rows holds the row cut out of each capture, and labels.txt says
;what is in every slot. The test reads every row and compares:
;
;- the slots, and which of them are in cooldown;
;- which passive each visible icon is;
;- every number and every labelled timer.
;
;Digits are matched against examples, and an example is never used to read the
;capture it came from, nor any capture taken at the same moment of play (a
;group in labels.txt): six captures a few seconds apart read each other far too
;well to say anything. So this is the reader's accuracy on a capture it has
;never seen, which is the only accuracy that matters in the game.
;
;A wrong number fails the test; an unread one does not, because the macro
;waits for the next read. The count of unread ones is reported.
;
;/build writes nm_image_assets\passives\glyphs.txt from every labelled glyph,
;the examples the macro itself reads with. Run it after adding captures.

#Include "%A_ScriptDir%\..\lib"
#Include "Gdip_All.ahk"
#Include "Gdip_ImageSearch.ahk"
#Include "%A_ScriptDir%\extensions\passives.ahk"

lines := [], failed := 0
pToken := Gdip_Startup()
rows := A_ScriptDir "\..\tools\passive-rows"
assets := A_ScriptDir "\..\nm_image_assets\passives"
shared := ext_passiveAssets(assets)
crops := PassiveCrops(rows "\labels.txt")
examples := PassiveExamples(crops, shared)

if ObjHasValue(A_Args, "/build") {
	text := "# label<TAB>w (white) or s (salmon)<TAB>12x18 grey levels, row by row`r`n"
		. "# written by PassiveSelfTest /build from tools\passive-rows - do not edit`r`n"
	for e in examples {
		vals := ""
		for n in e.v
			vals .= (A_Index > 1 ? "," : "") n
		text .= e.label "`t" e.kind "`t" vals "`r`n"
	}
	try FileDelete assets "\glyphs.txt"
	FileAppend text, assets "\glyphs.txt", "UTF-8-RAW"
	FileAppend examples.Length " examples written`n", "*"
	ExitApp 0
}

outl := []
tally := Map("slots", 0, "icons", 0, "iconsBad", 0, "num", 0, "numBad", 0, "numNone", 0
	, "tim", 0, "timBad", 0, "timNone", 0)
for c in crops {
	pBM := Gdip_CreateBitmapFromFile(rows "\" c.name ".png")
	slots := ext_passiveRow(pBM, shared)
	if (slots.Length != c.slots.Length) {
		Check(0, c.name ": " slots.Length " slots found, " c.slots.Length " labelled")
		Gdip_DisposeImage(pBM)
		continue
	}
	rowOk := 1
	for i, s in slots
		rowOk &= ((s.kind = "cooldown") = (SubStr(c.slots[i].value, 1, 2) = "cd"))
	Check(rowOk, c.name ": " slots.Length " slots, cooldowns where labelled")
	tally["slots"] += slots.Length
	;everything read here is read with examples from other moments of play
	own := {white: [], salmon: [], icons: shared.icons, ring: shared.ring}
	for e in examples
		if (e.group != c.group)
			((e.kind = "s") ? own.salmon : own.white).Push(e)
	px := ext_passiveLock(pBM)
	for i, s in slots {
		lab := c.slots[i]
		if (SubStr(lab.value, 1, 2) = "cd") {
			if !InStr(lab.value, "=")
				continue
			want := SubStr(lab.value, 4), got := ext_passiveTimerText(px, s.x, s.y, own)
			tally["tim"]++
			if (got = "")
				tally["timNone"]++
			else if (got != want)
				tally["timBad"]++, lines.Push("      " c.name " slot " i ": timer " want " read as " got)
			continue
		}
		ic := ext_passiveIcon(px, s.x, s.y, own)
		tally["icons"]++
		if (ic.name != lab.icon) {
			tally["iconsBad"]++
			lines.Push("      " c.name " slot " i ": " lab.icon " read as " ic.name)
			;the one icon everything rests on
			if (lab.icon = "GuidingStarIcon")
				Check(0, c.name ": the guiding star is recognised")
		}
		if (lab.value = "-")
			continue
		ext_passiveWhite(px, s.x, s.y, 0, &ol)
		for o in ol
			outl.Push(o "`t" c.name " " i " " lab.value)
		got := ext_passiveNumber(px, s.x, s.y, own)
		tally["num"]++
		if (got = "")
			tally["numNone"]++
		else if (got != Integer(lab.value))
			tally["numBad"]++, lines.Push("      " c.name " slot " i ": " lab.value " read as " got)
	}
	ext_passiveUnlock(px)
	Gdip_DisposeImage(pBM)
}
;the outline of the least outlined digit that is really one, against the 0.45
;the reader asks for: how much room is left
for o in SortedNumeric(outl)
	if (A_Index <= 4)
		lines.Push("      outline " o)
Check(tally["numBad"] = 0, "numbers: " tally["num"] - tally["numBad"] - tally["numNone"] " of " tally["num"] " right, "
	. tally["numBad"] " wrong, " tally["numNone"] " unread")
Check(tally["timBad"] = 0, "timers: " tally["tim"] - tally["timBad"] - tally["timNone"] " of " tally["tim"] " right, "
	. tally["timBad"] " wrong, " tally["timNone"] " unread")
;one icon in a hundred may be mistaken: only the guiding star's is acted on,
;and it is checked by itself above
Check(tally["iconsBad"] * 100 <= tally["icons"], "icons: " tally["icons"] - tally["iconsBad"] " of " tally["icons"] " recognised")

;--- the guiding star, end to end --------------------------------------------

;a charge is read and its place remembered
mem := {}
st := GuidingStar("guid2token", mem)
Check(st.state = "charge" && st.value = 2 && mem.HasProp("x") && mem.x = st.x, "star: charge 2 read, place remembered")
;a star in cooldown is read where it was last seen
pBM := Gdip_CreateBitmapFromFile(rows "\guidtimerother.png")
slots := ext_passiveRow(pBM, shared), Gdip_DisposeImage(pBM)
mem := {x: slots[4].x, y: slots[4].y}
st := GuidingStar("guidtimerother", mem)
Check(st.state = "cooldown" && (st.value = 257 || st.value = ""), "star: cooldown read where it was (4:17 is 257 s, got " st.value ")")
;and with nothing remembered, a star in cooldown is not guessed at
st := GuidingStar("guidtimerother", {})
Check(st.state = "unseen", "star: cooldown with no remembered place is unseen")
;a three-digit charge near firing, the case the full ring missed
st := GuidingStar("cap152341", {})
Check(st.state = "charge" && (st.value = 241 || st.value = ""), "star: 241, three digits over the ring (got " st.value ")")
;no passives at all
pBM := Gdip_CreateBitmapFromFile(rows "\t13noPassifAbility.png")
Check(ext_passiveRow(pBM, shared).Length = 0, "no passives: no row")
Gdip_DisposeImage(pBM)

Report()
return

;The star read with every example, as the macro would.
GuidingStar(name, mem) {
	global rows, shared
	pBM := Gdip_CreateBitmapFromFile(rows "\" name ".png")
	st := ext_passiveGuidingStar(pBM, shared, mem)
	Gdip_DisposeImage(pBM)
	return st
}

;labels.txt: crop, group, then Icon:value per slot.
PassiveCrops(path) {
	out := []
	Loop Parse FileRead(path), "`n", "`r" {
		if (A_LoopField = "" || SubStr(A_LoopField, 1, 1) = "#")
			continue
		f := StrSplit(A_LoopField, "`t"), c := {name: f[1], group: f[2], slots: []}
		if (f.Length >= 3 && f[3] != "")
			for cell in StrSplit(f[3], " ") {
				p := InStr(cell, ":")
				c.slots.Push({icon: SubStr(cell, 1, p - 1), value: SubStr(cell, p + 1)})
			}
		out.Push(c)
	}
	return out
}
;Every labelled glyph, cut out by the reader itself: white digits from the
;numbers, salmon ones and the s from the timers. A slot whose glyph count does
;not match its label gives none rather than a mislabelled one.
PassiveExamples(crops, a) {
	global rows
	out := []
	for c in crops {
		if !c.slots.Length
			continue
		pBM := Gdip_CreateBitmapFromFile(rows "\" c.name ".png")
		slots := ext_passiveRow(pBM, a)
		if (slots.Length != c.slots.Length) {
			Gdip_DisposeImage(pBM)
			continue
		}
		px := ext_passiveLock(pBM)
		for i, s in slots {
			lab := c.slots[i].value
			if (SubStr(lab, 1, 3) = "cd=") {
				chars := StrReplace(SubStr(lab, 4), ":"), gl := []
				for g in ext_passiveSalmonGlyphs(px, s.x, s.y)
					if !g.HasProp("colon")
						gl.Push(g)
				if (gl.Length = StrLen(chars))
					for g in gl
						out.Push({label: SubStr(chars, A_Index, 1), kind: "s", group: c.group, v: g.v})
			} else if IsDigit(lab) {
				vs := ext_passiveWhite(px, s.x, s.y)
				if (vs.Length = StrLen(lab))
					for v in vs
						out.Push({label: SubStr(lab, A_Index, 1), kind: "w", group: c.group, v: v})
			}
		}
		ext_passiveUnlock(px)
		Gdip_DisposeImage(pBM)
	}
	return out
}

SortedNumeric(arr) {
	s := ""
	for v in arr
		s .= v "`n"
	return StrSplit(Sort(RTrim(s, "`n"), "N"), "`n")
}
Check(ok, what) {
	global lines, failed
	if !ok
		failed++
	lines.Push((ok ? "PASS  " : "FAIL  ") what)
}

Report() {
	global lines, failed
	local text := "", v, path

	for _, v in lines
		text .= v "`r`n"
	text := "Passive row reader on AutoHotkey " A_AhkVersion "`r`n`r`n" text
		. "`r`n" failed " failed`r`n"
	path := A_ScriptDir "\..\settings\passive_diag.txt"
	try FileDelete path
	try FileAppend text, path, "UTF-8"
	if ObjHasValue(A_Args, "/quiet") {
		FileAppend (failed ? "FAIL" : "PASS") "`n", "*"
		ExitApp failed ? 1 : 0
	}
	try A_Clipboard := text
	MsgBox (failed ? failed " checks failed." : "Every check passed.") "`n`nThe list is on the "
		. "clipboard and in settings\passive_diag.txt.", "Passive self-test", failed ? 0x40010 : 0x40040
	ExitApp failed ? 1 : 0
}

ObjHasValue(arr, needle) {
	for _, v in arr
		if (v = needle)
			return 1
	return 0
}
