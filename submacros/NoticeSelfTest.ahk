#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon
;Warnings off, as in the other self-tests: Roblox.ahk reads globals this file
;never sets, and the load-time warning is a dialog that nobody can close in
;the VM's SSH session - the test hung on it, before its first line ran.
#Warn All, Off

;A runtime error fails the test rather than hanging it: over SSH there is no
;desktop for AutoHotkey's error dialog.
OnError(SelfTestError)

;The planter notices, read with Windows OCR since Roblox's new font.
;
;	.\submacros\AutoHotkey64.exe /script .\submacros\NoticeSelfTest.ahk
;
;tools\notice-shots holds the lower right quarter of a user's screen with the
;"Paper Planter is already in the Coconut Field" notice stacked up - the macro
;did not see it and threw the planter again and again - and the lower left
;quarter of the same screen, with no notice. The sorting of what OCR read is
;checked by itself too, the trap first: "planteris" is one letter from
;"planters", and a placed planter must not pass for a full set.
;
;The Blender's window too: blender_done.png is what nm_Blender captures of a
;finished batch, from the user's screen, left open by the macro.
;blender_busy.png is the same with the button painted red - made up, as no
;capture of a running craft exists yet. blender_none.png is the top of the
;same screen, the honey bar and a hint, no window.

#Include "%A_ScriptDir%\..\lib"
#Include "Gdip_All.ahk"
#Include "Roblox.ahk"
#Include "%A_ScriptDir%\extensions\notices.ahk"

;ext_planterNotice tries Natro's pictures first; not reached here
nm_imgSearch(*) {
	return [1]
}

lines := [], failed := 0
pToken := Gdip_Startup()
shots := A_ScriptDir "\..\tools\notice-shots"

Kind(arr, want, what) {
	Check(ext_planterNoticeKind(arr) = want, what " (got " ext_planterNoticeKind(arr) ")")
}
Kind(["paperplanterisalreadyinthecoconutfield"], "already", "a placed planter's notice")
Kind(["paperplanterisalreadyinthecoconutfield"], "already", "and it is not taken for 3 planters")
Kind(["paperplanterisalreadvinthecoconutfield"], "already", "a letter misread")
Kind(["youcanonlyhaveplantersout"], "3planters", "3 planters, its digit gone")
Kind(["youmustbestandinginafield"], "standing", "not in a field")
Kind(["honey", "pollen"], "", "no notice")

OcrLines(texts*) {
	local out := [], t
	for t in texts
		out.Push({text: t, x: 0, y: 0, w: 10, h: 10})
	return out
}
seen := ext_blenderReadLines(OcrLines("blender", "endcrafting"))
Check(seen.open && IsObject(seen.endAt) && !seen.cancel, "the Blender window with End Crafting")
seen := ext_blenderReadLines(OcrLines("blender", "cancei"))
Check(seen.open && seen.cancel && !IsObject(seen.endAt), "the amount picker's Cancel, a letter misread")
seen := ext_blenderReadLines(OcrLines("tomakehoneycollectpollen", "fromflowerfields"))
Check(!seen.open && !seen.cancel && !IsObject(seen.endAt), "no window")
Check(ext_blenderButtonColour(0xFF1ACC24) = "done", "the green button")
Check(ext_blenderButtonColour(0xFFC9271C) = "busy", "the red button")
Check(ext_blenderButtonColour(0xFF2868CC) = "", "the blue window behind it")

if (nm_OCR_Language() = "") {
	Check(0, "Windows OCR is not available on this machine")
} else {
	for name, want in Map("already", "already", "nothing", "") {
		pBM := Gdip_CreateBitmapFromFile(shots "\" name ".png")
		got := ext_planterNoticeIn(pBM)
		Gdip_DisposeImage(pBM)
		Check(got = want, name ".png read as '" got "', wanted '" want "'")
	}
	for name, want in Map("blender_done", "done 1", "blender_busy", "busy 1", "blender_none", " 0") {
		pBM := Gdip_CreateBitmapFromFile(shots "\" name ".png")
		seen := ext_blenderRead(pBM)
		Gdip_DisposeImage(pBM)
		got := seen.button " " seen.open
		Check(got = want, name ".png read as '" got "', wanted '" want "'")
	}
}

Report()
return

Check(ok, what) {
	global lines, failed
	if !ok
		failed++
	lines.Push((ok ? "PASS  " : "FAIL  ") what)
}

Report() {
	global lines, failed
	local text := "", v
	for v in lines
		text .= v "`r`n"
	text := "Planter notices on AutoHotkey " A_AhkVersion "`r`n`r`n" text "`r`n" failed " failed`r`n"
	try FileDelete A_ScriptDir "\..\settings\notice_diag.txt"
	try FileAppend text, A_ScriptDir "\..\settings\notice_diag.txt", "UTF-8"
	for a in A_Args
		if (a = "/quiet") {
			FileAppend (failed ? "FAIL" : "PASS") "`n", "*"
			ExitApp failed ? 1 : 0
		}
	MsgBox (failed ? failed " checks failed." : "Every check passed.") "`n`nsettings\notice_diag.txt", "Notice self-test"
	ExitApp failed ? 1 : 0
}

SelfTestError(e, *) {
	try FileAppend "ERROR: " e.Message " - " e.What " (line " e.Line ")`r`n", A_ScriptDir "\..\settings\notice_diag.txt", "UTF-8"
	for a in A_Args
		if (a = "/quiet")
			FileAppend "FAIL`n", "*"
	ExitApp 1
}
