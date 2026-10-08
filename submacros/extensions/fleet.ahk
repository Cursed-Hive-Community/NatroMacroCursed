;The macro's side of Natro Fleet.
;
;It joins the fleet, keeps the connection alive, holds a copy of the roster, and
;starts a coordinator when there is none. Everything here is timers and
;callbacks: not one line of it may block, because the macro this lives inside
;spends minutes at a time walking, converting and fighting.
;
;The governing rule from the spec, and the one to break last: losing the
;coordinator must never freeze a macro. Every failure path below ends in "carry
;on farming and try again later", never in waiting.

;Where to look for the coordinator, in the order of what is likeliest and
;cheapest to rule out.
;
;1. This machine. If the coordinator is here that is both the fastest path and
;   the right answer, and a refusal on loopback comes back immediately. It also
;   covers the case that matters most - a neighbour on this machine having just
;   taken over as acting coordinator.
;2. Wherever the last beacon came from. The coordinator broadcasts its address
;   every two seconds, so this stays right even after a router hands out a new
;   lease, which is the whole reason nothing has to be typed in any more.
;3. An address entered by hand, for a network where broadcasts are blocked.
ext_fleetCandidates() {
	global FleetAddress, ext_fleetFoundAt
	local list := ["127.0.0.1"]

	if ((ext_fleetFoundAt != "") && (ext_fleetFoundAt != "127.0.0.1"))
		list.Push(ext_fleetFoundAt)
	if ((FleetAddress != "") && (FleetAddress != "127.0.0.1")
		&& (FleetAddress != ext_fleetFoundAt))
		list.Push(FleetAddress)
	return list
}

;Try one candidate. Called with no argument - as a timer does - it starts again
;from the top; called with one, it moves on to the next.
ext_fleetConnect(again := 0) {
	global FleetPort, ext_fleetSock, ext_fleetTrying, ext_fleetTryAt

	if ext_fleetSock
		return 0
	ext_fleetTryAt := again ? (ext_fleetTryAt + 1) : 1
	if (ext_fleetTryAt > ext_fleetCandidates().Length) {
		;nowhere left to look this time round. A beacon will wake us sooner than
		;the backoff would, so this is a floor and not a wait.
		ext_fleetRetryLater()
		return 0
	}
	ext_fleetTrying := ext_fleetCandidates()[ext_fleetTryAt]
	ext_fleetSock := sock_Connect(ext_fleetTrying, FleetPort, ext_fleetOnSocket)
	if !ext_fleetSock
		ext_fleetRetryLater()
	return 1
}

;Listen for the coordinator's beacon. One socket, opened once and kept for the
;life of the macro: it is how a coordinator that has moved gets found again
;without anybody editing anything.
ext_fleetDiscover() {
	global FleetPort, ext_fleetBeaconSock

	if ext_fleetBeaconSock
		return 1
	ext_fleetBeaconSock := sock_UdpListen(FleetPort + 1, ext_fleetOnBeacon)
	return ext_fleetBeaconSock ? 1 : 0
}

;A beacon arrived. Another fleet sharing the network carries a different
;fingerprint and is ignored - and since the beacon is broadcast in clear, it
;carries that fingerprint rather than the secret itself.
ext_fleetOnBeacon(s, event, data, from) {
	global FleetSecret, ext_fleetFoundAt, ext_fleetSock, ext_fleetOpen
	local frame := fleet_Parse(data)

	if (!frame || (frame.verb != "FLEET"))
		return
	;an open fleet is worth noting even when the fingerprint says it is not
	;ours - that is exactly the one a macro looking to be bound is hunting for
	if (fleet_Field(frame, "open") = "1")
		ext_fleetOpen[from] := frame.fields
	if (fleet_Field(frame, "id") != fleet_Fingerprint(FleetSecret))
		return
	ext_fleetFoundAt := from
	;a beacon while we are adrift is the best news we are going to get, so act on
	;it rather than sitting out whatever backoff happens to be running
	if !ext_fleetSock
		SetTimer ext_fleetConnect, -200
}

;--- binding ----------------------------------------------------------------
;
;Joining a fleet is a two-sided gesture, like pairing a phone: the host opens
;its door for a couple of minutes, and a macro walks in. Nothing is typed on
;both machines and nothing has to match, because the row number and the
;secret are handed over rather than agreed in advance.
;
;The macro stores what it is given and uses it for every reconnection after,
;so binding happens exactly once per machine.

;Ask the coordinator to open its door. Only the host's own macro will be
;obeyed, which is checked at the other end.
ext_fleetOpenDoor(secs := 120) {
	global ext_fleetSock

	if !ext_fleetSock
		return 0
	return sock_SendLine(ext_fleetSock, fleet_Frame("OPEN", Map("secs", secs)))
}

;The open fleets heard from in the last few seconds. A beacon goes out every
;two, so anything older than that has stopped offering.
ext_fleetOpenFleets() {
	global ext_fleetOpen
	local addr, f, out := []

	for addr, f in ext_fleetOpen
		out.Push({ addr: addr
			, port: Integer(f.Has("port") ? f["port"] : 0)
			, host: f.Has("host") ? f["host"] : addr
			, size: f.Has("size") ? f["size"] : 0 })
	return out
}

;Knock on an open door, saying what this account is. The answer carries the
;row and the secret, and that is the whole of the configuration.
ext_fleetBind(addr, port, name, role, user) {
	global ext_fleetBindSock, ext_fleetBindWith

	if ext_fleetBindSock
		sock_Close(ext_fleetBindSock), ext_fleetBindSock := 0
	ext_fleetBindWith := Map("name", name, "role", role, "user", user
		, "machine", A_ComputerName)
	ext_fleetBindSock := sock_Connect(addr, port, ext_fleetOnBindSocket)
	return ext_fleetBindSock ? 1 : 0
}

ext_fleetOnBindSocket(s, event, data) {
	global ext_fleetBindSock, ext_fleetBindWith, ext_fleetBindResult
	local frame

	if (event = "connect") {
		if (data != "") {
			ext_fleetBindResult := "Could not reach that fleet."
			return
		}
		sock_SendLine(s, fleet_Frame("BIND", ext_fleetBindWith))
		return
	}
	if (event = "close") {
		ext_fleetBindSock := 0
		if (ext_fleetBindResult = "")
			ext_fleetBindResult := "The fleet closed the connection."
		return
	}
	if (event != "line")
		return
	if !(frame := fleet_Parse(data))
		return
	if (frame.verb = "BOUND")
		ext_fleetBound(Integer(fleet_Field(frame, "row", 0)), fleet_Field(frame, "secret"))
	else if (frame.verb = "BYE")
		ext_fleetBindResult := fleet_Field(frame, "why", "refused")
}

;We are in. Keep the row and the secret, and join properly - the binding
;socket has done its one job and is dropped.
ext_fleetBound(row, newSecret) {
	global ext_fleetBindSock, ext_fleetBindResult, FleetRow

	if (row <= 0)
		return 0
	ext_FleetSave("FleetRow", row)
	ext_FleetSave("FleetHostRow", 0)
	if (newSecret != "")
		ext_FleetSave("FleetSecret", newSecret)
	ext_FleetSave("FleetCheck", 1)
	if ext_fleetBindSock
		sock_Close(ext_fleetBindSock), ext_fleetBindSock := 0
	ext_fleetStop()
	ext_fleetStart()
	ext_fleetBindResult := "ok"
	return 1
}

;Start a fleet here instead of joining one. The same work the coordinator
;does for a newcomer, done locally: invent a secret, write ourselves into an
;empty roster, and take row one.
ext_fleetStartFleet(name, role, user) {
	global FleetSecret
	local path := A_WorkingDir "\settings\fleet_roster.ini", rows

	rows := roster_Load(path)
	rows[1] := { row: 1, name: name, role: role, user: user, owner: 1 }
	roster_Save(path, rows)
	if (FleetSecret = "")
		ext_FleetSave("FleetSecret", fleet_NewSecret())
	ext_FleetSave("FleetRow", 1)
	ext_FleetSave("FleetHostRow", 1)
	ext_FleetSave("FleetCheck", 1)
	ext_fleetStop()
	ext_fleetStart()
	return 1
}

;Everything the socket layer reports about our one connection.
ext_fleetOnSocket(s, event, data) {
	global ext_fleetSock, ext_fleetBackoff

	if (event = "connect") {
		if (data = "") {
			ext_fleetBackoff := 0
			ext_fleetHello()
			return
		}
		;refused here, so move down the list rather than giving up on the round
		sock_Close(s), ext_fleetSock := 0
		ext_fleetConnect(1)
	}
	else if (event = "line")
		ext_fleetOnLine(data)
	else if (event = "close") {
		ext_fleetSock := 0
		ext_fleetRetryLater()
	}
}

;Announce ourselves. Only the row number and the secret matter: who row 2 is
;belongs to the roster file, not to whatever this macro believes about itself.
ext_fleetHello() {
	global ext_fleetSock, FleetRow, FleetSecret

	sock_SendLine(ext_fleetSock, fleet_Frame("HELLO", Map("row", FleetRow
		, "secret", FleetSecret, "machine", A_ComputerName)))
}

;A frame from the coordinator.
ext_fleetOnLine(line) {
	global ext_fleetPeers, ext_fleetTerm, ext_fleetCoordRow, ext_fleetCoordSeen
	global ext_fleetEvents, ext_fleetFollowField
	local frame := fleet_Parse(line), row, term

	if !frame
		return
	switch frame.verb {
		case "HEARTBEAT":
			term := Integer(fleet_Field(frame, "term", 0))
			;a lower term is an older coordinator that has not noticed it was
			;replaced; its orders are stale and are not followed
			if (term < ext_fleetTerm)
				return
			ext_fleetTerm := term
			ext_fleetCoordRow := Integer(fleet_Field(frame, "row", 0))
			ext_fleetCoordSeen := nowUnix()
		case "ROSTER":
			if (row := Integer(fleet_Field(frame, "row", 0)))
				ext_fleetPeers[row] := frame.fields
			ext_fleetCoordSeen := nowUnix()
		case "EVENT":
			;stamped on arrival rather than from the frame: the difference is
			;milliseconds, and it saves converting unix time to a local clock
			ext_fleetEvents.InsertAt(1, FormatTime(A_Now, "HH:mm:ss") "  "
				. fleet_Field(frame, "text"))
			while (ext_fleetEvents.Length > 80)
				ext_fleetEvents.Pop()
			ext_fleetCoordSeen := nowUnix()
		case "GOTO":
			;the main is farming this field and we are a resident. Store it;
			;travelling there and gathering is the gather loop's job, added next.
			ext_fleetFollowField := fleet_Field(frame, "field")
			ext_fleetCoordSeen := nowUnix()
		case "BYE":
			nm_setStatus("Failed", "Fleet refused this macro`n" fleet_Field(frame, "why"))
	}
}

;Tell the coordinator which field we are farming, when it changes. Called from
;the gather loop - the farm path - so a planter harvest or a booster trip,
;each its own function, never reports one, and the residents following this
;never chase the main anywhere but to farm. Sent only on a change, since the
;gather loop runs the same field many times over.
ext_fleetReportField(field) {
	global ext_fleetSock, ext_fleetMyField

	if (!ext_fleetSock || (field = "") || (field = ext_fleetMyField))
		return 0
	ext_fleetMyField := field
	return sock_SendLine(ext_fleetSock, fleet_Frame("FIELD", Map("name", field)))
}

;Say we are still here. Cheap, and it is what tells the coordinator apart from a
;macro that has quietly died.
ext_fleetBeat() {
	global ext_fleetSock

	if ext_fleetSock
		sock_SendLine(ext_fleetSock, fleet_Frame("HEARTBEAT"))
	else
		ext_fleetConnect()
}

;Reconnect later rather than in a tight loop. The delay grows to a minute so a
;coordinator that is down for the night does not mean a connection attempt every
;second until morning.
ext_fleetRetryLater() {
	global ext_fleetBackoff

	ext_fleetBackoff := Min(ext_fleetBackoff ? ext_fleetBackoff * 2 : 5, 60)
	SetTimer ext_fleetConnect, -ext_fleetBackoff * 1000
}

;Is there a coordinator, and should it be us?
;
;Two reasons to start one. Either nobody has spoken for the grace period, or we
;are the macro the panel named as host and somebody lower down the pecking order
;is standing in for us. The second is how the host takes its job back.
;
;The successor is simply the lowest live row. Nothing is negotiated: every macro
;holds the same roster, so every macro works out the same answer without sending
;a single message about it.
ext_fleetWatch() {
	global ext_fleetTerm, ext_fleetCoordRow, ext_fleetCoordSeen, ext_fleetSock
	global FleetRow, FleetHostRow, FleetGraceSecs
	local silent := (nowUnix() - ext_fleetCoordSeen)

	if (silent > FleetGraceSecs) {
		if (ext_fleetSuccessor() = FleetRow)
			ext_fleetTakeOver("no coordinator for " silent "s")
		return
	}
	;the host reclaiming: only once the stand-in has actually been heard from,
	;so a host starting up does not fight a coordinator that is about to answer
	if ((FleetRow = FleetHostRow) && ext_fleetCoordRow && (ext_fleetCoordRow != FleetRow))
		ext_fleetTakeOver("host reclaiming from row " ext_fleetCoordRow)
}

;The lowest row that was alive when we last heard. Ours counts even when the
;roster is empty - a macro that has never reached a coordinator is still allowed
;to become one, otherwise the first one started would wait forever.
ext_fleetSuccessor() {
	global ext_fleetPeers, FleetRow
	local best := FleetRow, row, p

	for row, p in ext_fleetPeers {
		if (p.Has("state") && (p["state"] != "online"))
			continue
		if (row < best)
			best := row
	}
	return best
}

;Start a coordinator here, one term above whatever we last saw, and reconnect to
;it. The higher term is what makes the fleet follow us rather than the process
;we are replacing.
ext_fleetTakeOver(why) {
	global ext_fleetTerm, ext_fleetSock, ext_fleetCoordSeen
	global FleetPort, FleetSecret, FleetRow, exe_path32

	nm_setStatus("Starting", "Fleet coordinator`n" why)
	ext_fleetTerm++
	try Run '"' exe_path32 '" /script "' A_WorkingDir '\submacros\Fleet.ahk" '
		. FleetPort ' "' FleetSecret '" ' ext_fleetTerm ' ' FleetRow, , "Hide"
	;give it a moment to bind before knocking, and drop the dead connection so
	;the next attempt starts from loopback again
	if ext_fleetSock
		sock_Close(ext_fleetSock), ext_fleetSock := 0
	ext_fleetCoordSeen := nowUnix()
	SetTimer ext_fleetConnect, -2000
	return 1
}

;Bring the whole thing up. Called once, from the macro's start-up.
ext_fleetStart() {
	global FleetCheck, FleetRow, FleetHostRow

	;listening costs nothing and an unbound macro needs it most: it is how the
	;join dialog finds a fleet to join in the first place
	ext_fleetDiscover()
	if (!FleetCheck || (FleetRow <= 0))
		return 0
	;the designated host starts a coordinator without waiting to discover there
	;is none - it is the expected state at the beginning of a session
	if (FleetRow = FleetHostRow)
		ext_fleetTakeOver("designated host")
	else
		ext_fleetConnect()
	SetTimer ext_fleetBeat, 10000
	SetTimer ext_fleetWatch, 5000
	return 1
}

;Stop talking to the fleet, without killing a coordinator that other macros may
;still be using.
ext_fleetStop() {
	global ext_fleetSock

	SetTimer ext_fleetBeat, 0
	SetTimer ext_fleetWatch, 0
	SetTimer ext_fleetConnect, 0
	if ext_fleetSock
		sock_Close(ext_fleetSock), ext_fleetSock := 0
	return 1
}

;How the fleet looks from here, for the panel to draw. Rows in order, because a
;list that reshuffles itself between refreshes is unreadable.
ext_fleetView() {
	global ext_fleetPeers
	local keys := [], row, out := []

	for row, _ in ext_fleetPeers
		keys.Push(row)
	roster_Sort(keys)
	for _, row in keys
		out.Push(ext_fleetPeers[row])
	return out
}

;One line for the panel's header: whether we are connected, to whom, and on
;which term.
ext_fleetSummary() {
	global ext_fleetSock, ext_fleetTerm, ext_fleetCoordRow, ext_fleetCoordSeen
	global FleetCheck, ext_fleetTrying, ext_fleetFoundAt
	local silent

	if !FleetCheck
		return "Fleet is off"
	if !ext_fleetSock {
		return ext_fleetFoundAt
			? "Found a coordinator at " ext_fleetFoundAt " - connecting"
			: "Listening for a coordinator on the network"
	}
	silent := nowUnix() - ext_fleetCoordSeen
	return "Connected to " ext_fleetTrying
		. (ext_fleetCoordRow ? " (row " ext_fleetCoordRow ")" : "")
		. ", term " ext_fleetTerm
		. ((silent > 15) ? " - quiet for " silent "s" : "")
}

;The Fleet window - what the fleet is doing, and nothing else.
;
;Configuration lives in its own window behind the Settings button. The two are
;used at completely different rates: setting a macro up happens once per
;machine, watching the fleet happens all night. Making the second wade through
;the first was the whole problem with the panel this replaces.
;
;The seats are the point. A private server is six places, and every rule in the
;queue is about who holds one - so the window draws places rather than listing
;rows. The log underneath says why they changed hands, which a picture cannot.

;How many seat cards exist. They are made once and then shown, hidden and
;repainted: rebuilding controls every second flickers and leaks window handles.
FLEET_SEATS_MAIN := 12
FLEET_SEATS_SPARE := 6

ext_FleetGUI(*) {
	global FleetGui, FLEET_SEATS_MAIN, FLEET_SEATS_SPARE
	local i, x, y

	if (IsSet(FleetGui) && IsObject(FleetGui)) {
		FleetGui.Show()
		return
	}
	FleetGui := Gui("+AlwaysOnTop +Border", "Fleet")
	FleetGui.OnEvent("Close", ext_FleetGUIClose)
	FleetGui.SetFont("s8 cDefault Norm", "Tahoma")

	FleetGui.Add("Text", "x16 y10 w588 vFleetSummary", ext_fleetSummary())

	FleetGui.SetFont("s8 cDefault Bold")
	FleetGui.Add("Text", "x16 y34 w300 vFleetMainLabel", "MAIN SERVER")
	FleetGui.Add("Text", "x404 y34 w200 Right vFleetMainCount", "")
	FleetGui.Add("Text", "x16 y142 w300 vFleetSpareLabel", "RESERVE")
	FleetGui.Add("Text", "x404 y142 w200 Right vFleetSpareCount", "")
	FleetGui.SetFont("Norm")

	;seat cards, six to a row
	Loop FLEET_SEATS_MAIN {
		i := A_Index - 1
		x := 16 + Mod(i, 6) * 98, y := 54 + (i // 6) * 50
		FleetGui.Add("Text", "x" x " y" y " w94 h44 Border Center vFleetSeatM" A_Index, "")
	}
	Loop FLEET_SEATS_SPARE {
		i := A_Index - 1
		x := 16 + Mod(i, 6) * 98
		FleetGui.Add("Text", "x" x " y162 w94 h44 Border Center vFleetSeatS" A_Index, "")
	}

	;newest first, so the line that just appeared is the one on screen and
	;nothing has to be scrolled
	FleetGui.Add("Text", "x16 y216 w588 h1 +0x10")
	FleetGui.SetFont("s8", "Consolas")
	FleetGui.Add("Edit", "x16 y224 w588 h166 ReadOnly -Wrap +VScroll vFleetLog", "")
	FleetGui.SetFont("s8 cDefault Norm", "Tahoma")

	FleetGui.Add("Button", "x16 y398 w100 h26", "Settings").OnEvent("Click", ext_FleetSetupGUI)
	FleetGui.Add("Button", "x504 y398 w100 h26", "Close").OnEvent("Click", ext_FleetGUIClose)

	ext_FleetRefresh()
	SetTimer ext_FleetRefresh, 1000
	FleetGui.Show("w620 h436")
}

ext_FleetGUIClose(*) {
	global FleetGui

	SetTimer ext_FleetRefresh, 0
	if (IsSet(FleetGui) && IsObject(FleetGui))
		FleetGui.Destroy(), FleetGui := ""
}

;Repaint the seats and the log. Called every second, so it only ever changes
;text and colour on controls that already exist.
ext_FleetRefresh() {
	global FleetGui, ext_fleetEvents, FLEET_SEATS_MAIN, FLEET_SEATS_SPARE
	local main := [], spare := [], p, seated := 0

	if !(IsSet(FleetGui) && IsObject(FleetGui))
		return
	try FleetGui["FleetSummary"].Text := ext_fleetSummary()

	;Until the queue exists there is no server field to sort by, so a macro that
	;is online is shown in the main server and one that is not is shown apart.
	;The moment the coordinator starts reporting servers this follows it.
	for _, p in ext_fleetView() {
		if (ext_FleetCell(p, "server") = "reserve")
			spare.Push(p)
		else if (ext_FleetCell(p, "state") = "online")
			main.Push(p), seated++
		else
			spare.Push(p)
	}

	ext_FleetPaintRow("FleetSeatM", FLEET_SEATS_MAIN, main, 1)
	ext_FleetPaintRow("FleetSeatS", FLEET_SEATS_SPARE, spare, 0)
	try FleetGui["FleetMainCount"].Text := seated " / " ext_fleetCapacity()
	try FleetGui["FleetSpareCount"].Text := spare.Length ? spare.Length : ""
	try FleetGui["FleetSpareLabel"].Text := spare.Length ? "RESERVE AND OFFLINE" : ""

	try FleetGui["FleetLog"].Value := ext_fleetEvents.Length
		? ext_FleetJoin(ext_fleetEvents)
		: "Nothing has happened yet."
}

;Fill the cards of one section, and hide the ones nobody needs. Free places are
;only drawn in the main server: an empty reserve is not a place waiting to be
;filled, it is simply nothing.
ext_FleetPaintRow(prefix, pool, list, showFree) {
	global FleetGui
	local i, card, p, free := showFree ? ext_fleetCapacity() : 0

	Loop pool {
		i := A_Index
		card := FleetGui[prefix i]
		if (i <= list.Length) {
			p := list[i]
			card.Text := ext_FleetCell(p, "name") "`n" ext_FleetSeatLine(p)
			card.Opt("Background" ext_FleetSeatColour(p))
			card.Visible := true
		}
		else if (i <= free) {
			card.Text := "`nfree"
			card.Opt("BackgroundF2F2F2")
			card.Visible := true
		}
		else
			card.Visible := false
		card.Redraw()
	}
}

;The second line of a card: whatever is most worth knowing about that macro
;right now, which is not the same thing for every role.
ext_FleetSeatLine(p) {
	local left

	if (ext_FleetCell(p, "state") != "online")
		return ext_FleetCell(p, "state")
	if (ext_FleetCell(p, "guiding") != "") {
		left := Integer(ext_FleetCell(p, "until")) - nowUnix()
		if (left > 0)
			return "* " Floor(left / 60) ":" Format("{:02}", Mod(left, 60))
	}
	if (ext_FleetCell(p, "charge") > 0)
		return ext_FleetCell(p, "charge") " / 250"
	return ext_FleetCell(p, "field") ? ext_FleetCell(p, "field") : ext_FleetCell(p, "role")
}

;Colour says state at a glance, which is the whole reason for drawing seats
;rather than listing rows.
ext_FleetSeatColour(p) {
	if (ext_FleetCell(p, "state") = "offline")
		return "E4E4E4"
	if (ext_FleetCell(p, "state") != "online")
		return "F5E0D8"
	if (ext_FleetCell(p, "guiding") != "")
		return "FAE8C6"
	return "DCE8F5"
}

;Six by default, and whatever the panel says if that ever changes.
ext_fleetCapacity() {
	global FleetCapacity

	return (IsSet(FleetCapacity) && (FleetCapacity > 0)) ? FleetCapacity : 6
}

ext_FleetJoin(arr) {
	local out := "", v

	for _, v in arr
		out .= v "`r`n"
	return out
}

;A roster frame carries whatever the coordinator chose to send, so a field that
;is not there is normal rather than a fault.
ext_FleetCell(fields, name) {
	return fields.Has(name) ? fields[name] : ""
}

;--- settings, in a window of their own --------------------------------------

;Three sections, and the first one has no fields at all any more.
;
;It used to ask you to invent row numbers, type them into a table, then go to
;every other machine and pick which row it was and retype the secret. That is
;building the directory before anything can talk. Binding turns it round: the
;two sides find each other, and the table fills itself in as macros arrive.
ext_FleetSetupGUI(*) {
	global FleetSetupGui, FleetRoster, FleetRosterPath
	global FleetServerMain, FleetServerReserve
	local GuiCtrl

	if (IsSet(FleetSetupGui) && IsObject(FleetSetupGui)) {
		FleetSetupGui.Show()
		return
	}
	FleetRosterPath := A_WorkingDir "\settings\fleet_roster.ini"
	FleetRoster := roster_Load(FleetRosterPath)

	FleetSetupGui := Gui("+AlwaysOnTop +Border", "Fleet - settings")
	FleetSetupGui.OnEvent("Close", ext_FleetSetupClose)
	FleetSetupGui.SetFont("s8 cDefault Bold", "Tahoma")
	FleetSetupGui.Add("GroupBox", "x8 y4 w584 h68", "1 - this macro")
	FleetSetupGui.Add("GroupBox", "x8 y76 w584 h66", "2 - the servers, the same on every macro")
	FleetSetupGui.Add("GroupBox", "x8 y146 w584 h150", "3 - the accounts")
	FleetSetupGui.SetFont("Norm")

	FleetSetupGui.Add("Text", "x18 y22 w420 h36 vFleetWho", "")
	FleetSetupGui.Add("Button", "x446 y20 w136 h22 vFleetAct1", "").OnEvent("Click", ext_FleetAct1)
	FleetSetupGui.Add("Button", "x446 y44 w136 h22 vFleetAct2", "").OnEvent("Click", ext_FleetAct2)

	FleetSetupGui.Add("Text", "x18 y96 w60", "Main:")
	(GuiCtrl := FleetSetupGui.Add("Edit", "x82 y94 w500 h18 vFleetServerMain", FleetServerMain)).Section := "Fleet"
	GuiCtrl.OnEvent("Change", nm_saveConfig)
	FleetSetupGui.Add("Text", "x18 y118 w60", "Reserve:")
	(GuiCtrl := FleetSetupGui.Add("Edit", "x82 y116 w500 h18 vFleetServerReserve", FleetServerReserve)).Section := "Fleet"
	GuiCtrl.OnEvent("Change", nm_saveConfig)

	;no row column: the numbers are assigned at binding and nobody needs to see
	;them. They are still in Advanced for the day something has to be matched up
	;against a log.
	FleetSetupGui.Add("ListView", "x16 y164 w340 h122 -Multi vFleetRosterList"
		, ["Name", "Role", "Roblox user", "Owner"])
	FleetSetupGui["FleetRosterList"].OnEvent("ItemSelect", ext_FleetRosterSelect)
	FleetSetupGui.Add("Text", "x364 y168 w36", "Name:")
	FleetSetupGui.Add("Edit", "x404 y166 w178 h18 vFleetEditName")
	FleetSetupGui.Add("Text", "x364 y194 w36", "Role:")
	FleetSetupGui.Add("DropDownList", "x404 y192 w100 vFleetEditRole", roster_Roles())
	FleetSetupGui.Add("Text", "x364 y220 w36", "User:")
	FleetSetupGui.Add("Edit", "x404 y218 w178 h18 vFleetEditUser")
	FleetSetupGui.Add("CheckBox", "x404 y244 w178 vFleetEditOwner", "Owns the private server")
	FleetSetupGui.Add("Button", "x364 y268 w104 h24", "Update").OnEvent("Click", ext_FleetRosterSave)
	FleetSetupGui.Add("Button", "x478 y268 w104 h24", "Remove").OnEvent("Click", ext_FleetRosterRemove)

	FleetSetupGui.Add("Button", "x8 y304 w100 h26", "Advanced").OnEvent("Click", ext_FleetAdvanced)
	FleetSetupGui.Add("Button", "x492 y304 w100 h26", "Close").OnEvent("Click", ext_FleetSetupClose)

	ext_FleetRosterDraw()
	ext_FleetWhoDraw()
	SetTimer ext_FleetWhoDraw, 1000
	FleetSetupGui.Show("w600 h342")
}

ext_FleetSetupClose(*) {
	global FleetSetupGui

	SetTimer ext_FleetWhoDraw, 0
	if (IsSet(FleetSetupGui) && IsObject(FleetSetupGui))
		FleetSetupGui.Destroy(), FleetSetupGui := ""
}

;Section one says where this macro stands and offers the one or two things worth
;doing from there. Three states, and each gets different buttons rather than a
;row of buttons that are mostly greyed out.
ext_FleetWhoDraw() {
	global FleetSetupGui, FleetRoster, FleetRow, FleetHostRow, ext_fleetBindOpenUntil
	local me, left

	if !(IsSet(FleetSetupGui) && IsObject(FleetSetupGui))
		return
	if (FleetRow <= 0) {
		FleetSetupGui["FleetWho"].Text := "This macro is not in a fleet yet."
			. "`nSet it up once and it will rejoin on its own from then on."
		ext_FleetButton("FleetAct1", "Set up this macro")
		ext_FleetButton("FleetAct2", "")
		return
	}
	me := FleetRoster.Has(FleetRow)
		? FleetRoster[FleetRow].name " (" FleetRoster[FleetRow].role ")"
		: "row " FleetRow
	if (FleetHostRow = FleetRow) {
		left := ext_fleetBindOpenUntil - nowUnix()
		FleetSetupGui["FleetWho"].Text := me "`nThis macro hosts the fleet."
		ext_FleetButton("FleetAct1", (left > 0)
			? "Open for " Floor(left / 60) ":" Format("{:02}", Mod(left, 60))
			: "Accept new macros")
		ext_FleetButton("FleetAct2", "Leave the fleet")
		return
	}
	FleetSetupGui["FleetWho"].Text := me "`nJoined this fleet."
	ext_FleetButton("FleetAct1", "Leave the fleet")
	ext_FleetButton("FleetAct2", "")
}

;An empty caption hides the button. A button with nothing to do should not be
;on screen at all.
ext_FleetButton(name, caption) {
	global FleetSetupGui

	FleetSetupGui[name].Text := caption
	FleetSetupGui[name].Visible := (caption != "")
}

ext_FleetAct1(*) {
	global FleetRow, FleetHostRow, ext_fleetBindOpenUntil

	if (FleetRow <= 0) {
		ext_FleetJoinGUI()
		return
	}
	if (FleetHostRow = FleetRow) {
		;two minutes, which is the window the coordinator will honour anyway
		if ext_fleetOpenDoor(120)
			ext_fleetBindOpenUntil := nowUnix() + 120
		else
			MsgBox "The coordinator is not reachable from here yet. Wait for the fleet to come up and try again.", "Fleet", 0x40030
		ext_FleetWhoDraw()
		return
	}
	ext_FleetLeave()
}

ext_FleetAct2(*) {
	ext_FleetLeave()
}

;Forget the fleet. The roster file is left alone: this macro leaving is not a
;reason to lose everyone else's details, and the coordinator keeps its own copy.
ext_FleetLeave() {
	if (MsgBox("Leave the fleet?`n`nThis macro will stop talking to the others until it is set up again.",
		"Fleet", 0x40024) != "Yes")
		return
	ext_fleetStop()
	ext_FleetSave("FleetCheck", 0)
	ext_FleetSave("FleetRow", 0)
	ext_FleetSave("FleetHostRow", 0)
	ext_FleetWhoDraw()
}

;--- the join dialog ---------------------------------------------------------

;One window for both ways in. It shows what it can hear, and offers whichever
;action makes sense: join the fleet it found, or start one here if there is
;none. Asking "join or host?" before looking would be asking a question the
;program can answer itself.
ext_FleetJoinGUI(*) {
	global FleetJoinGui, ext_fleetBindResult

	if (IsSet(FleetJoinGui) && IsObject(FleetJoinGui)) {
		FleetJoinGui.Show()
		return
	}
	ext_fleetBindResult := ""
	ext_fleetDiscover()

	FleetJoinGui := Gui("+AlwaysOnTop +Border", "Set up this macro")
	FleetJoinGui.OnEvent("Close", ext_FleetJoinClose)
	FleetJoinGui.SetFont("s8 cDefault Bold", "Tahoma")
	FleetJoinGui.Add("GroupBox", "x8 y4 w404 h98", "What is this account?")
	FleetJoinGui.Add("GroupBox", "x8 y108 w404 h104", "Which fleet?")
	FleetJoinGui.SetFont("Norm")

	FleetJoinGui.Add("Text", "x18 y26 w40", "Name:")
	FleetJoinGui.Add("Edit", "x64 y24 w190 h18 vJoinName", A_ComputerName)
	FleetJoinGui.Add("Text", "x18 y50 w40", "Role:")
	FleetJoinGui.Add("DropDownList", "x64 y48 w110 vJoinRole Choose4", roster_Roles())
	FleetJoinGui.Add("Text", "x18 y74 w40", "User:")
	FleetJoinGui.Add("Edit", "x64 y72 w190 h18 vJoinUser")
	FleetJoinGui.SetFont("c808080")
	FleetJoinGui.Add("Text", "x262 y26 w142", "The Roblox username is only needed to force an account out of a server.")
	FleetJoinGui.SetFont("cDefault")

	FleetJoinGui.Add("Text", "x18 y128 w386 vJoinFound", "Listening for a fleet on your network...")
	FleetJoinGui.Add("Button", "x18 y150 w180 h26 vJoinButton Disabled", "Join this fleet").OnEvent("Click", ext_FleetJoinDo)
	FleetJoinGui.Add("Button", "x208 y150 w196 h26", "Start a new fleet here").OnEvent("Click", ext_FleetHostDo)
	FleetJoinGui.SetFont("c808080")
	FleetJoinGui.Add("Text", "x18 y182 w386"
		, "To join, open the door on the macro that hosts the fleet first - settings, Accept new macros.")
	FleetJoinGui.SetFont("cDefault")

	FleetJoinGui.Add("Button", "x312 y220 w100 h26", "Cancel").OnEvent("Click", ext_FleetJoinClose)

	SetTimer ext_FleetJoinRefresh, 500
	ext_FleetJoinRefresh()
	FleetJoinGui.Show("w420 h256")
}

ext_FleetJoinClose(*) {
	global FleetJoinGui

	SetTimer ext_FleetJoinRefresh, 0
	if (IsSet(FleetJoinGui) && IsObject(FleetJoinGui))
		FleetJoinGui.Destroy(), FleetJoinGui := ""
}

;What we can hear, twice a second. The button turns on by itself when a fleet
;answers, which is the clearest way to say "now you can".
ext_FleetJoinRefresh() {
	global FleetJoinGui, ext_fleetBindResult
	local open

	if !(IsSet(FleetJoinGui) && IsObject(FleetJoinGui))
		return
	if (ext_fleetBindResult = "ok") {
		ext_FleetJoinClose()
		MsgBox "Joined. This macro will rejoin on its own from now on.", "Fleet", 0x40040
		ext_FleetWhoDraw()
		return
	}
	if (ext_fleetBindResult != "") {
		MsgBox ext_fleetBindResult, "Fleet", 0x40030
		ext_fleetBindResult := ""
		return
	}
	open := ext_fleetOpenFleets()
	if open.Length {
		FleetJoinGui["JoinFound"].Text := "Found " open[1].host
			. " (" open[1].size " accounts), accepting new macros."
		FleetJoinGui["JoinButton"].Enabled := true
	}
	else {
		FleetJoinGui["JoinFound"].Text := "Listening for a fleet on your network..."
		FleetJoinGui["JoinButton"].Enabled := false
	}
}

ext_FleetJoinDo(*) {
	global FleetJoinGui
	local open := ext_fleetOpenFleets()

	if !open.Length
		return
	ext_fleetBind(open[1].addr, open[1].port
		, Trim(FleetJoinGui["JoinName"].Value)
		, FleetJoinGui["JoinRole"].Text
		, Trim(FleetJoinGui["JoinUser"].Value))
}

ext_FleetHostDo(*) {
	global FleetJoinGui

	ext_fleetStartFleet(Trim(FleetJoinGui["JoinName"].Value)
		, FleetJoinGui["JoinRole"].Text
		, Trim(FleetJoinGui["JoinUser"].Value))
	ext_FleetJoinClose()
	MsgBox "This macro now hosts the fleet.`n`nTo add another, press Accept new macros here, then set that macro up.", "Fleet", 0x40040
	ext_FleetWhoDraw()
}

;Write one setting the way the rest of the macro does: the global and the ini
;together, so a restart finds what the screen showed.
ext_FleetSave(name, value) {
	global

	%name% := value
	IniWrite value, "settings\nm_config.ini", "Fleet", name
}

;--- the roster editor -------------------------------------------------------

ext_FleetRosterDraw() {
	global FleetSetupGui, FleetRoster, FleetRosterOrder
	local keys := [], row, e

	if !(IsSet(FleetSetupGui) && IsObject(FleetSetupGui))
		return
	FleetSetupGui["FleetRosterList"].Delete()
	for row, _ in FleetRoster
		keys.Push(row)
	roster_Sort(keys)
	;the list shows no row numbers, so it keeps its own note of which line is
	;which account
	FleetRosterOrder := keys
	for _, row in keys {
		e := FleetRoster[row]
		FleetSetupGui["FleetRosterList"].Add(, e.name, e.role, e.user, e.owner ? "yes" : "")
	}
	Loop 4
		FleetSetupGui["FleetRosterList"].ModifyCol(A_Index, "AutoHdr")
}

ext_FleetRosterSelect(ctrl, item, selected) {
	global FleetSetupGui, FleetRoster, FleetRosterOrder, FleetEditRow
	local row

	if (!selected || !item || (item > FleetRosterOrder.Length))
		return
	FleetEditRow := row := FleetRosterOrder[item]
	if !FleetRoster.Has(row)
		return
	FleetSetupGui["FleetEditName"].Value := FleetRoster[row].name
	FleetSetupGui["FleetEditRole"].Text := FleetRoster[row].role
	FleetSetupGui["FleetEditUser"].Value := FleetRoster[row].user
	FleetSetupGui["FleetEditOwner"].Value := FleetRoster[row].owner
}

;Editing only. Accounts arrive by binding, so there is no Add here - a row this
;list has never seen would be a row no macro answers to.
ext_FleetRosterSave(*) {
	global FleetSetupGui, FleetRoster, FleetRosterPath, FleetEditRow
	local other

	if (!FleetEditRow || !FleetRoster.Has(FleetEditRow)) {
		MsgBox "Pick an account in the list first.", "Fleet", 0x40030
		return
	}
	;only one account can own the private server, so ticking it here clears it
	;elsewhere rather than leaving two and choosing one silently later
	if FleetSetupGui["FleetEditOwner"].Value
		for other, _ in FleetRoster
			FleetRoster[other].owner := 0
	FleetRoster[FleetEditRow].name := Trim(FleetSetupGui["FleetEditName"].Value)
	FleetRoster[FleetEditRow].role := FleetSetupGui["FleetEditRole"].Text
	FleetRoster[FleetEditRow].user := Trim(FleetSetupGui["FleetEditUser"].Value)
	FleetRoster[FleetEditRow].owner := FleetSetupGui["FleetEditOwner"].Value ? 1 : 0
	if (FleetRoster[FleetEditRow].name = "")
		FleetRoster[FleetEditRow].name := "row " FleetEditRow
	roster_Save(FleetRosterPath, FleetRoster)
	ext_FleetRosterDraw()
}

ext_FleetRosterRemove(*) {
	global FleetRoster, FleetRosterPath, FleetEditRow

	if (!FleetEditRow || !FleetRoster.Has(FleetEditRow))
		return
	if (MsgBox("Remove " FleetRoster[FleetEditRow].name " from the fleet?`n`nThat macro will be refused until it is set up again.",
		"Fleet", 0x40024) != "Yes")
		return
	FleetRoster.Delete(FleetEditRow)
	roster_Save(FleetRosterPath, FleetRoster)
	FleetEditRow := 0
	ext_FleetRosterDraw()
}

;Port, grace and a hand-typed address. Tucked away because a fleet on an
;ordinary network needs none of them, and a window that shows everything at
;once is a window nobody reads.
ext_FleetAdvanced(*) {
	global FleetSetupGui, FleetAdvGui, FleetPort, FleetGraceSecs, FleetAddress
	local GuiCtrl

	if (IsSet(FleetAdvGui) && IsObject(FleetAdvGui)) {
		FleetAdvGui.Show()
		return
	}
	FleetAdvGui := Gui("+AlwaysOnTop +Owner" FleetSetupGui.Hwnd, "Fleet - advanced")
	FleetAdvGui.OnEvent("Close", ext_FleetAdvClose)
	FleetAdvGui.SetFont("s8 cDefault Norm", "Tahoma")

	FleetAdvGui.Add("Text", "x12 y14 w96", "Port:")
	(GuiCtrl := FleetAdvGui.Add("Edit", "x112 y12 w70 h18 Number vFleetPort", FleetPort)).Section := "Fleet"
	GuiCtrl.OnEvent("Change", nm_saveConfig)
	FleetAdvGui.SetFont("c808080")
	FleetAdvGui.Add("Text", "x12 y34 w360", "The discovery beacon uses the next port up. Change it on every macro or on none.")
	FleetAdvGui.SetFont("cDefault")

	FleetAdvGui.Add("Text", "x12 y72 w96", "Grace period:")
	(GuiCtrl := FleetAdvGui.Add("Edit", "x112 y70 w70 h18 Number vFleetGraceSecs", FleetGraceSecs)).Section := "Fleet"
	GuiCtrl.OnEvent("Change", nm_saveConfig)
	FleetAdvGui.Add("Text", "x188 y72 w40", "sec")
	FleetAdvGui.SetFont("c808080")
	FleetAdvGui.Add("Text", "x12 y92 w360", "How long the coordinator may stay silent before another macro takes over.")
	FleetAdvGui.SetFont("cDefault")

	FleetAdvGui.Add("Text", "x12 y130 w96", "Address:")
	(GuiCtrl := FleetAdvGui.Add("Edit", "x112 y128 w180 h18 vFleetAddress", FleetAddress)).Section := "Fleet"
	GuiCtrl.OnEvent("Change", nm_saveConfig)
	FleetAdvGui.SetFont("c808080")
	FleetAdvGui.Add("Text", "x12 y150 w360"
		, "Leave this empty. The coordinator is found by beacon, and an address typed`nhere would be wrong the moment the router hands out a new lease. Fill it in`nonly if broadcasts are blocked on your network.")
	FleetAdvGui.SetFont("cDefault")

	FleetAdvGui.Add("Button", "x292 y200 w80 h24", "Close").OnEvent("Click", ext_FleetAdvClose)
	FleetAdvGui.Show("w384 h238")
}

ext_FleetAdvClose(*) {
	global FleetAdvGui

	if (IsSet(FleetAdvGui) && IsObject(FleetAdvGui))
		FleetAdvGui.Destroy(), FleetAdvGui := ""
}

;The two live lines on the main window. Dots rather than a count, because the
;shape of ●●●●○○ reads without being counted - and a gap in it is the thing
;worth noticing. The second line carries whatever deadline is nearest, since
;that is the only number that ever demands action.
ext_fleetTabStatus() {
	global MainGui, FleetCheck, ext_fleetSock, ext_fleetTerm, ext_fleetPeers
	local seats := "", online := 0, away := 0, p, capacity := ext_fleetCapacity()

	if !FleetCheck {
		try MainGui["FleetStripSeats"].Text := "Off"
		try MainGui["FleetStripNext"].Text := ""
		return
	}
	if !ext_fleetSock {
		try MainGui["FleetStripSeats"].Text := ext_fleetSummary()
		try MainGui["FleetStripNext"].Text := ""
		return
	}
	for _, p in ext_fleetView() {
		if (ext_FleetCell(p, "state") = "online")
			online++
		else
			away++
	}
	Loop capacity
		seats .= (A_Index <= online) ? Chr(0x25CF) : Chr(0x25CB)
	try MainGui["FleetStripSeats"].Text := seats "  " online " seated"
		. (away ? " - " away " away" : "") " - term " ext_fleetTerm
	try MainGui["FleetStripNext"].Text := ext_fleetNextDeadline()
}

;The nearest thing that will need doing, in words. Nothing on the horizon is
;itself worth saying: silence from a status line reads as a fault.
ext_fleetNextDeadline() {
	global ext_fleetPeers
	local p, left, best := 0, who := ""

	for _, p in ext_fleetView() {
		if (ext_FleetCell(p, "guiding") = "")
			continue
		left := Integer(ext_FleetCell(p, "until")) - nowUnix()
		if ((left > 0) && (!best || (left < best)))
			best := left, who := ext_FleetCell(p, "name")
	}
	if best
		return "Star " Floor(best / 60) ":" Format("{:02}", Mod(best, 60)) " (" who ")"
	return "No star running"
}
