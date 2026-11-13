#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, Off

;One macro's side of the fleet, with no macro around it.
;
;	AutoHotkey64.exe /script submacros\FleetMacroStub.ahk <folder> <address>
;
;This is extensions\fleet.ahk as natro_macro.ahk includes it - the same file,
;not a copy - with the dozen things it calls in the macro replaced by stubs,
;running out of a folder of its own with a settings\nm_config.ini of its own.
;It connects, heartbeats, elects, starts coordinators and follows exactly as
;the real one does, because it is the real one.
;
;It exists for FleetElectionTest, which runs three of them. Until this, the
;macro's side of the fleet had no test of any kind: FleetSelfTest speaks the
;protocol itself, as a pretend macro. A day of logs from a real fleet then
;showed that side going wrong in ways nothing here could have caught.
;
;<address> is this "machine", as the macros on it reach a coordinator on it:
;127.0.0.1 for the ordinary case, another address of 127.0.0.0/8 to stand for
;another PC - see bindAddr in Fleet.ahk.
;
;What it does is read from outside in settings\stub_state.txt, rewritten four
;times a second, and it takes orders from settings\stub_cmd.txt:
;
;	field Pine Tree     say it farms that field, as the gather loop would
;	quit                exit as a macro does, running its exit handlers

#Include "%A_ScriptDir%\..\lib"
#Include "nowUnix.ahk"
#Include "Socket.ahk"
#Include "FleetProtocol.ahk"
#Include "FleetRoster.ahk"
#Include "FleetServers.ahk"
#Include "FleetHop.ahk"
#Include "%A_ScriptDir%\extensions\fleet.ahk"

if (A_Args.Length < 2)
	ExitApp 2
SetWorkingDir A_Args[1]
OnError stub_Error

nm_setStatus(state, text := "", *) {
	try FileAppend FormatTime(A_Now, "HH:mm:ss") "  " state ": " StrReplace(text, "`n", " - ") "`n"
		, "settings\stub_status.txt", "UTF-8"
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
global fieldOverrideReason := "None", LastMondoBuff := 0
global FieldDefault := Map("Pine Tree", 1, "Bamboo", 1, "Rose", 1, "Blue Flower", 1)
;what nm_importConfig gives the macro: the defaults, then whatever the file says
global FleetCheck := 0, FleetRow := 0, FleetHostRow := 0, FleetPort := 47600
global FleetSecret := "", FleetId := "", FleetHome := "", FleetAddress := ""
global FleetGraceSecs := 45, FleetLastField := "", FleetTerm := 0, FleetMandate := 0
global FleetServerMain := "", FleetServerReserve := "", FleetCapacity := 6
global FleetServerNow := "", FleetServerAssigned := ""
global FleetFollowOwn := 1, FleetFollowBoost := 1, FleetFollowQuest := 0, FleetFollowPlanter := 0
for stub_k in ["FleetCheck", "FleetRow", "FleetHostRow", "FleetPort", "FleetSecret", "FleetId"
	, "FleetHome", "FleetAddress", "FleetGraceSecs", "FleetLastField", "FleetTerm"
	, "FleetMandate"] {
	stub_v := IniRead("settings\nm_config.ini", "Fleet", stub_k, %stub_k%)
	%stub_k% := IsInteger(stub_v) ? Integer(stub_v) : stub_v
}
#Include "%A_ScriptDir%\extensions\fleetstate.ahk"
ext_fleetLocalAddr := A_Args[2]

OnExit ext_fleetOnExit
ext_fleetStart()
SetTimer stub_Tick, 250
Persistent
return

;What this macro is doing, for whoever is watching, and what it is told to do.
stub_Tick() {
	global ext_fleetSock, ext_fleetTrying, ext_fleetTerm, ext_fleetCoordRow
	global ext_fleetCoordSeen, ext_fleetFollowField, ext_fleetCoordPid, ext_fleetMyRole
	global ext_fleetLastProblem
	local seated, cmd, line

	;seated, not merely connected: a coordinator has spoken within two beats
	seated := (ext_fleetSock && ((nowUnix() - ext_fleetCoordSeen) < 11)) ? 1 : 0
	fleet_WriteWhole("settings\stub_state.txt"
		, "seated=" seated "`nat=" (ext_fleetSock ? ext_fleetTrying : "")
		. "`nterm=" ext_fleetTerm "`ncoord=" ext_fleetCoordRow
		. "`nfollow=" ext_fleetFollowField "`nrole=" ext_fleetMyRole
		. "`nowncoord=" ((ext_fleetCoordPid && ProcessExist(ext_fleetCoordPid)) ? 1 : 0)
		. "`nproblem=" ext_fleetLastProblem "`n")
	if !FileExist("settings\stub_cmd.txt")
		return
	cmd := ""
	try cmd := FileRead("settings\stub_cmd.txt", "UTF-8")
	try FileDelete "settings\stub_cmd.txt"
	Loop Parse cmd, "`n", "`r" {
		line := Trim(A_LoopField)
		if (SubStr(line, 1, 6) = "field ")
			ext_fleetReportField(SubStr(line, 7))
		else if (line = "quit")
			ExitApp 0
	}
}

;Written down and ended: a dialog here would be on a desktop nobody sees.
stub_Error(e, *) {
	try FileAppend "ERROR " e.Message " at line " e.Line " (" e.What ")`n"
		, "settings\stub_error.txt", "UTF-8"
	ExitApp 1
	return 1
}
