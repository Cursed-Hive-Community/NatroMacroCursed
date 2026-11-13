#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon
#Warn All, Off

;Who runs the fleet, and does everybody end up with them?
;
;	.\submacros\AutoHotkey64.exe /script .\submacros\FleetElectionTest.ahk
;	.\submacros\AutoHotkey64.exe /script .\submacros\FleetElectionTest.ahk two
;
;Three macros - a main that hosts, and two tads - each a FleetMacroStub, which
;is the real extensions\fleet.ahk with no macro around it. They start real
;coordinators. Nothing here speaks the protocol: this only starts and stops
;macros, tells the main which field it farms, and reads what each one says it
;is doing.
;
;Without an argument all three are on one PC. With "two", the main is on one
;and the tads on another: 127.0.0.2 and 127.0.0.3, which Windows answers on
;like any address of its own - see bindAddr in Fleet.ahk.
;
;What is asked, every time the fleet has been disturbed: within a deadline,
;every macro is seated with the same coordinator, that coordinator is the
;main's, a field the main then announces reaches both tads, and one
;coordinator is running. That is the whole of what a fleet is for, and it is
;what a real one failed at for 27 hours of a day and a half (AUDIT.md): each
;macro was connected, to a different coordinator, and none had anything to
;report.
;
;	1. started in order              the ordinary beginning of a session
;	2. the main gone past the grace  a tad takes over, the other joins it
;	3. the main back                 it asks for its job and is given it
;	4. the main restarted quickly    nobody takes over, nobody is lost
;	5. the alts started first        the main arrives to a fleet already run
;	6. the main's process killed     no exit handler, its coordinator left behind
;
;The grace period is twelve seconds here rather than forty-five. Nothing else
;is shortened: the beats, the beacon and the watch run at their real pace.

#Include "%A_ScriptDir%\..\lib"
#Include "nowUnix.ahk"
#Include "FleetProtocol.ahk"
#Include "FleetRoster.ahk"

OnError elect_Error

elect_two := (A_Args.Length >= 1) && InStr(A_Args[1], "two")
elect_quiet := 0
for elect_arg in A_Args
	if (elect_arg = "/quiet")
		elect_quiet := 1
elect_port := elect_two ? 47730 : 47720
elect_id := "electfleet"
elect_base := A_ScriptDir "\..\settings\election" (elect_two ? "2" : "1")
elect_addr := elect_two ? ["127.0.0.2", "127.0.0.3", "127.0.0.3"]
	: ["127.0.0.1", "127.0.0.1", "127.0.0.1"]
elect_pid := [0, 0, 0]
elect_lines := [], elect_ok := 1
elect_diag := A_ScriptDir "\..\settings\election_diag.txt"

elect_Sweep()
elect_Build()

;1 - started in order
elect_Start(1), Sleep(1500), elect_Start(2), elect_Start(3)
elect_Settled("1. started in order", 30, "Pine Tree")

;2 - the main gone for longer than the grace period
elect_Stop(1)
elect_Check("2. the main gone: a tad runs the fleet and the other is with it"
	, elect_Wait(() => elect_Together([2, 3], 2), 50))

;3 - the main back
elect_Start(1)
elect_Settled("3. the main back", 60, "Bamboo")

;4 - the main restarted quickly
elect_Stop(1), elect_Start(1)
elect_Settled("4. the main restarted quickly", 45, "Rose")

;5 - the alts started first
elect_Stop(1), elect_Stop(2), elect_Stop(3)
Sleep 1000
elect_Start(2), elect_Start(3)
Sleep 20000
elect_Start(1)
elect_Settled("5. the alts started first", 60, "Blue Flower")

;6 - the main's process killed, with no chance to end its coordinator
try ProcessClose(elect_pid[1])
elect_pid[1] := 0
Sleep 3000
elect_Start(1)
elect_Settled("6. the main killed and started again", 60, "Pine Tree")

elect_Finish()

;--- what is asked --------------------------------------------------------------

;Everybody with the main's coordinator, a field announced now reaching both
;tads, and one coordinator left running - all within secs.
elect_Settled(what, secs, field) {
	local ok := elect_Wait(() => elect_Together([1, 2, 3], 1), secs)

	elect_Check(what ": all three with the main's coordinator", ok)
	elect_Say(1, "field " field)
	elect_Check(what ": a field the main announces reaches both tads (" field ")"
		, elect_Wait(() => (elect_State(2, "follow") = field) && (elect_State(3, "follow") = field), 15))
	elect_Check(what ": one coordinator is running"
		, elect_Wait(() => (elect_Coordinators() = 1), 20))
}

;Are these macros all seated with the same coordinator, started by that row?
;The same term and the same starter, and on two PCs the same address too. On
;one PC the address says nothing: a coordinator there answers on 127.0.0.1 and
;on the machine's own address, and a macro reaches it by either.
elect_Together(rows, by) {
	global elect_two
	local r, at := "", term := ""

	for r in rows {
		if ((elect_State(r, "seated") != "1") || (elect_State(r, "coord") != by))
			return 0
		if (at = "")
			at := elect_State(r, "at"), term := elect_State(r, "term")
		else if ((elect_two && (elect_State(r, "at") != at)) || (elect_State(r, "term") != term))
			return 0
	}
	return (at != "")
}

elect_Wait(cond, secs) {
	local deadline := A_TickCount + secs * 1000

	while (A_TickCount < deadline) {
		if cond()
			return 1
		Sleep 250
	}
	return cond() ? 1 : 0
}

elect_Check(what, ok) {
	global elect_lines, elect_ok
	local r, line

	elect_lines.Push((ok ? "PASS  " : "FAIL  ") what)
	if ok
		return
	elect_ok := 0
	;where each macro was when it failed, which is the whole of the diagnosis
	for r in [1, 2, 3] {
		line := "        row " r ":"
		for _, k in ["seated", "at", "term", "coord", "follow", "owncoord", "problem"]
			line .= " " k "=" elect_State(r, k)
		elect_lines.Push(line)
	}
	elect_lines.Push("        coordinators running: " elect_Coordinators())
}

;--- the macros -------------------------------------------------------------------

elect_Dir(row) {
	global elect_base
	return elect_base "\m" row
}

;One line of what a macro says about itself, "" when it says nothing.
elect_State(row, key) {
	local text := "", m

	try text := FileRead(elect_Dir(row) "\settings\stub_state.txt", "UTF-8")
	return RegExMatch(text, "m)^" key "=(.*?)\r?$", &m) ? m[1] : ""
}

elect_Say(row, cmd) {
	try FileAppend cmd "`n", elect_Dir(row) "\settings\stub_cmd.txt", "UTF-8"
}

elect_Start(row) {
	global elect_pid, elect_addr
	local pid := 0

	try FileDelete elect_Dir(row) "\settings\stub_state.txt"
	Run '"' A_AhkPath '" /script "' A_ScriptDir '\FleetMacroStub.ahk" "' elect_Dir(row) '" '
		. elect_addr[row], , "Hide", &pid
	elect_pid[row] := pid
}

;As a macro is closed: it is asked, and runs its exit handlers.
elect_Stop(row) {
	global elect_pid

	if !elect_pid[row]
		return
	elect_Say(row, "quit")
	Loop 20 {
		if !ProcessExist(elect_pid[row])
			break
		Sleep 250
	}
	if ProcessExist(elect_pid[row])
		try ProcessClose(elect_pid[row])
	elect_pid[row] := 0
	try FileDelete elect_Dir(row) "\settings\stub_state.txt"
}

;The coordinators and stubs of this run, by the folder on their command line.
elect_Processes(kind) {
	global elect_base
	local out := [], proc, cmd, tail := SubStr(elect_base, InStr(elect_base, "\settings\election"))

	try {
		for proc in ComObjGet("winmgmts:").ExecQuery("SELECT ProcessId, CommandLine"
			. " FROM Win32_Process WHERE Name LIKE 'AutoHotkey%'") {
			try cmd := proc.CommandLine
			catch
				continue
			if (InStr(cmd, tail "\") && InStr(cmd, kind))
				out.Push(proc.ProcessId)
		}
	}
	return out
}
elect_Coordinators() {
	return elect_Processes("\submacros\Fleet.ahk").Length
}

;Nothing of an earlier run left behind: a coordinator outlives the macro that
;started it by five minutes, and would hold the port this run needs.
elect_Sweep() {
	local id

	for id in elect_Processes("FleetMacroStub.ahk")
		try ProcessClose(id)
	for id in elect_Processes("\submacros\Fleet.ahk")
		try ProcessClose(id)
	Sleep 500
}

;Three macro folders, each with what a macro's folder has that the fleet
;uses: its settings, this fleet's roster, and the coordinator it would start.
elect_Build() {
	global elect_base, elect_port, elect_id
	local row, dir, rows := Map(), f

	try DirDelete elect_base, 1
	rows[1] := { row: 1, name: "Main", role: "main", user: "main1", machine: "election" }
	rows[2] := { row: 2, name: "Tad one", role: "tad", user: "tad1", machine: "election" }
	rows[3] := { row: 3, name: "Tad two", role: "tad", user: "tad2", machine: "election" }
	for row in [1, 2, 3] {
		dir := elect_Dir(row)
		DirCreate dir "\settings\fleet\" elect_id
		DirCreate dir "\submacros"
		DirCreate dir "\lib"
		FileCopy A_ScriptDir "\Fleet.ahk", dir "\submacros\Fleet.ahk", 1
		for f in ["Socket", "FleetProtocol", "FleetRoster", "FleetServers", "FleetHop", "nowUnix"]
			FileCopy A_ScriptDir "\..\lib\" f ".ahk", dir "\lib\" f ".ahk", 1
		roster_Save(dir "\settings\fleet\" elect_id "\roster.ini", rows, 1, 1)
		FileAppend "[Fleet]`r`nFleetCheck=1`r`nFleetRow=" row "`r`nFleetHostRow=" ((row = 1) ? 1 : 0)
			. "`r`nFleetPort=" elect_port "`r`nFleetSecret=electiontest`r`nFleetId=" elect_id
			. "`r`nFleetGraceSecs=12`r`n", dir "\settings\nm_config.ini", "UTF-16"
	}
}

elect_Finish() {
	global elect_lines, elect_ok, elect_diag, elect_quiet, elect_two
	local text := "", l, row, tail

	;each macro's own account of the run goes in the report before the folders
	;are left behind: it is what says why
	for row in [1, 2, 3] {
		tail := ""
		try tail := FileRead(elect_Dir(row) "\settings\fleet_macro.log", "UTF-8")
		elect_lines.Push("", "--- row " row ", settings\fleet_macro.log", tail)
		try tail := "", tail := FileRead(elect_Dir(row) "\settings\stub_error.txt", "UTF-8")
		if (tail != "")
			elect_lines.Push("--- row " row " ERRORS", tail), elect_ok := 0
	}
	elect_Sweep()
	for l in elect_lines
		text .= l "`r`n"
	try FileDelete elect_diag
	try FileAppend (elect_two ? "two PCs" : "one PC") "`r`n" text, elect_diag, "UTF-8"
	if elect_quiet {
		FileAppend (elect_ok ? "PASS" : "FAIL") "`n", "*"
		ExitApp elect_ok ? 0 : 1
	}
	MsgBox (elect_ok ? "The election holds." : "The election is broken.") "`n`n"
		. "Details in settings\election_diag.txt", "Fleet election test", elect_ok ? 0x40040 : 0x40010
	ExitApp elect_ok ? 0 : 1
}

elect_Error(e, *) {
	global elect_diag

	try FileAppend "ERROR " e.Message " at line " e.Line " (" e.What ")`r`n", elect_diag, "UTF-8"
	try elect_Sweep()
	ExitApp 1
	return 1
}
