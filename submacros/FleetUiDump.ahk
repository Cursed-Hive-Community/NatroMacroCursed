#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off
#NoTrayIcon

;Build one of the fleet's windows and write down every control in it.
;
;	.\submacros\AutoHotkey64.exe /script .\submacros\FleetUiDump.ahk setup 1
;
;The first argument names the window - join, setup, panel, panelfull, servers, hop
;or adv - and the second, when given, is the row this macro sits on. Each
;control's type, name, rectangle, visible and enabled state and first sixty
;characters go to settings\ui_dump.txt, one per line.
;
;This exists because a window cannot be photographed over SSH: it is drawn on
;the service session's desktop, which is never composited, so a screenshot is
;black. The rectangles catch what actually goes wrong - an overlap, a line
;wrapped below its frame, a control past the edge, the wrong text. They cannot
;catch a colour. See TESTING.md, "Proven as layout".
;
;A dialog drawn there cannot be closed either, so every error is written to
;the dump instead and the script exits.
#Include "%A_ScriptDir%\..\lib"
#Include "nowUnix.ahk"
#Include "Socket.ahk"
#Include "FleetProtocol.ahk"
#Include "FleetRoster.ahk"
#Include "FleetServers.ahk"
#Include "FleetHop.ahk"
#Include "%A_ScriptDir%\extensions\fleet.ahk"
SetWorkingDir A_ScriptDir "\.."
OnError(Dumped)
global out := A_ScriptDir "\..\settings\ui_dump.txt"
try FileDelete out
nm_setStatus(*) {
}
nm_saveConfig(*) {
}
nm_ForceReconnect(*) {
}
nm_Reset(*) {
}
DisconnectCheck(*) {
}
PostSubmacroMessage(*) {
}
ext_mondoDueAt(*) {
	return 0
}
global exe_path32 := A_AhkPath, MainGui := ""
global FleetCheck := 0
global FleetRow := 0
global FleetHostRow := 1
global FleetPort := 47600
global FleetSecret := ""
global FleetId := ""
global FleetAddress := ""
global FleetGraceSecs := 45
global FleetServerMain := ""
global FleetServerReserve := ""
global FleetCapacity := 6
global FleetFollowOwn := 1
global FleetFollowBoost := 1
global FleetFollowQuest := 0
global FleetFollowPlanter := 0
global FleetLastField := ""
#Include "%A_ScriptDir%\extensions\fleetstate.ahk"
which := A_Args.Length ? A_Args[1] : "join"
if (A_Args.Length >= 2)
	FleetRow := Integer(A_Args[2])
switch which {
	case "join": ext_FleetJoinGUI(), g := "FleetJoinGui"
	case "setup": ext_FleetSetupGUI(), g := "FleetSetupGui"
	case "panel": ext_FleetGUI(), g := "FleetGui"
	case "servers": ext_FleetServersGUI(), g := "FleetServersGui"
	case "hop": ext_FleetHopGUI(), g := "FleetHopGui"
	case "panelfull":
		global FieldDefault := Map("Pine Tree", 1)
		FleetCheck := 1, ext_fleetMyRole := "fuzzy", ext_fleetFollowField := "Pine Tree"
		mk(r, st, role, field) => Map("row", r, "state", st, "role", role, "field", field, "user", "acct" r, "machine", "PC" r)
		ext_fleetPeers[1] := mk(1, "online", "main", "Pine Tree")
		ext_fleetPeers[2] := mk(2, "online", "fuzzy", "Bamboo")
		ext_fleetPeers[3] := mk(3, "online", "tad", "Pine Tree")
		ext_fleetPeers[4] := mk(4, "stale", "guid", "")
		Loop 8
			ext_fleetPeers[10 + A_Index] := mk(10 + A_Index, "offline", "guid", "")
		ext_FleetGUI(), g := "FleetGui"
		Sleep 1500
		dump := ""
		for ctrl in FleetGui
			if (InStr(ctrl.Name, "FleetSeat") && ctrl.Visible && (SubStr(ctrl.Name, -1) = "r" || SubStr(ctrl.Name, -1) = "n"))
				dump .= ctrl.Name "=" ctrl.Text "`n"
		FileAppend dump, out, "UTF-8"
	case "adv": ext_FleetSetupGUI(), ext_FleetAdvanced(), g := "FleetAdvGui"
}
Sleep 1500
G := %g%
G.GetClientPos(, , &cw, &ch)
txt := "client " cw "x" ch "`n"
for ctrl in G {
	ctrl.GetPos(&x, &y, &w, &hh)
	t := StrReplace(StrReplace(SubStr(ctrl.Text, 1, 60), "`r", ""), "`n", "|")
	txt .= ctrl.Type "`t" ctrl.Name "`t" x "," y "," w "," hh "`t" (ctrl.Visible ? "V" : "-") (ctrl.Enabled ? "E" : "-") "`t" t "`n"
}
FileAppend txt, out, "UTF-8"
ExitApp 0

Dumped(e, *) {
	global out
	FileAppend "ERROR " e.Message " at line " e.Line " (" e.What ")`n", out, "UTF-8"
	ExitApp 1
	return 1
}
