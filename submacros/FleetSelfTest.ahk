#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon

;An end-to-end check of the Fleet coordinator.
;
;It launches a real coordinator on a test port, connects two pretend macros to
;it, and watches whether the roster reaches both of them. Run it the same way as
;the socket test:
;
;	.\submacros\AutoHotkey64.exe /script .\submacros\FleetSelfTest.ahk
;
;Four things are checked, each because it is a way the design could be wrong
;rather than merely broken:
;
;	1. both macros appear in the roster        the coordinator keeps a roster
;	2. each macro sees the other               it is broadcast, not just held
;	3. "fuzzy 1" keeps its space               field encoding survives the wire
;	4. a wrong secret is refused               the only door has a lock on it
;
;It leaves nothing running: the coordinator it started is closed at the end.

#Include "%A_ScriptDir%\..\lib"
#Include "Socket.ahk"
#Include "FleetProtocol.ahk"

PORT := 47655
SECRET := "selftest"

coordPid := 0, finished := 0
seenBy := Map()             ;client label -> Map of row -> roster frame it received
refused := ""               ;what the bad-secret connection was told

Run '"' A_AhkPath '" /script "' A_ScriptDir '\Fleet.ahk" ' PORT ' ' SECRET ' 1', , , &coordPid
;the coordinator has to bind before anyone can knock
Sleep 1200

seenBy["main"] := Map(), seenBy["fuzzy"] := Map()
clientA := sock_Connect("127.0.0.1", PORT, OnA)
clientB := sock_Connect("127.0.0.1", PORT, OnB)
clientBad := sock_Connect("127.0.0.1", PORT, OnBad)

SetTimer Report, -5000
return

OnA(s, event, data) {
	Handle("main", 1, "main", s, event, data)
}
OnB(s, event, data) {
	;the space in the name is the point: it is the character the wire protocol
	;has to encode, and a naive implementation would split the frame on it
	Handle("fuzzy", 2, "fuzzy 1", s, event, data)
}

Handle(label, row, name, s, event, data) {
	global seenBy, SECRET
	local frame

	if (event = "connect") {
		if (data != "")
			return
		sock_SendLine(s, fleet_Frame("HELLO", Map("row", row, "name", name
			, "role", label, "secret", SECRET, "machine", A_ComputerName)))
		return
	}
	if (event != "line")
		return
	if !(frame := fleet_Parse(data))
		return
	if (frame.verb = "ROSTER")
		seenBy[label][Integer(fleet_Field(frame, "row", 0))] := frame
}

;The connection that should not get in.
OnBad(s, event, data) {
	global refused
	local frame

	if (event = "connect") {
		if (data = "")
			sock_SendLine(s, fleet_Frame("HELLO", Map("row", 9, "name", "intruder"
				, "secret", "wrong")))
		return
	}
	if ((event = "line") && (frame := fleet_Parse(data)) && (frame.verb = "BYE"))
		refused := fleet_Field(frame, "why")
	else if (event = "close")
		refused := refused ? refused : "closed"
}

Report(*) {
	global seenBy, refused, coordPid, finished, clientA, clientB, clientBad
	local lines := [], allOk := 1

	if finished
		return
	finished := 1

	allOk := Check(lines, "both rows reach the main macro"
		, seenBy["main"].Has(1) && seenBy["main"].Has(2)) && allOk
	allOk := Check(lines, "both rows reach the fuzzy macro"
		, seenBy["fuzzy"].Has(1) && seenBy["fuzzy"].Has(2)) && allOk
	allOk := Check(lines, "the space in `"fuzzy 1`" survived"
		, seenBy["main"].Has(2) && (fleet_Field(seenBy["main"][2], "name") == "fuzzy 1")) && allOk
	allOk := Check(lines, "a wrong secret was refused"
		, refused != "") && allOk

	if seenBy["main"].Has(2)
		lines.Push("", "row 2 as the main macro sees it:"
			, "  name=" fleet_Field(seenBy["main"][2], "name")
			. "  role=" fleet_Field(seenBy["main"][2], "role")
			. "  state=" fleet_Field(seenBy["main"][2], "state"))
	else
		lines.Push("", "The main macro never heard about row 2.")

	sock_Close(clientA), sock_Close(clientB), sock_Close(clientBad)
	if coordPid
		try ProcessClose(coordPid)

	MsgBox (allOk ? "Fleet coordinator works.`n`n" : "Fleet coordinator is broken.`n`n")
		. Join(lines) "`nDetail in settings\fleet_log.txt"
		, "Fleet self-test", allOk ? 0x40040 : 0x40010
	ExitApp
}

Check(lines, what, ok) {
	lines.Push((ok ? "PASS  " : "FAIL  ") what)
	return ok
}

Join(arr) {
	local out := ""
	for _, v in arr
		out .= v "`n"
	return out
}
