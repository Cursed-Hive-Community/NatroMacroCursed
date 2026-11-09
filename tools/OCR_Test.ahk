/***********************************************************
* OCR_Test.ahk - read-only check of the OCR changes
* Run with Natro STOPPED. It never clicks, presses keys or moves
* your character: it only takes screenshots and reports what it sees.
* Run it by dragging this file onto submacros\AutoHotkey64.exe,
* or from a terminal: submacros\AutoHotkey64.exe tools\OCR_Test.ahk
***********************************************************/
#Requires AutoHotkey v2.0
#SingleInstance Force
#Include "%A_ScriptDir%\..\lib"
#Include "Gdip_All.ahk"
#Include "Gdip_ImageSearch.ahk"
#Include "Roblox.ahk"
#Include "nm_OpenMenu.ahk"
#Include "nm_InventorySearch.ahk"

CoordMode "Mouse", "Screen"
CoordMode "Pixel", "Screen"
pToken := Gdip_Startup()
OnExit((*) => Gdip_Shutdown(pToken))

(bitmaps := Map()).CaseSense := 0
(shrine := Map()).CaseSense := 0 ; referenced by general\bitmaps.ahk
#Include "%A_ScriptDir%\..\nm_image_assets\general\bitmaps.ahk"
#Include "%A_ScriptDir%\..\nm_image_assets\convert\bitmaps.ahk"

title := "Natro OCR test"
report := "Natro OCR test - " FormatTime(, "yyyy-MM-dd HH:mm") "`n`n"
problems := 0

; ---- 1. OCR engine ----
lang := nm_OCR_Language()
report .= "[1] Windows OCR language: " (lang != "" ? lang " - OK" : "NOT AVAILABLE - add English (United States) in Windows Settings > Language") "`n"
if (lang = "") {
	problems++
	Finish()
}

if !(hwnd := GetRobloxHWND()) {
	report .= "Roblox window not found - open Bee Swarm Simulator and run this again.`n"
	problems++
	Finish()
}

; ---- 2. GUI offset + conversion prompt (stand at hive) ----
if (MsgBox("Step 1 of 2`n`nIn Bee Swarm Simulator:`n - stand on your hive so the Make Honey / Collect Pollen prompt is showing`n - close the item menu`n`nNothing will be clicked or pressed. Click OK when ready.", title, 0x40001) = "Cancel")
	ExitApp
ActivateRoblox()
Sleep 500
GetRobloxClientPos(hwnd)
t := A_TickCount
offsetY := GetYOffset(hwnd, &offsetfail)
report .= "[2] GUI offset: " (offsetfail ? "FAILED - the Pollen label could not be read" : offsetY " px - found in " (A_TickCount - t) " ms") "`n"
if offsetfail
	problems++
else {
	; draw a red line through where the macro thinks the middle of the "Pollen" label is
	line := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
	line.BackColor := "Red"
	line.Show("NA x" windowX + windowWidth//2 - 150 " y" windowY + offsetY + 18 " w300 h2")
	r := MsgBox("A red line is now drawn across the top of Roblox.`n`nDoes it run through the middle of the word `"Pollen`" in the top bar?", title, 0x40023)
	line.Destroy()
	if (r = "Yes")
		report .= "    line check: on the label - OK`n"
	else if (r = "No") {
		report .= "    line check: NOT on the label - set OffsetCorrection in lib\nm_OCR.ahk (positive = move down)`n"
		problems++
	}
}

; conversion prompt: these are the same checks the macro uses to convert, unchanged by the OCR patch
GetRobloxClientPos(hwnd)
pBM := Gdip_BitmapFromScreen(windowX+windowWidth//2-200 "|" windowY+offsetY "|400|125")
eBtn := Gdip_ImageSearch(pBM, bitmaps["e_button"], , , , , , 2, , 6) = 1
mk := Gdip_ImageSearch(pBM, bitmaps["makehoney"], , , , , , 2, , 2) = 1
cp := Gdip_ImageSearch(pBM, bitmaps["collectpollen"], , , , , , 2, , 2) = 1
ch := Gdip_ImageSearch(pBM, bitmaps["colhey"], , , , , , 2, , 2) = 1
ocrPrompt := nm_OCRFindPhrase(pBM, ["makehoney", "collecthoney", "makinghoney", "collectpollen"], 2)
Gdip_DisposeImage(pBM)
report .= "[3] Hive prompt (used for converting): E button " (eBtn ? "found" : "NOT found") ", Make Honey " (mk ? "found" : "not found") ", Collect Pollen " (cp ? "found" : "not found") ", Collect/Honey " (ch ? "found" : "not found") ", OCR prompt text " (ocrPrompt ? "found" : "NOT found") "`n"
if !(mk || ch || ocrPrompt) {
	report .= "    WARNING: the macro could not confirm your hive. If the prompt WAS showing, converting is broken too - send me this report before running unattended.`n"
	problems++
}

; ---- 3. Inventory ----
if (MsgBox("Step 2 of 2`n`nOpen your item menu (inventory) in Bee Swarm Simulator and leave it at the top.`n`nNothing will be clicked or pressed. Click OK when ready.", title, 0x40001) = "OK") {
	ActivateRoblox()
	Sleep 500
	t := A_TickCount
	pBM := nm_InventoryCapture(hwnd, offsetY)
	lines := nm_OCR_ReadInventory(pBM)
	ms := A_TickCount - t
	if !lines {
		report .= "[4] Inventory: OCR FAILED`n"
		problems++
	} else {
		names := ""
		for row in lines
			if (StrLen(row.name) >= 3)
				names .= row.name ", "
		report .= "[4] Inventory text read in " ms " ms: " (names != "" ? RTrim(names, ", ") : "NOTHING - is the item menu open?") "`n"
		if (names = "")
			problems++
		found := ""
		for item in ["PaperPlanter", "TicketPlanter", "PlasticPlanter", "CandyPlanter", "RedClayPlanter", "BlueClayPlanter", "TackyPlanter", "PesticidePlanter", "HeatTreatedPlanter", "HydroponicPlanter", "PetalPlanter", "PlanterOfPlenty", "Glitter", "Gumdrops", "Bitterberry", "BasicEgg", "RoyalJelly", "Strawberry", "Blueberry", "Pineapple", "SunflowerSeed", "Treat"]
			if (nm_OCRFindItem(pBM, item) != "")
				found .= item ", "
		report .= "    items matched on this screen: " (found != "" ? RTrim(found, ", ") : "none") "`n"
	}
	if pBM
		Gdip_DisposeImage(pBM)
}
Finish()

Finish() {
	global report, problems, title
	report .= "`n" (problems ? problems " problem(s) found - don't leave the macro unattended yet." : "Everything checked out.") "`n"
	try FileDelete A_ScriptDir "\OCR_Test_Report.txt"
	FileAppend report, A_ScriptDir "\OCR_Test_Report.txt"
	A_Clipboard := report
	MsgBox report "`n(Copied to clipboard and saved as tools\OCR_Test_Report.txt)", title, problems ? 0x40030 : 0x40040
	ExitApp
}
