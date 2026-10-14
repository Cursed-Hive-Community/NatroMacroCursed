#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off

;The fleet bench - a fleet you can drive by hand
;
;	.\submacros\AutoHotkey64.exe /script .\submacros\FleetBench.ahk
;
;Testing the fleet by hand meant setting up every account on every machine
;before anything could be tried, which is why almost none of it was ever tried.
;This stands in for all of them but one: it connects as however many pretend
;macros you like, says whatever you tell it to say, and shows every frame that
;crosses the wire in either direction. One of these and one real macro with the
;game running is enough to watch a feature actually work.
;
;It proves less than a real fleet and it says so - there is no Roblox here, no
;second machine, and nothing walks anywhere. What it does is put the
;architecture under pressure from something other than its own self-test, and
;show what the protocol is doing while it happens.
;
;It never touches the real configuration. Its own port, its own roster file,
;its own coordinator. A bench that could corrupt the fleet it is meant to test
;would be worse than no bench, so this one cannot reach it: to use it, point a
;macro at the bench's port in the Fleet advanced window.

SetWorkingDir A_ScriptDir "\.."

#Include "%A_ScriptDir%\..\lib"
#Include "Socket.ahk"
#Include "FleetProtocol.ahk"
#Include "FleetRoster.ahk"
#Include "FleetServers.ahk"
#Include "nowUnix.ahk"

;Every function here carries the bench_ prefix, which is the house convention
;and also what stops the collision this file was born with: a builder called
;BenchGUI and the window it builds called BenchGui are one identifier to
;AutoHotkey, and the assignment destroys the function. The prefix is what saves
;the Fleet code from the same thing.

;An error here cannot draw a dialog when this is started over SSH, and would
;hang with nothing written. It can draw one on a desktop, which is where this
;is used - so both: the file always, the dialog when there is somebody to see.
OnError(bench_error)
bench_error(err, mode) {
	;a continuation line has to open with an operator or AutoHotkey reads it as a
	;statement of its own - which is what the leading dot is doing here
	try FileAppend "ERROR: " err.Message "`r`nline " err.Line "`r`n" err.Extra
		. "`r`n" err.Stack, "settings\fleet_bench_error.txt", "UTF-8"
	return 0
}

;A port of its own, well clear of the real fleet's 47600. Nothing here can
;reach a real coordinator unless somebody types this number into one.
BENCH_PORT := 47700
BENCH_SECRET := "bench"
BENCH_ROSTER := A_WorkingDir "\settings\fleet_bench_roster.ini"
BENCH_LOGFILE := A_WorkingDir "\settings\fleet_bench.txt"
;the log in the window is capped: it is read by scrolling, and a hundred
;thousand lines is not read at all. The file keeps everything.
BENCH_LOG_LINES := 400

;The fields a macro can be told it is farming. Hardcoded rather than read from
;FieldDefault, which lives inside the macro and is not ours to reach from here.
BENCH_FIELDS := ["sunflower", "dandelion", "mushroom", "blue flower", "clover"
	, "strawberry", "spider", "bamboo", "pineapple", "stump", "cactus"
	, "pumpkin", "pine tree", "rose", "mountain top", "pepper", "coconut"]

;row -> what this pretend macro is and what its socket is doing
bench_seats := Map()
;socket -> row, for the reverse lookup a frame needs
bench_bySocket := Map()
;the newest lines last, as a window reads
bench_log := []
bench_coordPid := 0

bench_gUI()
return

;--- the window --------------------------------------------------------------

bench_gUI() {
	global BenchGui, BENCH_PORT, BENCH_FIELDS

	BenchGui := Gui("+Resize", "Fleet bench - port " BENCH_PORT)
	BenchGui.OnEvent("Close", bench_close)
	BenchGui.SetFont("s8 cDefault Norm", "Tahoma")

	BenchGui.Add("Text", "x16 y12 w450 vBenchState", "")
	BenchGui.Add("Button", "x470 y8 w140 h24 vBenchCoord", "Start a coordinator")
		.OnEvent("Click", bench_coordToggle)

	BenchGui.SetFont("s8 cDefault Bold", "Tahoma")
	BenchGui.Add("GroupBox", "x8 y40 w602 h206", "Pretend macros")
	BenchGui.SetFont("s8 cDefault Norm", "Tahoma")
	BenchGui.Add("ListView", "x16 y58 w420 h178 -Multi vBenchSeats"
		, ["Row", "Name", "Role", "State", "Last said"])
	BenchGui.Add("Button", "x444 y58 w160 h24", "Add a macro")
		.OnEvent("Click", bench_addSeat)
	BenchGui.Add("Button", "x444 y86 w160 h24", "Remove this one")
		.OnEvent("Click", bench_removeSeat)
	BenchGui.Add("Button", "x444 y122 w160 h24", "Connect this one")
		.OnEvent("Click", bench_connectOne)
	BenchGui.Add("Button", "x444 y150 w160 h24", "Disconnect this one")
		.OnEvent("Click", bench_disconnectOne)
	BenchGui.Add("Button", "x444 y186 w160 h24", "Connect them all")
		.OnEvent("Click", bench_connectAll)
	BenchGui.Add("Button", "x444 y214 w160 h24", "Disconnect them all")
		.OnEvent("Click", bench_disconnectAll)

	;Everything here acts on the macro selected above, which is the whole
	;reason the seats are a list rather than six copies of this panel.
	BenchGui.SetFont("s8 cDefault Bold", "Tahoma")
	BenchGui.Add("GroupBox", "x8 y252 w602 h128", "Make the selected macro say something")
	BenchGui.SetFont("s8 cDefault Norm", "Tahoma")

	BenchGui.Add("Text", "x18 y274 w70", "Farming:")
	BenchGui.Add("DropDownList", "x92 y270 w150 vBenchField Choose1", BENCH_FIELDS)
	BenchGui.Add("Button", "x250 y269 w120 h22", "Say the field")
		.OnEvent("Click", bench_sayField)
	BenchGui.SetFont("c808080")
	;y268 and not y274: at w226 this wraps to two lines, so it reaches y294 -
	;and the Config edit below starts at y298. Four pixels of clearance,
	;measured rather than assumed, because the first attempt overlapped by two.
	BenchGui.Add("Text", "x378 y268 w226"
		, "A main saying this is what sends every fuzzy and tad after it.")
	BenchGui.SetFont("cDefault")

	BenchGui.Add("Text", "x18 y302 w70", "In server:")
	BenchGui.Add("Edit", "x92 y298 w150 h18 vBenchServer", "main")
	BenchGui.Add("Button", "x250 y297 w120 h22", "Say the server")
		.OnEvent("Click", bench_sayServer)
	BenchGui.Add("Text", "x378 y302 w60", "Config:")
	BenchGui.Add("Edit", "x430 y298 w44 h18 Number vBenchCv", "0")
	BenchGui.Add("Text", "x480 y302 w20", "by")
	BenchGui.Add("Edit", "x500 y298 w34 h18 Number vBenchCby", "0")
	BenchGui.Add("Button", "x540 y297 w64 h22", "Beat")
		.OnEvent("Click", bench_sayBeat)

	BenchGui.Add("Text", "x18 y330 w70", "Raw frame:")
	BenchGui.Add("Edit", "x92 y326 w390 h18 vBenchRaw", "")
	BenchGui.Add("Button", "x490 y325 w114 h22", "Send it")
		.OnEvent("Click", bench_sendRaw)
	BenchGui.SetFont("c808080")
	BenchGui.Add("Text", "x18 y352 w380"
		, "Anything the protocol can carry, so this window never needs updating`nwhen a verb is added. Try: GUIDING field=pepper until=0")
	BenchGui.SetFont("cDefault")
	BenchGui.Add("Button", "x490 y351 w114 h22", "Leave the fleet")
		.OnEvent("Click", bench_sayLeave)

	BenchGui.SetFont("s8", "Consolas")
	BenchGui.Add("Edit", "x8 y388 w602 h190 ReadOnly -Wrap +VScroll vBenchLog", "")
	BenchGui.SetFont("s8 cDefault Norm", "Tahoma")
	BenchGui.Add("Button", "x8 y586 w100 h26", "Clear the log")
		.OnEvent("Click", bench_clearLog)
	BenchGui.Add("Button", "x510 y586 w100 h26", "Close").OnEvent("Click", bench_close)

	bench_loadRoster()
	bench_drawSeats()
	bench_say("bench ready on port " BENCH_PORT ", secret `"" BENCH_SECRET "`"")
	bench_say("point a macro at this port in Fleet settings, Advanced")
	SetTimer bench_tick, 1000
	BenchGui.Show("w618 h622")
}

bench_close(*) {
	global BenchGui

	SetTimer bench_tick, 0
	bench_disconnectAll()
	bench_endCoord()
	if (IsSet(BenchGui) && IsObject(BenchGui))
		BenchGui.Destroy(), BenchGui := ""
	ExitApp 0
}

;Once a second: the state line, and the seat list if anything moved.
bench_tick() {
	global BenchGui, BENCH_PORT, bench_coordPid

	if !(IsSet(BenchGui) && IsObject(BenchGui))
		return
	try BenchGui["BenchState"].Text := "Port " BENCH_PORT
		. " - coordinator " (bench_coordPid && ProcessExist(bench_coordPid)
			? "running, pid " bench_coordPid
			: "not running")
		. " - " bench_connectedCount() " of " bench_seats.Count " connected"
	try BenchGui["BenchCoord"].Text := (bench_coordPid && ProcessExist(bench_coordPid))
		? "Stop the coordinator"
		: "Start a coordinator"
	bench_drawSeats()
}

bench_connectedCount() {
	global bench_seats
	local r, seat, n := 0

	for r, seat in bench_seats
		if seat.socket
			n++
	return n
}

;--- the pretend macros ------------------------------------------------------

;The bench writes its own roster, which is also how a macro under test gets a
;row to claim: add a seat here, and the coordinator admits that row.
bench_loadRoster() {
	global bench_seats, BENCH_ROSTER
	local rows, r, e

	rows := roster_Load(BENCH_ROSTER)
	if !rows.Count {
		;row one is the main, because a fleet with no main has nothing to
		;follow, and following is the first thing anybody wants to watch
		rows[1] := { row: 1, name: "bench main", role: "main", user: ""
			, machine: A_ComputerName }
		rows[2] := { row: 2, name: "bench fuzzy", role: "fuzzy", user: ""
			, machine: A_ComputerName }
		roster_Save(BENCH_ROSTER, rows, 1, 1)
	}
	for r, e in rows
		if !bench_seats.Has(r)
			bench_seats[r] := { row: r, name: e.name, role: e.role
				, socket: 0, said: "" }
	return 1
}

bench_drawSeats() {
	global BenchGui, bench_seats
	local keys := [], r, seat, pick

	if !(IsSet(BenchGui) && IsObject(BenchGui))
		return
	;the selection has to survive a redraw, or every tick would lose it and
	;none of the buttons would ever act on what you picked
	pick := bench_selectedRow()
	for r, _ in bench_seats
		keys.Push(r)
	roster_Sort(keys)
	BenchGui["BenchSeats"].Delete()
	for _, r in keys {
		seat := bench_seats[r]
		BenchGui["BenchSeats"].Add(, r, seat.name, seat.role
			, seat.socket ? "connected" : "-", seat.said)
	}
	for _, r in keys
		if (r = pick)
			BenchGui["BenchSeats"].Modify(A_Index, "Select Focus")
	Loop 5
		BenchGui["BenchSeats"].ModifyCol(A_Index, "AutoHdr")
	return 1
}

bench_selectedRow() {
	global BenchGui, bench_seats
	local at := 0, keys := [], r

	try at := BenchGui["BenchSeats"].GetNext()
	if !at
		return 0
	for r, _ in bench_seats
		keys.Push(r)
	roster_Sort(keys)
	return (at <= keys.Length) ? keys[at] : 0
}

bench_addSeat(*) {
	global bench_seats, BENCH_ROSTER
	local rows, row, name, role

	name := bench_ask("Name for the new pretend macro", "bench " (bench_seats.Count + 1))
    if (name = "")
		return
	role := bench_ask("Role - main, fuzzy, tad, guid or atk", "fuzzy")
	if (role = "")
		return
	rows := roster_Load(BENCH_ROSTER)
	row := 1
	for r, _ in rows
		if (r >= row)
			row := r + 1
	rows[row] := { row: row, name: name, role: StrLower(role), user: ""
		, machine: A_ComputerName }
	;the next version, because the coordinator compares them - the bench has to
	;speak the protocol properly or it is testing something else
	roster_Save(BENCH_ROSTER, rows, bench_rosterVersion() + 1, 1)
	bench_seats[row] := { row: row, name: name, role: StrLower(role)
		, socket: 0, said: "" }
	bench_say("added row " row " (" name ", " role ")")
	bench_drawSeats()
}

bench_removeSeat(*) {
	global bench_seats, BENCH_ROSTER
	local row := bench_selectedRow(), rows

	if !row
		return
	bench_disconnectRow(row)
	rows := roster_Load(BENCH_ROSTER)
	rows.Delete(row)
	roster_Save(BENCH_ROSTER, rows, bench_rosterVersion() + 1, 1)
	bench_seats.Delete(row)
	bench_say("removed row " row)
	bench_drawSeats()
}

bench_rosterVersion() {
	global BENCH_ROSTER

	return fleet_ConfigVersion(BENCH_ROSTER).version
}

;A one-line prompt. InputBox rather than a window of its own: this is asked
;twice in the life of a bench session.
bench_ask(prompt, preset) {
	local answer := InputBox(prompt, "Fleet bench", "w320 h130", preset)

	return (answer.Result = "OK") ? Trim(answer.Value) : ""
}

bench_connectOne(*) {
	bench_connectRow(bench_selectedRow())
}
bench_disconnectOne(*) {
	bench_disconnectRow(bench_selectedRow())
}
bench_connectAll(*) {
	global bench_seats
	local r

	for r, _ in bench_seats
		bench_connectRow(r)
}
bench_disconnectAll(*) {
	global bench_seats
	local r

	for r, _ in bench_seats
		bench_disconnectRow(r)
}

bench_connectRow(row) {
	global bench_seats, BENCH_PORT
	local seat

	if (!row || !bench_seats.Has(row))
		return 0
	seat := bench_seats[row]
	if seat.socket
		return 0
	seat.socket := sock_Connect("127.0.0.1", BENCH_PORT, bench_onSocket)
	if !seat.socket {
		bench_say("row " row " could not open a socket")
		return 0
	}
	bench_bySocket[seat.socket] := row
	bench_say("row " row " connecting")
	bench_drawSeats()
	return 1
}

bench_disconnectRow(row) {
	global bench_seats, bench_bySocket
	local seat

	if (!row || !bench_seats.Has(row))
		return 0
	seat := bench_seats[row]
	if !seat.socket
		return 0
	bench_bySocket.Delete(seat.socket)
	sock_Close(seat.socket)
	seat.socket := 0
	bench_say("row " row " disconnected")
	bench_drawSeats()
	return 1
}

;--- the wire ----------------------------------------------------------------

bench_onSocket(s, event, data) {
	global bench_bySocket, bench_seats
	local row := bench_bySocket.Has(s) ? bench_bySocket[s] : 0

	if (event = "connect") {
		if (data != "") {
			bench_say("row " row " could not connect: error " data)
			bench_disconnectRow(row)
			return
		}
		bench_send(row, fleet_Frame("HELLO", Map("row", row
			, "secret", BENCH_SECRET, "machine", A_ComputerName)))
		return
	}
	if (event = "close") {
		bench_say("row " row " was closed by the other end")
		if (row && bench_seats.Has(row)) {
			bench_bySocket.Delete(s)
			bench_seats[row].socket := 0
		}
		bench_drawSeats()
		return
	}
	if (event != "line")
		return
	bench_logFrame(row, "<-", data)
	bench_answer(row, data)
}

;The only frame a pretend macro has to answer. Everything else is for looking
;at: a bench that acted on its own would stop being a window onto the wire.
bench_answer(row, line) {
	local frame := fleet_Parse(line)

	if (!frame || (frame.verb != "PING"))
		return 0
	return bench_send(row, fleet_Frame("ACK", Map("id", fleet_Field(frame, "id"))))
}

bench_send(row, line) {
	global bench_seats

	if (!row || !bench_seats.Has(row) || !bench_seats[row].socket)
		return 0
	bench_logFrame(row, "->", line)
	return sock_SendLine(bench_seats[row].socket, line)
}

;--- saying things -----------------------------------------------------------

bench_sayField(*) {
	global BenchGui, bench_seats
	local row := bench_selectedRow(), field

	if !bench_ready(row)
		return
	field := BenchGui["BenchField"].Text
	bench_seats[row].said := "farming " field
	bench_send(row, fleet_Frame("FIELD", Map("name", field)))
	bench_drawSeats()
}

bench_sayServer(*) {
	global BenchGui, bench_seats
	local row := bench_selectedRow(), server

	if !bench_ready(row)
		return
	server := Trim(BenchGui["BenchServer"].Value)
	bench_seats[row].said := "in " server
	bench_send(row, fleet_Frame("STATE", Map("server", server)))
	bench_drawSeats()
}

;A heartbeat carrying whichever configuration version you say this macro holds,
;which is how the stale-copy case is staged without unplugging anything.
bench_sayBeat(*) {
	global BenchGui
	local row := bench_selectedRow()

	if !bench_ready(row)
		return
	bench_send(row, fleet_Frame("HEARTBEAT"
		, Map("cv", BenchGui["BenchCv"].Value, "cby", BenchGui["BenchCby"].Value)))
}

bench_sayLeave(*) {
	local row := bench_selectedRow()

	if !bench_ready(row)
		return
	bench_send(row, fleet_Frame("LEAVE"))
}

bench_sendRaw(*) {
	global BenchGui
	local row := bench_selectedRow(), raw := Trim(BenchGui["BenchRaw"].Value)

	if (!bench_ready(row) || (raw = ""))
		return
	bench_send(row, raw)
}

bench_ready(row) {
	global bench_seats

	if (!row || !bench_seats.Has(row)) {
		bench_say("pick a macro in the list first")
		return 0
	}
	if !bench_seats[row].socket {
		bench_say("row " row " is not connected")
		return 0
	}
	return 1
}

;--- the coordinator --------------------------------------------------------

;The real one, on the bench's port and reading the bench's roster. Not a
;pretend coordinator: the point is to test against the process that will
;actually be running.
bench_coordToggle(*) {
	global bench_coordPid

	if (bench_coordPid && ProcessExist(bench_coordPid)) {
		bench_endCoord()
		return
	}
	bench_startCoord()
}

bench_startCoord() {
	global bench_coordPid, BENCH_PORT, BENCH_SECRET, BENCH_ROSTER

	try
		Run '"' A_AhkPath '" /script "' A_ScriptDir '\Fleet.ahk" ' BENCH_PORT
			. ' "' BENCH_SECRET '" 1 1 "' BENCH_ROSTER '"', , "Hide", &bench_coordPid
	catch as e {
		bench_coordPid := 0
		bench_say("could not start a coordinator: " e.Message)
		return 0
	}
	bench_say("coordinator started, pid " bench_coordPid
		. " - its log is beside the bench roster")
	return 1
}

bench_endCoord() {
	global bench_coordPid

	if (bench_coordPid && ProcessExist(bench_coordPid)) {
		try ProcessClose(bench_coordPid)
		bench_say("coordinator " bench_coordPid " stopped")
	}
	bench_coordPid := 0
	return 1
}

;--- the log ----------------------------------------------------------------

;Every frame, both directions, with the row it belongs to. This is half the
;value of the bench: the fleet's own log says what the coordinator decided, and
;this says what was actually on the wire.
bench_logFrame(row, arrow, line) {
	bench_say(Format("{:-4} {} {}", "r" row, arrow, line))
}

bench_say(text) {
	global BenchGui, bench_log, BENCH_LOG_LINES, BENCH_LOGFILE
	local stamp := FormatTime(A_Now, "HH:mm:ss") "  "

	bench_log.Push(stamp text)
	while (bench_log.Length > BENCH_LOG_LINES)
		bench_log.RemoveAt(1)
	try FileAppend stamp text "`r`n", BENCH_LOGFILE, "UTF-8"
	if !(IsSet(BenchGui) && IsObject(BenchGui))
		return
	try {
		BenchGui["BenchLog"].Value := bench_join(bench_log)
		;the newest line is the one worth seeing, and an Edit does not scroll
		;itself - 0x115 with 7 is WM_VSCROLL, SB_BOTTOM
		SendMessage 0x115, 7, 0, BenchGui["BenchLog"]
	}
}

bench_clearLog(*) {
	global bench_log

	bench_log := []
	bench_say("log cleared")
}

bench_join(arr) {
	local out := "", v

	for _, v in arr
		out .= v "`r`n"
	return out
}
