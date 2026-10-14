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

;A fault goes to a file and into the bench's own log, and AutoHotkey's own
;dialog is suppressed.
;
;Returning 0 here lets that dialog appear, which is right on a desktop and
;fatal anywhere else: it cannot be drawn in a service session, so the process
;sits there for ever with nothing written. That is exactly what happened the
;first time this file was driven headlessly. The file is the record either way,
;and the log line is what somebody sitting at the window reads.
;
;A continuation line has to open with an operator, or AutoHotkey reads it as a
;statement of its own - which is what the leading dot below is for.
OnError(bench_onError)
bench_onError(err, mode) {
	local text := "ERROR: " err.Message " (line " err.Line ") " err.Extra

	try FileAppend text "`r`n" err.Stack "`r`n"
		, "settings\fleet_bench_error.txt", "UTF-8"
	try bench_say(text)
	return 1
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
;the script being run, where it is up to, when it may resume, and the tally
bench_script := [], bench_pc := 0, bench_resumeAt := 0
bench_pass := 0, bench_fail := 0

;Which side of the wire the bench is on.
;
;"macro" stands in for the other macros against a real coordinator. The seats
;are ours and we connect out.
;
;"coordinator" is the other half, and the only way to put pressure on a real
;macro's own share of the work - replicating a configuration, refusing to go
;backwards, handing a better one up, noticing the coordinator has gone. The
;self-test cannot reach any of that, because it speaks the protocol by hand
;instead of driving a macro. Here the seats are the real macros that connected,
;and the same table and the same expect hold for both.
bench_mode := "macro"
bench_listener := 0
;what the heartbeat claims, so a macro can be told a term higher or lower than
;the one it already obeys
bench_term := 1

bench_window()
return

;--- the window --------------------------------------------------------------

bench_window() {
	global BenchGui, BENCH_PORT, BENCH_FIELDS
	;UseTab belongs to the tab control and not to the window, which /Validate
	;cannot tell you - a wrong method name is a runtime lookup, so only running
	;it finds one
	local tabs

	BenchGui := Gui("+Resize", "Fleet bench - port " BENCH_PORT)
	BenchGui.OnEvent("Close", bench_close)
	BenchGui.SetFont("s8 cDefault Norm", "Tahoma")

	BenchGui.Add("Text", "x16 y12 w420 vBenchState", "")
	BenchGui.Add("Text", "x444 y12 w36", "Mode:")
	BenchGui.Add("DropDownList", "x482 y8 w128 vBenchMode Choose1"
		, ["Pretend macros", "Be the coordinator"]).OnEvent("Change", bench_modeChanged)

	BenchGui.SetFont("s8 cDefault Bold", "Tahoma")
	BenchGui.Add("GroupBox", "x8 y40 w602 h206", "Pretend macros")
	BenchGui.SetFont("s8 cDefault Norm", "Tahoma")
	BenchGui.Add("ListView", "x16 y58 w420 h178 -Multi vBenchSeats"
		, ["Row", "Name", "Role", "State", "Said", "Told to go to"])
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

	;Two ways to drive it. By hand is for finding out what happens; a script is
	;for finding out again, and for being handed a list of tests to run.
	tabs := BenchGui.Add("Tab3", "x8 y252 w602 h164 vBenchTabs", ["By hand", "Script"])

	tabs.UseTab(1)
	BenchGui.Add("Text", "x20 y286 w70", "Farming:")
	BenchGui.Add("DropDownList", "x94 y282 w150 vBenchField Choose1", BENCH_FIELDS)
	BenchGui.Add("Button", "x252 y281 w120 h22", "Say the field")
		.OnEvent("Click", bench_sayField)
	BenchGui.SetFont("c808080")
	;measured rather than assumed: at this width the line wraps to two, so it
	;reaches y306 and the row below starts at y310. The first attempt at this
	;panel overlapped an edit box by two pixels.
	BenchGui.Add("Text", "x380 y280 w216"
		, "A main saying this is what sends every fuzzy and tad after it.")
	BenchGui.SetFont("cDefault")

	BenchGui.Add("Text", "x20 y314 w70", "In server:")
	BenchGui.Add("Edit", "x94 y310 w150 h18 vBenchServer", "main")
	BenchGui.Add("Button", "x252 y309 w120 h22", "Say the server")
		.OnEvent("Click", bench_sayServer)
	BenchGui.Add("Text", "x380 y314 w48", "Config:")
	BenchGui.Add("Edit", "x430 y310 w44 h18 Number vBenchCv", "0")
	BenchGui.Add("Text", "x480 y314 w18", "by")
	BenchGui.Add("Edit", "x500 y310 w34 h18 Number vBenchCby", "0")
	BenchGui.Add("Button", "x540 y309 w56 h22", "Beat")
		.OnEvent("Click", bench_sayBeat)

	BenchGui.Add("Text", "x20 y342 w70", "Raw frame:")
	BenchGui.Add("Edit", "x94 y338 w384 h18 vBenchRaw", "")
	BenchGui.Add("Button", "x484 y337 w112 h22", "Send it")
		.OnEvent("Click", bench_sendRaw)
	BenchGui.Add("Button", "x484 y366 w112 h22", "Leave the fleet")
		.OnEvent("Click", bench_sayLeave)
	BenchGui.Add("Button", "x252 y366 w220 h22 vBenchCoord", "Start a coordinator")
		.OnEvent("Click", bench_coordToggle)
	BenchGui.SetFont("c808080")
	BenchGui.Add("Text", "x20 y368 w224"
		, "Anything the protocol can carry, so`nnothing here needs updating.")
	BenchGui.SetFont("cDefault")

	tabs.UseTab(2)
	BenchGui.SetFont("s8", "Consolas")
	BenchGui.Add("Edit", "x20 y278 w432 h128 +Multi -Wrap +VScroll vBenchScript"
		, bench_reference())
	BenchGui.SetFont("s8 cDefault Norm", "Tahoma")
	BenchGui.Add("Button", "x462 y278 w134 h24", "Run")
		.OnEvent("Click", bench_runScript)
	BenchGui.Add("Button", "x462 y306 w134 h24", "Stop")
		.OnEvent("Click", bench_stopScript)
	BenchGui.Add("Button", "x462 y340 w134 h24", "Commands")
		.OnEvent("Click", bench_commands)
	BenchGui.Add("Button", "x462 y368 w134 h24", "Empty the box")
		.OnEvent("Click", bench_clearScript)
	tabs.UseTab()

	BenchGui.SetFont("s8", "Consolas")
	BenchGui.Add("Edit", "x8 y424 w602 h154 ReadOnly -Wrap +VScroll vBenchLog", "")
	BenchGui.SetFont("s8 cDefault Norm", "Tahoma")
	BenchGui.Add("Button", "x8 y586 w100 h26", "Clear the log")
		.OnEvent("Click", bench_clearLog)
	BenchGui.Add("Button", "x510 y586 w100 h26", "Close").OnEvent("Click", bench_close)

	bench_loadRoster()
	bench_drawSeats()
	bench_say("bench ready on port " BENCH_PORT ", secret `"" BENCH_SECRET "`"")
	bench_say("point a macro at this port in Fleet settings, Advanced")
	SetTimer bench_tick, 1000
	SetTimer bench_beat, 10000
	SetTimer bench_step, 100
	BenchGui.Show("w618 h622")
}

bench_close(*) {
	global BenchGui

	SetTimer bench_tick, 0
	SetTimer bench_beat, 0
	SetTimer bench_step, 0
	bench_disconnectAll()
	bench_endCoord()
	if (IsSet(BenchGui) && IsObject(BenchGui))
		BenchGui.Destroy(), BenchGui := ""
	ExitApp 0
}

;Once a second: the state line, and the seat list if anything moved.
bench_tick() {
	global BenchGui, BENCH_PORT, bench_coordPid, bench_mode, bench_listener, bench_term

	if !(IsSet(BenchGui) && IsObject(BenchGui))
		return
	if (bench_mode = "coordinator") {
		try BenchGui["BenchState"].Text := "Port " BENCH_PORT
			. " - " (bench_listener ? "listening as the coordinator, term " bench_term
				: "not listening yet - run: listen")
			. " - " bench_connectedCount() " real macro(s) connected"
	}
	else {
		try BenchGui["BenchState"].Text := "Port " BENCH_PORT
			. " - coordinator " (bench_coordPid && ProcessExist(bench_coordPid)
				? "running, pid " bench_coordPid
				: "not running")
			. " - " bench_connectedCount() " of " bench_seats.Count " connected"
	}
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
				, socket: 0, said: "", told: "", heard: [] }
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
			, seat.socket ? "connected" : "-", seat.said
			, seat.told != "" ? seat.told : "-")
	}
	for _, r in keys
		if (r = pick)
			BenchGui["BenchSeats"].Modify(A_Index, "Select Focus")
	Loop 6
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
		, socket: 0, said: "", told: "", heard: [] }
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

;What a pretend macro does with what it is told.
;
;The rule is that it reacts the way a real macro reacts on the protocol, and
;decides nothing on its own. Both halves matter. Without the first, the test is
;not faithful - a seat that never answers a ping is timed as unreachable, and
;one that ignores a BYE goes on looking connected after it has been thrown out.
;Without the second you could no longer tell what you caused from what the
;bench did, which is the whole value of driving it by hand.
;
;So: answer a ping, obey a refusal, remember an order. Never report a field,
;never leave, never stand for coordinator - those are yours to press.
bench_answer(row, line) {
	global bench_seats
	local frame := fleet_Parse(line), seat

	if !frame
		return 0
	if !bench_seats.Has(row)
		return 0
	seat := bench_seats[row]
	bench_heard(row, frame)
	switch frame.verb {
		case "PING":
			return bench_send(row, fleet_Frame("ACK", Map("id", fleet_Field(frame, "id"))))
		case "GOTO":
			;the thing you are watching for when the real macro is the main, so
			;it goes in the seat list rather than only scrolling past in the log
			seat.told := fleet_Field(frame, "field")
			bench_drawSeats()
		case "BYE":
			bench_say("row " row " was refused: " fleet_Field(frame, "why")
				. (fleet_Field(frame, "final", "") != "" 
					? " (final=" fleet_Field(frame, "final") ")" : ""))
			bench_disconnectRow(row)
	}
	return 1
}

;A real macro beats every ten seconds, and a bench seat that does not is only
;alive by accident - the coordinator's own ping happens to refresh it. Left
;that way, a seat would be written off as quiet the moment pinging stopped,
;and nothing about that would be the fault being tested.
bench_beat() {
	global bench_seats, bench_mode, bench_term, bench_listener
	local r, seat, line

	;as a macro, the beat says we are alive. As the coordinator, it says who is
	;in charge and on which term, which is the frame a macro's whole failover
	;decision turns on - and the one it has never been sent by anything but the
	;real coordinator.
	line := (bench_mode = "coordinator")
		? fleet_Frame("HEARTBEAT", Map("term", bench_term, "row", 1, "at", nowUnix()))
		: fleet_Frame("HEARTBEAT")
	if ((bench_mode = "coordinator") && !bench_listener)
		return 0
	for r, seat in bench_seats
		if seat.socket
			sock_SendLine(seat.socket, line)
	return 1
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

;--- being the coordinator --------------------------------------------------
;
;The other side of the wire, and the only way to put a real macro's own share
;of the work under any pressure at all. Everything it does for itself - keeping
;a replica of the configuration, refusing to write a worse one over a better,
;handing a better one up, noticing the coordinator has gone and standing for
;the job - happens in reaction to frames it is sent, and until now nothing
;could send it a wrong one. The self-test cannot: it speaks the protocol by
;hand rather than driving a macro.
;
;Here the seats are the real macros that connected, which means the same table
;and the same expect and reject work for both modes.

bench_modeChanged(*) {
	global BenchGui, bench_mode

	bench_setMode((BenchGui["BenchMode"].Value = 2) ? "coordinator" : "macro")
}

bench_setMode(which) {
	global bench_mode, BenchGui

	if (bench_mode = which)
		return 0
	;neither half of the wire survives becoming the other one: the sockets face
	;the wrong way and the seats mean something else
	bench_disconnectAll()
	bench_stopListening()
	bench_mode := which
	try BenchGui["BenchMode"].Value := (which = "coordinator") ? 2 : 1
	bench_say("mode: " which)
	if (which = "coordinator")
		bench_say("run: listen - then point a macro at port " BENCH_PORT)
	bench_drawSeats()
	return 1
}

;Exclusive, like the real coordinator's own listen. If a real one already has
;the port, this says so rather than quietly listening alongside it and
;splitting whatever connects.
bench_listen() {
	global bench_listener, BENCH_PORT, bench_mode

	bench_setMode("coordinator")
	if bench_listener
		return 0
	bench_listener := sock_Listen(BENCH_PORT, bench_onServer, 1)
	if !bench_listener {
		bench_say("could not listen on " BENCH_PORT " - something else has it"
			. (sock_lastError != "" ? " (" sock_lastError ")" : ""))
		return 0
	}
	bench_say("listening on " BENCH_PORT " as the coordinator")
	return 1
}

bench_stopListening() {
	global bench_listener, bench_seats
	local r, seat

	if !bench_listener
		return 0
	for r, seat in bench_seats
		if seat.socket
			sock_Close(seat.socket), seat.socket := 0
	sock_Close(bench_listener)
	bench_listener := 0
	bench_say("stopped listening - a macro watching this should take over")
	bench_drawSeats()
	return 1
}

;A real macro arriving. Its row is whatever it claims, which is the point: the
;bench admits anybody, because refusing is a thing to test on purpose rather
;than a thing to do by default.
bench_onServer(s, event, data) {
	global bench_seats, bench_bySocket, bench_term
	local row := bench_bySocket.Has(s) ? bench_bySocket[s] : 0, frame

	if (event = "accept") {
		bench_say("a macro connected, waiting for its HELLO")
		return
	}
	if (event = "close") {
		if (row && bench_seats.Has(row)) {
			bench_seats[row].socket := 0
			bench_say("row " row " went away")
		}
		bench_bySocket.Delete(s)
		bench_drawSeats()
		return
	}
	if (event != "line")
		return
	bench_logFrame(row, "<-", data)
	if !(frame := fleet_Parse(data))
		return
	if (frame.verb = "HELLO") {
		bench_onHello(s, frame)
		return
	}
	if (!row || !bench_seats.Has(row))
		return
	bench_heard(row, frame)
	;the two a macro reports about itself, shown where they can be seen rather
	;than only scrolling past
	if (frame.verb = "FIELD")
		bench_seats[row].said := "farming " fleet_Field(frame, "name")
	else if (frame.verb = "HEARTBEAT")
		bench_seats[row].said := "config v" fleet_Field(frame, "cv", "?")
			. " by " fleet_Field(frame, "cby", "?")
	else if (frame.verb = "SETROW")
		bench_seats[row].said := "handing up v" fleet_Field(frame, "v", "?")
	bench_drawSeats()
}

bench_onHello(s, frame) {
	global bench_seats, bench_bySocket, bench_term, BENCH_SECRET
	local row := fleet_Num(fleet_Field(frame, "row"))

	if !row {
		bench_say("a macro said HELLO without a row")
		return 0
	}
	if (fleet_Field(frame, "secret") != BENCH_SECRET)
		bench_say("row " row " gave the secret `"" fleet_Field(frame, "secret")
			. "`" - the bench wants `"" BENCH_SECRET "`", and is letting it in anyway")
	bench_seats[row] := { row: row, name: fleet_Field(frame, "machine", "a macro")
		, role: "real", socket: s, said: "", told: "", heard: [] }
	bench_bySocket[s] := row
	bench_say("row " row " is here, from " fleet_Field(frame, "machine", "somewhere"))
	;a macro expects to be told who is in charge before anything else
	sock_SendLine(s, fleet_Frame("HEARTBEAT"
		, Map("term", bench_term, "row", 1, "at", nowUnix())))
	bench_drawSeats()
	return 1
}

;What a seat has heard, kept for expect. One place, because both modes need it
;and only one of them used to have it.
bench_heard(row, frame) {
	global bench_seats

	if !bench_seats.Has(row)
		return 0
	bench_seats[row].heard.Push(frame)
	while (bench_seats[row].heard.Length > 200)
		bench_seats[row].heard.RemoveAt(1)
	return 1
}

;serve roster <version> <by> - the bench's own roster, as the configuration,
;at whatever version you say. A version below what the macro holds is the whole
;stale-copy case, staged in one line.
bench_serve(parts) {
	global BENCH_ROSTER, bench_seats, bench_mode
	local what := (parts.Length >= 2) ? StrLower(parts[2]) : ""
	local v := (parts.Length >= 3) ? fleet_Num(parts[3]) : 1
	local by := (parts.Length >= 4) ? fleet_Num(parts[4]) : 1
	local rows, r, e, n, line, seat

	if (bench_mode != "coordinator") {
		bench_say("? serve only means something as the coordinator")
		return
	}
	if (what = "servers") {
		rows := servers_Load(RegExReplace(BENCH_ROSTER, "i)\.ini$", "_servers.ini"))
		n := rows.Count
		for r, e in rows
			bench_toAll(fleet_Frame("SERVER", Map("v", v, "by", by, "n", n
				, "slot", e.slot, "name", e.name, "link", e.link
				, "owner", e.owner, "kind", e.kind)))
		bench_say("served " n " server(s) at v" v " by row " by)
		return
	}
	rows := roster_Load(BENCH_ROSTER)
	n := rows.Count
	;an empty configuration still has to say so, exactly as the real
	;coordinator does, or clearing one would reach nobody
	if !n {
		bench_toAll(fleet_Frame("ROW", Map("v", v, "by", by, "n", 0)))
		bench_say("served an empty roster at v" v " by row " by)
		return
	}
	for r, e in rows {
		bench_toAll(fleet_Frame("ROW", Map("v", v, "by", by, "n", n
			, "row", e.row, "name", e.name, "role", e.role
			, "user", e.user, "machine", e.machine)))
		;and the live half, so the macro's panel has something to draw
		bench_toAll(fleet_Frame("ROSTER", Map("row", e.row, "name", e.name
			, "role", e.role, "state", "online", "machine", e.machine
			, "user", e.user, "server", "", "field", ""
			, "guiding", "", "until", 0, "charge", 0
			, "rtt", 1, "seen", nowUnix(), "cv", v, "cby", by)))
	}
	bench_say("served " n " row(s) at v" v " by row " by)
}

;To every connected macro, which in this mode is every real one.
bench_toAll(line) {
	global bench_seats
	local r, seat, n := 0

	for r, seat in bench_seats
		if seat.socket
			bench_send(r, line), n++
	if !n
		bench_say("nobody is connected, so that went nowhere")
	return n
}

;--- the script runner ------------------------------------------------------
;
;A handful of commands in the fleet's own idiom, so a test can be written down,
;handed over, and run again. Pressing six buttons in the right order is not a
;test anybody repeats, which is the whole reason this exists.
;
;	# a comment
;	seat 2 fuzzy bench fuzzy    make sure row 2 exists, with this role
;	connect all                 or: connect 2
;	disconnect 2
;	clear all                   forget what the seats have heard
;	send 1 FIELD name=pepper    a frame exactly as it travels on the wire
;	field 1 pepper              the same thing, shorter
;	beat 1 9 1                  a heartbeat saying it holds config v9 by row 1
;	leave 2
;	coordinator start           or stop
;	wait 2000
;	expect 2 GOTO field=pepper  pass or fail, and the run says which
;	reject 4 GOTO               passes when it was NOT heard
;	say anything at all         one line in the log
;
;reject exists so that a script's right answer is always "nothing failed". A
;test whose correct outcome is "two failed" is a trap for whoever runs it
;tired, and half of what is worth checking here is that something did not
;happen - a guid is not sent a field, a stale configuration is not taken.
;
;Stepped by a timer rather than run in a loop. A loop with sleeps would work -
;AutoHotkey pumps messages during one - but the window would be dead while it
;ran, and watching the log fill is half of why anybody drives this by hand.

;What the console understands, as the console's own opening text.
;
;In the box you type into rather than in a folder of scripts somebody else
;wrote: a tool you have to be handed tests for is a tool you cannot think
;with. It can be deleted, and the Commands button brings it back.
bench_reference() {
	return "
(
# Type commands below and press Run. A line starting with # is ignored.
#
# either mode
#   mode macro / mode coordinator   which side of the wire the bench is on
#   wait 2000                       milliseconds
#   say anything at all             one line in the log
#   clear all / clear 2             forget what a seat has heard
#   send 2 FIELD name=pepper        a frame exactly as it travels
#   expect 2 GOTO field=pepper      pass or fail, and the log says which
#   reject 2 GOTO                   passes when it was NOT heard
#
# pretending to be the other macros
#   seat 2 fuzzy some name          declare one - do this before the coordinator
#   connect all / connect 2
#   disconnect all / disconnect 2
#   field 2 pepper                  report a field, which is what a main does
#   beat 2 9 1                      a heartbeat claiming config v9 by row 1
#   leave 2
#   coordinator start / coordinator stop
#
# being the coordinator, with a real macro connecting here
#   listen / stop
#   term 4                          what the heartbeat claims
#   serve roster 9 1                the bench roster, at that version and author
#   serve servers 3 1
#   goto all pepper                 or: goto 2 pepper
#   bye 2 1 you are not welcome     final=1, so the macro gives up for good
#   gone 2
)"
}

bench_commands(*) {
	global BenchGui

	BenchGui["BenchScript"].Value := bench_reference()
}

bench_clearScript(*) {
	global BenchGui

	BenchGui["BenchScript"].Value := ""
}

bench_runScript(*) {
	global BenchGui, bench_script, bench_pc, bench_resumeAt, bench_pass, bench_fail

	bench_script := StrSplit(BenchGui["BenchScript"].Value, "`n", "`r")
	bench_pc := 1, bench_resumeAt := 0, bench_pass := 0, bench_fail := 0
	bench_say("--- running " bench_script.Length " lines ---")
}

bench_stopScript(*) {
	global bench_script, bench_pc

	if bench_pc
		bench_say("--- stopped at line " bench_pc " ---")
	bench_script := [], bench_pc := 0
}

;One line per tick at most, and nothing while a wait is running.
bench_step() {
	global bench_script, bench_pc, bench_resumeAt, bench_pass, bench_fail
	local line

	if (!bench_pc || (bench_pc > bench_script.Length)) {
		if bench_pc {
			bench_say("--- done: " bench_pass " passed, " bench_fail " failed ---")
			bench_pc := 0
		}
		return
	}
	if (A_TickCount < bench_resumeAt)
		return
	line := Trim(bench_script[bench_pc])
	bench_pc++
	if ((line = "") || (SubStr(line, 1, 1) = "#"))
		return
	bench_do(line)
}

bench_do(line) {
	global bench_resumeAt
	local parts := StrSplit(line, " "), verb := StrLower(parts[1]), rest

	rest := (StrLen(line) > StrLen(parts[1]))
		? Trim(SubStr(line, StrLen(parts[1]) + 1))
		: ""
	switch verb {
		case "say":
			bench_say(rest)
		case "wait":
			bench_resumeAt := A_TickCount + (fleet_Num(rest) ? fleet_Num(rest) : 1000)
		case "seat":
			bench_doSeat(parts)
		case "connect":
			if (StrLower(rest) = "all")
				bench_connectAll()
			else
				bench_connectRow(fleet_Num(rest))
		case "disconnect":
			if (StrLower(rest) = "all")
				bench_disconnectAll()
			else
				bench_disconnectRow(fleet_Num(rest))
		case "clear":
			bench_doClear(rest)
		case "send":
			bench_doRest(parts, rest, "send")
		case "field":
			bench_doRest(parts, rest, "field")
		case "beat":
			bench_doBeat(parts)
		case "leave":
			bench_send(fleet_Num(rest), fleet_Frame("LEAVE"))
		case "coordinator":
			if (StrLower(rest) = "stop")
				bench_endCoord()
			else
				bench_startCoord()
		case "expect":
			bench_doExpect(parts, rest, 1)
		case "reject":
			bench_doExpect(parts, rest, 0)
		case "mode":
			bench_setMode((StrLower(rest) = "coordinator") ? "coordinator" : "macro")
		case "listen":
			bench_listen()
		case "stop":
			bench_stopListening()
		case "term":
			bench_doTerm(rest)
		case "serve":
			bench_serve(parts)
		case "goto":
			bench_doGoto(parts, rest)
		case "bye":
			bench_doBye(parts, rest)
		case "gone":
			bench_toAll(fleet_Frame("GONE", Map("row", fleet_Num(rest))))
		default:
			bench_say("? unknown command: " line)
	}
}

;term <n> - what the heartbeat claims. A term below the one a macro already
;obeys should be ignored by it; one above should make it follow this bench.
bench_doTerm(rest) {
	global bench_term

	bench_term := fleet_Num(rest) ? fleet_Num(rest) : 1
	bench_say("term is now " bench_term " - it rides on the next beat")
}

;goto <row|all> <field>, which is the order a resident acts on. The field name
;takes the rest of the line because half of them have a space in.
bench_doGoto(parts, rest) {
	local who := (parts.Length >= 2) ? parts[2] : "", field

	field := (StrLen(rest) > StrLen(who)) ? Trim(SubStr(rest, StrLen(who) + 1)) : ""
	if (field = "") {
		bench_say("? goto needs a row or all, and a field")
		return
	}
	if (StrLower(who) = "all") {
		bench_toAll(fleet_Frame("GOTO", Map("field", field)))
		return
	}
	bench_send(fleet_Num(who), fleet_Frame("GOTO", Map("field", field)))
}

;bye <row> <final 0|1> <why...> - the refusal, and whether the macro should
;treat it as something it can come back from. Getting that distinction wrong
;once emptied a whole fleet, so it is worth being able to send both.
bench_doBye(parts, rest) {
	local row := fleet_Num(parts[2]), final, why := "", i

	if !row {
		bench_say("? bye needs a row")
		return
	}
	final := (parts.Length >= 3) ? fleet_Num(parts[3]) : 1
	i := 4
	while (i <= parts.Length)
		why .= (why = "" ? "" : " ") parts[i], i++
	if (why = "")
		why := "the bench says so"
	bench_send(row, fleet_Frame("BYE", Map("why", why, "final", final)))
}

;seat <row> <role> [name...]
bench_doSeat(parts) {
	global bench_seats, BENCH_ROSTER
	local row := fleet_Num(parts[2]), role, name := "", i, rows

	if !row {
		bench_say("? seat needs a row number")
		return
	}
	role := (parts.Length >= 3) ? StrLower(parts[3]) : "fuzzy"
	i := 4
	while (i <= parts.Length)
		name .= (name = "" ? "" : " ") parts[i], i++
	if (name = "")
		name := "bench " row
	rows := roster_Load(BENCH_ROSTER)
	rows[row] := { row: row, name: name, role: role, user: ""
		, machine: A_ComputerName }
	roster_Save(BENCH_ROSTER, rows, bench_rosterVersion() + 1, 1)
	if bench_seats.Has(row)
		bench_seats[row].name := name, bench_seats[row].role := role
	else
		bench_seats[row] := { row: row, name: name, role: role
			, socket: 0, said: "", told: "", heard: [] }
	bench_say("seat " row " is " name " (" role ")")
	bench_drawSeats()
}

bench_doClear(what) {
	global bench_seats
	local r, seat

	for r, seat in bench_seats
		if ((StrLower(what) = "all") || (r = fleet_Num(what)))
			seat.heard := [], seat.told := ""
	bench_drawSeats()
}

;send <row> <frame verbatim>, and field <row> <name>, which both take
;everything after the row number as one value - a field name has spaces in it
;and so does half the protocol.
bench_doRest(parts, rest, what) {
	global bench_seats
	local row := fleet_Num(parts[2]), tail

	tail := (StrLen(rest) > StrLen(parts[2]))
		? Trim(SubStr(rest, StrLen(parts[2]) + 1))
		: ""
	if (!row || (tail = "")) {
		bench_say("? " what " needs a row and something to send")
		return
	}
	if (what = "send") {
		bench_send(row, tail)
		return
	}
	if bench_seats.Has(row)
		bench_seats[row].said := "farming " tail
	bench_send(row, fleet_Frame("FIELD", Map("name", tail)))
	bench_drawSeats()
}

;beat <row> [version] [by]
bench_doBeat(parts) {
	local row := fleet_Num(parts[2])

	if !row {
		bench_say("? beat needs a row")
		return
	}
	bench_send(row, fleet_Frame("HEARTBEAT"
		, Map("cv", (parts.Length >= 3) ? fleet_Num(parts[3]) : 0
		, "cby", (parts.Length >= 4) ? fleet_Num(parts[4]) : 0)))
}

;expect <row> <VERB> [field=value ...] - and reject, which wants the opposite.
;
;Against everything that seat has heard since the last clear, so a script reads
;as a sequence rather than as a race. A failure does not stop the run: the
;point of a list of tests is to learn everything that is wrong in one pass.
bench_doExpect(parts, rest, wanted) {
	global bench_seats, bench_pass, bench_fail
	local row := fleet_Num(parts[2]), want, i, frame, k, v, at, ok, desc
	local found := 0

	if (!row || (parts.Length < 3) || !bench_seats.Has(row)) {
		bench_say("FAIL  needs a known row and a verb: " rest)
		bench_fail++
		return
	}
	;A seat that is not connected heard nothing, which would make every reject
	;pass for the wrong reason - and did, the first time this ran. Nothing is
	;proved by a macro that was not there.
	if !bench_seats[row].socket {
		bench_say("FAIL  row " row " is not connected, so this proves nothing")
		bench_fail++
		return
	}
	want := StrUpper(parts[3])
	;the row number is already in the message, so the description starts after it
	desc := want
	i := 4
	while (i <= parts.Length)
		desc .= " " parts[i], i++
	for _, frame in bench_seats[row].heard {
		if (frame.verb != want)
			continue
		ok := 1, i := 4
		while (i <= parts.Length) {
			if (at := InStr(parts[i], "=")) {
				k := SubStr(parts[i], 1, at - 1)
				v := fleet_Unescape(SubStr(parts[i], at + 1))
				if (fleet_Field(frame, k) != v)
					ok := 0
			}
			i++
		}
		if ok {
			found := 1
			break
		}
	}
	if (!!found = !!wanted) {
		bench_pass++
		bench_say("PASS  row " row (wanted ? " heard " : " was not sent ") desc)
		return
	}
	bench_fail++
	bench_say("FAIL  row " row (wanted ? " never heard " : " was sent ") desc)
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
