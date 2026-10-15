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
	;Carrying on is right when somebody is watching the log and can decide what
	;to do about it. It is wrong in an automated run, where it leaves a process
	;alive for ever holding the port - which is then the next run's failure,
	;with nothing to connect the two. That has already happened here once.
	if bench_quiet() {
		try FileAppend "FAIL`n", "*"
		ExitApp 2
	}
	return 1
}

;Where the bench listens, and the one setting that lets a real macro join
;without being reconfigured.
;
;47700 by default, well clear of the real fleet's 47600: the two can run side
;by side and nothing here can reach a real coordinator. Set it to 47600 with
;the port command and a real macro needs no changes at all - it listens for
;beacons on 47601 and knocks on 47600, which is where this now is. The price
;is that the bench and a real fleet can no longer share the machine, and the
;exclusive bind is what says so rather than the two of them splitting
;whatever connects.
bench_port := 47700
BENCH_SECRET := "bench"
;The identity of the bench's fleet. A macro bound to it keeps this fleet's
;configuration under settings\fleet\benchfleet\, so nothing the bench does
;can reach the files of the real fleet that macro also belongs to - which is
;what made a real macro safe to invite in the first place.
;
;Fixed rather than minted, because it has to be recognisable: a folder called
;benchfleet is one anybody can delete without wondering what it was.
BENCH_FLEET_ID := "benchfleet"
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
;row -> what the bench knows about that seat.
;
;A seat has up to two sockets, and conflating them was a real fault: a fake
;seat connecting to the bench's own coordinator was reclassified as a real
;macro by its own HELLO, and became undrivable. So the two directions are
;named separately.
;
;  socket  the bench speaking AS that macro. Only a fake seat has one.
;  back    the bench speaking TO that macro, as the coordinator. Both kinds
;          have one while the bench is listening.
;
;A fake seat talking to the bench's own listener therefore has both, which is
;exactly right: it is a macro and the bench is its coordinator, and the bench
;is both ends of that conversation.
bench_seats := Map()
;socket -> row, for the reverse lookup a frame needs
bench_bySocket := Map()
;the newest lines last, as a window reads
bench_log := []
bench_coordPid := 0
;the script being run, where it is up to, when it may resume, and the tally
bench_script := [], bench_pc := 0, bench_resumeAt := 0
bench_pass := 0, bench_fail := 0

;Who is coordinating this fleet. Three answers, and the bench picks:
;
;	"none"   nothing is; the fakes will sit there failing to connect
;	"real"   a real Fleet.ahk the bench started, on the bench's port
;	"bench"  the bench itself, listening
;
;It is a choice and not a mode, because the rest does not change with it. The
;bench always has its fake macros, real macros can always join the same port,
;and the two sit in one fleet together - which is the only arrangement that
;puts both halves under pressure at once. A real coordinator plus fakes tests
;what the coordinator does with a crowd; the bench coordinating plus a real
;macro tests what that macro does when it is told something wrong; both at the
;same time tests the crowd and the lie together.
bench_coord := "none"
bench_listener := 0
;what the heartbeat claims, so a macro can be told a term higher or lower than
;the one it already obeys
bench_term := 1
;The beacon, so a real macro finds this bench the way it finds any fleet:
;by hearing it, not by being told an address. Without one, joining the bench
;meant typing a port and an address into the macro - which is exactly the
;thing binding exists to avoid, and which nobody would have discovered on
;their own.
bench_beacon := 0
;Until when the bench accepts macros it has never seen. Shut by default: an
;open door is how a real macro ends up in the bench fleet, and that should be
;a thing somebody asked for.
bench_bindUntil := 0

;Bound to an ephemeral port, like the coordinator's, so it never competes
;with the listening port. Opened once: a socket is cheap and a bench that
;could not be found is the whole problem being fixed here.
bench_beacon := sock_UdpListen(0, (*) => 0)
if !bench_beacon
	bench_say("no UDP socket - a real macro will have to be given this"
		. " address by hand")
SetTimer bench_sendBeacon, 2000

bench_window()
;Driven without a mouse, when something hands it a file of commands.
;
;That is how the bench itself gets checked by the same harness as everything
;else - and it is also how a scenario worth keeping gets kept: in a file you
;wrote, not in a dropdown of tests somebody else wrote for you.
bench_args()
return

;--- the window --------------------------------------------------------------

bench_window() {
	global BenchGui, bench_port, BENCH_FIELDS
	;UseTab belongs to the tab control and not to the window, which /Validate
	;cannot tell you - a wrong method name is a runtime lookup, so only running
	;it finds one
	local tabs

	BenchGui := Gui("+Resize", "Fleet bench - port " bench_port)
	BenchGui.OnEvent("Close", bench_close)
	BenchGui.SetFont("s8 cDefault Norm", "Tahoma")

	;w380 and not w420: the state line runs to sixty-odd characters and the
	;label beside it starts at 400, so the wider version overlapped it by
	;thirty-two pixels. Measured, after the first attempt did.
	BenchGui.Add("Text", "x16 y12 w380 vBenchState", "")
	;Not "mode": the bench always has its fake macros and real ones can always
	;join. The only choice is who coordinates them.
	BenchGui.Add("Text", "x400 y12 w78", "Coordinated by:")
	BenchGui.Add("DropDownList", "x482 y8 w128 vBenchCoordBy Choose1"
		, ["nobody", "a real Fleet.ahk", "this bench"]).OnEvent("Change", bench_coordChanged)

	BenchGui.SetFont("s8 cDefault Bold", "Tahoma")
	BenchGui.Add("GroupBox", "x8 y40 w602 h206", "Pretend macros")
	BenchGui.SetFont("s8 cDefault Norm", "Tahoma")
	;Kind first after the row, because it is what decides whether a command can
	;act on that seat at all: a fake one you drive, a real one you only send to.
	BenchGui.Add("ListView", "x16 y58 w420 h178 -Multi vBenchSeats"
		, ["Row", "Kind", "Name", "Role", "State", "Said", "Told"])
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
bench_say("bench ready on port " bench_port ", secret `"" BENCH_SECRET "`"")
bench_say("to let a real macro in: accept - and set its Fleet port to "
	. bench_port ", or run: port 47600")
	bench_say("point a macro at this port in Fleet settings, Advanced")
	SetTimer bench_tick, 1000
	SetTimer bench_beat, 10000
	SetTimer bench_step, 100
	BenchGui.Show("w618 h622")
}

;A file of commands as the first argument is loaded into the box and run.
;/quiet makes the run answer on standard output and exit when it finishes,
;which is the shape the other self-tests already answer in.
bench_args() {
	global BenchGui
	local path := "", text := "", a

	for _, a in A_Args
		if (SubStr(a, 1, 1) != "/")
			path := a
	if ((path = "") || !FileExist(path))
		return 0
	try text := FileRead(path, "UTF-8")
	if (text = "")
		return 0
	BenchGui["BenchScript"].Value := text
	bench_say("running " path)
	;A run driven from outside has to end by itself, pass or hang. Killing the
	;ssh connection that started it does not kill it - that has already left a
	;process on the test machine which then interfered with a later run.
	if bench_quiet()
		SetTimer bench_giveUp, -90000
	bench_runScript()
	return 1
}

;The script never finished. Said out loud and then gone, because a bench left
;holding a port is the next run's failure and nobody would connect the two.
bench_giveUp() {
	global bench_pc

	if !bench_pc
		return 0
	bench_say("--- gave up: still on line " bench_pc " after 90 seconds ---")
	FileAppend "FAIL`n", "*"
	ExitApp 1
}

bench_quiet() {
	local a

	for _, a in A_Args
		if (a = "/quiet")
			return 1
	return 0
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
	global BenchGui, bench_port, bench_coordPid, bench_coord, bench_listener, bench_term

	if !(IsSet(BenchGui) && IsObject(BenchGui))
		return
	try BenchGui["BenchState"].Text := "Port " bench_port " - "
		. bench_coordWord() " - " bench_fakeCount() " fake, "
		. bench_realCount() " real, " bench_connectedCount() " connected"
	try BenchGui["BenchCoord"].Text := (bench_coordPid && ProcessExist(bench_coordPid))
		? "Stop the coordinator"
		: "Start a coordinator"
	bench_drawSeats()
}

;One seat, built in one place.
;
;Three places used to write this object out by hand, and when a second socket
;was added to it two of them were not updated - so a seat loaded from the
;roster file had no "back" property and the first frame aimed at it brought the
;bench down. One constructor is the fix for the fault and for its cause.
bench_newSeat(row, name, role, kind := "fake", socket := 0, back := 0) {
	return { row: row, name: name, role: StrLower(role), kind: kind
		, socket: socket, back: back, said: "", told: "", heard: [] }
}

bench_connectedCount() {
	global bench_seats
	local r, seat, n := 0

	for r, seat in bench_seats
		if bench_wired(seat)
			n++
	return n
}
bench_fakeCount() {
	global bench_seats
	local r, seat, n := 0

	for r, seat in bench_seats
		if (seat.kind = "fake")
			n++
	return n
}
bench_realCount() {
	global bench_seats
	local r, seat, n := 0

	for r, seat in bench_seats
		if (seat.kind = "real")
			n++
	return n
}

;Who is coordinating, in words, and honest about the gap between what was asked
;for and what is actually running.
bench_coordWord() {
	global bench_coord, bench_coordPid, bench_listener, bench_term

	if (bench_coord = "bench")
		return bench_listener
			? "this bench is coordinating, term " bench_term
			: "this bench should be coordinating but is not listening"
	if (bench_coord = "real")
		return (bench_coordPid && ProcessExist(bench_coordPid))
			? "a real Fleet.ahk is coordinating, pid " bench_coordPid
			: "a real Fleet.ahk was asked for and is not running"
	return "nobody is coordinating"
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
			bench_seats[r] := bench_newSeat(r, e.name, e.role)
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
		BenchGui["BenchSeats"].Add(, r, seat.kind, seat.name, seat.role
			, bench_wired(seat) ? "connected" : "-", seat.said
			, seat.told != "" ? seat.told : "-")
	}
	for _, r in keys
		if (r = pick)
			BenchGui["BenchSeats"].Modify(A_Index, "Select Focus")
	Loop 7
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
	bench_seats[row] := bench_newSeat(row, name, role)
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
	global bench_seats, bench_port
	local seat

	if (!row || !bench_seats.Has(row))
		return 0
	seat := bench_seats[row]
	if seat.socket
		return 0
	seat.socket := sock_Connect("127.0.0.1", bench_port, bench_onSocket)
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
	global bench_seats, bench_term, bench_listener
	local r, seat

	;A fake macro's beat says it is alive. The bench's own, when it is the
	;coordinator, says who is in charge and on which term - the frame a macro's
	;whole failover decision turns on.
	;
	;Both go out, to different sockets: a fake seat gets the macro's beat, a
	;real one gets the coordinator's. Which is the point of the two kinds living
	;in one list.
	for r, seat in bench_seats {
		;as the macro: a fake seat saying it is alive
		if seat.socket
			sock_SendLine(seat.socket, fleet_Frame("HEARTBEAT"))
		;as the coordinator: who is in charge and on which term, which is the
		;frame a macro's whole failover decision turns on. It goes to every seat
		;the bench is coordinating, fake ones included - a fake seat connected to
		;the bench is a macro whose coordinator this is.
		if (bench_listener && seat.back)
			sock_SendLine(seat.back, fleet_Frame("HEARTBEAT"
				, Map("term", bench_term, "row", 1, "at", nowUnix())))
	}
	return 1
}

;Speak AS that macro: out of the socket the bench opened pretending to be it.
bench_send(row, line) {
	global bench_seats

	if (!row || !bench_seats.Has(row) || !bench_seats[row].socket)
		return 0
	bench_logFrame(row, "->", line)
	return sock_SendLine(bench_seats[row].socket, line)
}

;Speak TO that macro, as its coordinator: out of the accepted socket.
;
;A separate function because the same frame means opposite things on the two
;sockets. GOTO sent as a macro is a macro giving its coordinator an order,
;which is nonsense; sent as the coordinator it is the order a resident acts
;on. They used to share one call and the wrong one was being used for every
;coordinator verb aimed at a fake seat.
bench_sendBack(row, line) {
	global bench_seats

	if (!row || !bench_seats.Has(row) || !bench_seats[row].back) {
		bench_say("? row " row " has no connection the coordinator can answer on")
		return 0
	}
	bench_logFrame(row, "=>", line)
	return sock_SendLine(bench_seats[row].back, line)
}

;Connected at all, either way round.
bench_wired(seat) {
	return seat.socket || seat.back
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
	return bench_drivable(row)
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
	global bench_coordPid, bench_port, BENCH_SECRET, BENCH_ROSTER, BENCH_FLEET_ID

	try
		Run '"' A_AhkPath '" /script "' A_ScriptDir '\Fleet.ahk" ' bench_port
			. ' "' BENCH_SECRET '" 1 1 "' BENCH_ROSTER '" "' BENCH_FLEET_ID '" 1'
			;and what to call itself in a join window, so a real macro about to
			;bind is told this is the bench and not its own fleet
			. ' "the Natro Macro test bench"'
			, , "Hide", &bench_coordPid
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
;Being the coordinator is the only way to put a real macro's own share of the
;work under any pressure. Everything it does for itself - keeping a replica of
;the configuration, refusing to write a worse one over a better, handing a
;better one up, noticing the coordinator has gone and standing for the job -
;happens in reaction to frames it is sent, and nothing else can send it a wrong
;one. The self-test cannot: it speaks the protocol by hand rather than driving
;a macro.
;
;A real macro that connects becomes a seat of kind "real" beside the fakes, so
;the same table, the same log and the same expect cover both.

;The word a script used, as one of the three the choice allows.
bench_coordWord2(rest) {
	local w := StrLower(Trim(rest))

	if ((w = "bench") || (w = "this bench") || (w = "me"))
		return "bench"
	if ((w = "real") || (w = "fleet.ahk") || (w = "fleet"))
		return "real"
	return "none"
}

bench_coordChanged(*) {
	global BenchGui

	bench_setCoord(["none", "real", "bench"][BenchGui["BenchCoordBy"].Value])
}

;Only one thing can hold the port, so choosing takes the other down. The fake
;macros are left alone deliberately: they reconnect to whoever is listening,
;which is what a macro does when a coordinator changes hands, and watching them
;do it is half of what this is for.
bench_setCoord(which) {
	global bench_coord, BenchGui, bench_port

	if (bench_coord = which)
		return 0
	bench_coord := which
	try BenchGui["BenchCoordBy"].Value := (which = "bench") ? 3
		: ((which = "real") ? 2 : 1)
	if (which != "bench")
		bench_stopListening()
	if (which != "real")
		bench_endCoord()
	if (which = "bench")
		bench_listen()
	else if (which = "real")
		bench_startCoord()
	else
		bench_say("nobody is coordinating - the fakes will fail to connect")
	bench_drawSeats()
	return 1
}

;Exclusive, like the real coordinator's own listen. If a real one already has
;the port, this says so rather than quietly listening alongside it and
;splitting whatever connects.
bench_listen() {
	global bench_listener, bench_port, bench_coord

	bench_coord := "bench"
	try BenchGui["BenchCoordBy"].Value := 3
	if bench_listener
		return 0
	bench_listener := sock_Listen(bench_port, bench_onServer, 1)
	if !bench_listener {
		bench_say("could not listen on " bench_port " - something else has it"
			. (sock_lastError != "" ? " (" sock_lastError ")" : ""))
		return 0
	}
	bench_say("listening on " bench_port " as the coordinator")
	;Said every time, because it is the one way this tool can do harm. A real
	;macro pointed here writes the bench's configuration into its own files -
	;the mark on it stops that configuration ever beating a real one, but the
	;macro will still be carrying it until the real fleet overwrites it.
	bench_say("a real macro that joins will replicate THIS configuration;"
		. " it is marked as the bench's, so it can never win against a real one")
	return 1
}

;--- being found, and letting a real macro in --------------------------------
;
;A real macro finds a fleet by hearing its beacon and walks in through the
;binding door. Until this, the bench had neither: joining it meant typing a
;port and an address into the macro's advanced settings, which is precisely the
;thing binding exists to avoid and which nobody would have found on their own.
;So the bench beacons like a coordinator and binds like one.

;Shout where this bench is. The label is the point of difference and it is not
;decoration: it is what the join window repeats back to whoever is about to
;press the button. On your own machine a bench fleet is otherwise
;indistinguishable from the real one - same host name, same kind of account
;count, same open door - and joining it takes that macro out of its fleet until
;it is set up again.
bench_sendBeacon() {
	global bench_beacon, bench_port, bench_term, bench_seats, bench_bindUntil
	global bench_listener, BENCH_SECRET

	;only while the bench is the one coordinating. A Fleet.ahk it started does
	;its own beaconing, and two beacons for one fleet are two answers to one
	;question.
	if (!bench_beacon || !bench_listener)
		return 0
	return sock_UdpSend(bench_beacon, "255.255.255.255", bench_port + 1
		, fleet_Frame("FLEET", Map("port", bench_port, "term", bench_term
			, "row", 1, "id", fleet_Fingerprint(BENCH_SECRET)
			, "open", (nowUnix() < bench_bindUntil) ? 1 : 0
			, "host", A_ComputerName, "size", bench_seats.Count
			, "label", "the Natro Macro test bench")))
}

;accept [secs] - open the door, or shut it with 0.
;
;Routed by who is coordinating: the bench opens its own door, and a real
;Fleet.ahk is asked through the protocol by the seat that holds its mandate,
;which is the same path a macro's own Accept button takes.
bench_accept(rest) {
	global bench_bindUntil, bench_coord, bench_seats, bench_listener
	local secs := fleet_Num(rest)

	if (rest = "")
		secs := 120
	if (bench_coord = "real") {
		if (!bench_seats.Has(1) || !bench_seats[1].socket) {
			bench_say("? the real coordinator takes orders from row 1 - run:"
				. " seat 1 main mandate, then connect 1")
			return 0
		}
		bench_send(1, fleet_Frame("OPEN", Map("secs", secs)))
		bench_say("asked the real coordinator to accept macros for " secs "s")
		return 1
	}
	if !bench_listener {
		bench_say("? nothing is coordinating here - run: listen")
		return 0
	}
	if (secs <= 0) {
		bench_bindUntil := 0
		bench_say("the door is shut")
		return 1
	}
	bench_bindUntil := nowUnix() + secs
	bench_say("accepting new macros for " secs "s - a real macro will now see"
		. " this bench in its own Set up this macro window")
	return 1
}

;A macro asking to be let in. The one frame that arrives without a secret,
;because handing the secret over is what binding is for.
;
;The row goes into the bench's own roster so the seat survives the macro
;reconnecting, and the bench's fleet identity goes back with the secret - that
;is what keeps this fleet's configuration in a folder of its own on that
;macro's disk, well away from the real fleet it also belongs to.
bench_onBind(s, frame) {
	global bench_seats, bench_bySocket, bench_bindUntil, bench_term
	global BENCH_SECRET, BENCH_FLEET_ID, BENCH_ROSTER
	local row, rows

	if (nowUnix() > bench_bindUntil) {
		bench_say("refused a bind - the door is shut, run: accept")
		sock_SendLine(s, fleet_Frame("BYE"
			, Map("why", "the test bench is not accepting macros")))
		return 0
	}
	rows := roster_Load(BENCH_ROSTER)
	row := bench_freeRow(rows, fleet_Field(frame, "user")
		, fleet_Field(frame, "machine"), fleet_Field(frame, "name"))
	rows[row] := { row: row, name: fleet_Field(frame, "name", "row " row)
		, role: fleet_Field(frame, "role", "guid")
		, user: fleet_Field(frame, "user", "")
		, machine: fleet_Field(frame, "machine", "") }
	roster_Save(BENCH_ROSTER, rows, bench_rosterVersion() + 1, 1, 1)
	bench_seats[row] := bench_newSeat(row, rows[row].name, rows[row].role
		, "real", 0, s)
	bench_seats[row].said := "just bound"
	bench_bySocket[s] := row
	bench_say("bound " rows[row].name " as row " row " of fleet " BENCH_FLEET_ID)
	sock_SendLine(s, fleet_Frame("BOUND", Map("row", row
		, "secret", BENCH_SECRET, "fid", BENCH_FLEET_ID)))
	bench_drawSeats()
	return 1
}

;The row this account already has, or the next free one. Same rule the real
;coordinator uses: one account is one row, so a macro set up twice lands back
;on its own seat instead of leaving a ghost behind.
bench_freeRow(rows, user, machine, name) {
	local r, e, best := 0

	if (user != "")
		for r, e in rows
			if (e.user = user)
				return r
	if ((machine != "") && (name != ""))
		for r, e in rows
			if ((e.machine = machine) && (e.name = name))
				return r
	for r, _ in rows
		if (r > best)
			best := r
	return best + 1
}

;port <n> - where the bench listens.
;
;Everything stops first. A listener and a beacon on the old port would keep
;answering macros that are no longer being told about, which is the one state
;harder to debug than nothing working at all.
bench_doPort(rest) {
	global bench_port, bench_coord
	local want := fleet_Num(rest), was := bench_coord

	if ((want < 1024) || (want > 65535)) {
		bench_say("? port <1024-65535>, and 47600 is the real fleet's")
		return 0
	}
	bench_setCoord("none")
	bench_endCoord()
	bench_port := want
	bench_say("port is now " bench_port
		. ((want = 47600) ? " - the real fleet's, so a macro needs no changes"
			" and a real coordinator cannot run on this machine at the same time"
			: " - set the same port in the macro's Fleet advanced settings"))
	bench_state()
	if (was != "none")
		bench_say("nothing is coordinating any more - run: " ((was = "bench")
			? "listen" : "coordinatedby real"))
	return 1
}

bench_stopListening() {
	global bench_listener, bench_seats
	local r, seat

	if !bench_listener
		return 0
	;the accepted side only. A fake seat's own socket is this process pretending
	;to be a macro, and it closes itself when the listener goes.
	for r, seat in bench_seats
		if seat.back
			sock_Close(seat.back), seat.back := 0
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
			bench_seats[row].back := 0
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
	;the one frame that arrives before a macro has a row at all
	if (frame.verb = "BIND") {
		bench_onBind(s, frame)
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
	;A seat the bench already owns keeps its kind. This is the fault that made
	;the whole point of one fleet with both kinds in it not work: a fake seat
	;connecting to the bench's own coordinator arrived here, was rewritten as a
	;real macro by its own HELLO, and could no longer be driven.
	if (bench_seats.Has(row) && (bench_seats[row].kind = "fake")) {
		bench_seats[row].back := s
		bench_bySocket[s] := row
		bench_say("row " row " reached the bench's own coordinator")
	}
	else {
		bench_seats[row] := bench_newSeat(row
			, fleet_Field(frame, "machine", "a macro")
			, fleet_Field(frame, "role", "?"), "real", 0, s)
		bench_bySocket[s] := row
		bench_say("row " row " is here, from "
			. fleet_Field(frame, "machine", "somewhere"))
	}
	;a macro expects to be told who is in charge before anything else
	sock_SendLine(s, fleet_Frame("HEARTBEAT"
		, Map("term", bench_term, "row", 1, "at", nowUnix())))
	bench_drawSeats()
	return 1
}

;Can this seat be told what to say?
;
;A fake one yes - it is ours. A real one no: the only thing that can make a
;real macro report a field is the macro deciding to, and pretending otherwise
;would be sending a frame in the wrong direction down its own socket. Saying so
;beats a command that appears to work.
bench_drivable(row) {
	global bench_seats

	if (!row || !bench_seats.Has(row)) {
		bench_say("? there is no seat " row)
		return 0
	}
	if (bench_seats[row].kind = "real") {
		bench_say("? row " row " is a real macro - you can send TO it as the"
			. " coordinator (goto, bye, serve), not make it speak")
		return 0
	}
	if !bench_seats[row].socket {
		bench_say("? row " row " is not connected")
		return 0
	}
	return 1
}

;What a seat has heard, kept for expect. One place, because both kinds need it
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
	global BENCH_ROSTER, bench_seats, bench_listener
	local what := (parts.Length >= 2) ? StrLower(parts[2]) : ""
	local v := (parts.Length >= 3) ? fleet_Num(parts[3]) : 1
	local by := (parts.Length >= 4) ? fleet_Num(parts[4]) : 1
	local rows, r, e, n, line, seat

	if !bench_listener {
		bench_say("? serve needs this bench to be the coordinator - run: listen")
		return
	}
	if (what = "servers") {
		rows := servers_Load(RegExReplace(BENCH_ROSTER, "i)\.ini$", "_servers.ini"))
		n := rows.Count
		for r, e in rows
			bench_asCoord(fleet_Frame("SERVER", Map("v", v, "by", by, "bench", 1
				, "n", n, "slot", e.slot, "name", e.name, "link", e.link
				, "owner", e.owner, "kind", e.kind)))
		bench_say("served " n " server(s) at v" v " by row " by)
		return
	}
	rows := roster_Load(BENCH_ROSTER)
	n := rows.Count
	;an empty configuration still has to say so, exactly as the real
	;coordinator does, or clearing one would reach nobody
	if !n {
		bench_asCoord(fleet_Frame("ROW", Map("v", v, "by", by, "bench", 1, "n", 0)))
		bench_say("served an empty roster at v" v " by row " by)
		return
	}
	for r, e in rows {
		;bench=1 on every one. A real macro will write this into its own files,
		;and the mark is what stops it ever being handed up and winning against
		;a real fleet - see the note on Bench in FleetRoster.ahk.
		bench_asCoord(fleet_Frame("ROW", Map("v", v, "by", by, "bench", 1, "n", n
			, "row", e.row, "name", e.name, "role", e.role
			, "user", e.user, "machine", e.machine)))
		;and the live half, so the macro's panel has something to draw
		bench_asCoord(fleet_Frame("ROSTER", Map("row", e.row, "name", e.name
			, "role", e.role, "state", "online", "machine", e.machine
			, "user", e.user, "server", "", "field", ""
			, "guiding", "", "until", 0, "charge", 0
			, "rtt", 1, "seen", nowUnix(), "cv", v, "cby", by)))
	}
	bench_say("served " n " row(s) at v" v " by row " by)
}

;A coordinator's frame, to everybody this bench coordinates - real macros and
;its own fakes alike.
;
;It was called bench_toReal and went only to the real seats, on the socket a
;fake seat uses to speak rather than the one it listens on. That is why a fake
;seat could never be sent an order, and the name was the clue: it named half
;the set it should have been reaching.
bench_asCoord(line) {
	global bench_seats
	local r, seat, n := 0

	for r, seat in bench_seats
		if seat.back
			bench_sendBack(r, line), n++
	if !n
		bench_say("nothing is connected to this bench, so that went nowhere")
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
# One fleet. The bench always has its fake macros; real macros join the same
# port and sit in it beside them. Only the coordinator is a choice.
#
#   coordinatedby bench             this bench coordinates (same as: listen)
#   coordinatedby real              a real Fleet.ahk, started here
#   coordinatedby none              nobody (same as: stop)
#
# the fake macros - yours to drive
#   seat 2 fuzzy some name          declare one, before a coordinator reads it
#   connect all / connect 2
#   disconnect all / disconnect 2
#   field 2 pepper                  report a field, which is what a main does
#   beat 2 9 1                      a heartbeat claiming config v9 by row 1
#   leave 2
#   send 2 FIELD name=pepper        a frame exactly as it travels
#
# the real macros - theirs to decide, yours to lie to
#   term 4                          what your heartbeat claims
#   serve roster 9 1                your roster at that version and author
#   serve servers 3 1
#   goto all pepper                 or: goto 2 pepper
#   bye 2 1 you are not welcome     final=1, so the macro gives up for good
#   gone 2
#
# letting a real macro in - it finds this bench by beacon, like any fleet
#   accept                       open the door for two minutes (accept 0 shuts it)
#   port 47600                   take the real fleet's port, so a macro
#                                needs no changes at all to join
#
# either kind
#   wait 2000                       milliseconds
#   say anything at all             one line in the log
#   clear all / clear 2             forget what a seat has heard
#   expect 2 GOTO field=pepper      pass or fail, and the log says which
#   reject 2 GOTO                   passes when it was NOT heard
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
			;A run with nothing checked is not a pass. A script whose expects all
			;failed to even parse would otherwise report success, which is the
			;worst answer a test harness can give.
			if bench_quiet() {
				FileAppend (bench_fail || !bench_pass) ? "FAIL" : "PASS", "*"
				FileAppend "`n", "*"
				ExitApp (bench_fail || !bench_pass) ? 1 : 0
			}
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
			if bench_drivable(fleet_Num(rest))
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
		case "coordinatedby":
			bench_setCoord(bench_coordWord2(rest))
		case "listen":
			bench_setCoord("bench")
		case "accept":
			bench_accept(rest)
		case "port":
			bench_doPort(rest)
		case "stop":
			bench_setCoord("none")
		case "term":
			bench_doTerm(rest)
		case "serve":
			bench_serve(parts)
		case "goto":
			bench_doGoto(parts, rest)
		case "bye":
			bench_doBye(parts, rest)
		case "gone":
			bench_asCoord(fleet_Frame("GONE", Map("row", fleet_Num(rest))))
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
		bench_asCoord(fleet_Frame("GOTO", Map("field", field)))
		return
	}
	bench_sendBack(fleet_Num(who), fleet_Frame("GOTO", Map("field", field)))
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
	bench_sendBack(row, fleet_Frame("BYE", Map("why", why, "final", final)))
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
		bench_seats[row] := bench_newSeat(row, name, role)
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
	if ((tail = "") || !bench_drivable(row)) {
		if (tail = "")
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

	if !bench_drivable(row)
		return
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
	if !bench_wired(bench_seats[row]) {
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
