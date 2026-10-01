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
	global FleetSecret, ext_fleetFoundAt, ext_fleetSock
	local frame := fleet_Parse(data)

	if (!frame || (frame.verb != "FLEET"))
		return
	if (fleet_Field(frame, "id") != fleet_Fingerprint(FleetSecret))
		return
	ext_fleetFoundAt := from
	;a beacon while we are adrift is the best news we are going to get, so act on
	;it rather than sitting out whatever backoff happens to be running
	if !ext_fleetSock
		SetTimer ext_fleetConnect, -200
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
	global ext_fleetEvents
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
		case "BYE":
			nm_setStatus("Failed", "Fleet refused this macro`n" fleet_Field(frame, "why"))
	}
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

	if (!FleetCheck || (FleetRow <= 0))
		return 0
	;start listening before anything else, so a coordinator that is already up
	;is found on its very next beacon
	ext_fleetDiscover()
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

;Three steps and an Advanced button. The hard part of setting a fleet up was
;never the values, it was knowing which of them differ from machine to machine -
;so step one is the single question each macro answers for itself, and the
;window says as much rather than leaving it to be found out.
ext_FleetSetupGUI(*) {
	global FleetSetupGui, FleetRoster, FleetRosterPath
	global FleetRow, FleetHostRow, FleetSecret, FleetServerMain, FleetServerReserve
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
	FleetSetupGui.Add("GroupBox", "x8 y4 w584 h64", "1 - which account is this macro?")
	FleetSetupGui.Add("GroupBox", "x8 y72 w584 h88", "2 - the same on every macro")
	FleetSetupGui.Add("GroupBox", "x8 y168 w584 h150", "3 - the accounts")
	FleetSetupGui.SetFont("Norm")

	FleetSetupGui.Add("Text", "x18 y25 w86", "This macro is:")
	FleetSetupGui.Add("DropDownList", "x108 y22 w250 vFleetWhoAmI").OnEvent("Change", ext_FleetWhoChanged)
	FleetSetupGui.Add("CheckBox", "x372 y24 w210 vFleetIsHost Checked" ((FleetHostRow > 0) && (FleetHostRow = FleetRow))
		, "This macro hosts the coordinator").OnEvent("Click", ext_FleetHostChanged)
	FleetSetupGui.SetFont("c808080")
	FleetSetupGui.Add("Text", "x18 y46 w564"
		, "Every macro answers this one differently. Everything below is identical on all of them.")
	FleetSetupGui.SetFont("cDefault")

	FleetSetupGui.Add("Text", "x18 y93 w86", "Fleet secret:")
	(GuiCtrl := FleetSetupGui.Add("Edit", "x108 y91 w170 h18 vFleetSecret", FleetSecret)).Section := "Fleet"
	GuiCtrl.OnEvent("Change", nm_saveConfig)
	FleetSetupGui.SetFont("c808080")
	FleetSetupGui.Add("Text", "x286 y93 w300", "Any word, as long as it matches on every macro.")
	FleetSetupGui.SetFont("cDefault")
	FleetSetupGui.Add("Text", "x18 y117 w86", "Main server:")
	(GuiCtrl := FleetSetupGui.Add("Edit", "x108 y115 w474 h18 vFleetServerMain", FleetServerMain)).Section := "Fleet"
	GuiCtrl.OnEvent("Change", nm_saveConfig)
	FleetSetupGui.Add("Text", "x18 y139 w86", "Reserve:")
	(GuiCtrl := FleetSetupGui.Add("Edit", "x108 y137 w474 h18 vFleetServerReserve", FleetServerReserve)).Section := "Fleet"
	GuiCtrl.OnEvent("Change", nm_saveConfig)

	FleetSetupGui.Add("ListView", "x16 y186 w340 h122 -Multi vFleetRosterList"
		, ["Row", "Name", "Role", "Roblox user", "Owner"])
	FleetSetupGui["FleetRosterList"].OnEvent("ItemSelect", ext_FleetRosterSelect)
	FleetSetupGui.Add("Text", "x364 y188 w36", "Row:")
	FleetSetupGui.Add("Edit", "x402 y186 w40 h18 Number vFleetEditRow")
	FleetSetupGui.Add("Text", "x450 y188 w32", "Name:")
	FleetSetupGui.Add("Edit", "x484 y186 w98 h18 vFleetEditName")
	FleetSetupGui.Add("Text", "x364 y212 w36", "Role:")
	FleetSetupGui.Add("DropDownList", "x402 y210 w84 vFleetEditRole", roster_Roles())
	FleetSetupGui.Add("Text", "x364 y236 w36", "User:")
	FleetSetupGui.Add("Edit", "x402 y234 w180 h18 vFleetEditUser")
	FleetSetupGui.Add("CheckBox", "x402 y258 w180 vFleetEditOwner", "Owns the private server")
	FleetSetupGui.Add("Button", "x364 y280 w104 h24", "Add / update").OnEvent("Click", ext_FleetRosterSave)
	FleetSetupGui.Add("Button", "x478 y280 w104 h24", "Remove").OnEvent("Click", ext_FleetRosterRemove)

	FleetSetupGui.Add("Button", "x8 y326 w100 h26", "Advanced").OnEvent("Click", ext_FleetAdvanced)
	FleetSetupGui.Add("Button", "x492 y326 w100 h26", "Close").OnEvent("Click", ext_FleetSetupClose)

	ext_FleetRosterDraw()
	FleetSetupGui.Show("w600 h364")
}

ext_FleetSetupClose(*) {
	global FleetSetupGui

	if (IsSet(FleetSetupGui) && IsObject(FleetSetupGui))
		FleetSetupGui.Destroy(), FleetSetupGui := ""
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

;--- the roster editor -------------------------------------------------------

;The account list, as names rather than numbers. A row number means nothing to
;the person filling this in; "2 - fuzzy 1" does.
ext_FleetWhoDraw() {
	global FleetSetupGui, FleetRoster, FleetRow
	local keys := [], row, items := [], pick := 0

	if !(IsSet(FleetSetupGui) && IsObject(FleetSetupGui))
		return
	for row, _ in FleetRoster
		keys.Push(row)
	roster_Sort(keys)
	for _, row in keys {
		items.Push(row " - " FleetRoster[row].name " (" FleetRoster[row].role ")")
		if (row = FleetRow)
			pick := items.Length
	}
	if !items.Length
		items.Push("(add your accounts in step 3 first)")
	FleetSetupGui["FleetWhoAmI"].Delete()
	FleetSetupGui["FleetWhoAmI"].Add(items)
	FleetSetupGui["FleetWhoAmI"].Value := pick ? pick : 1
}

ext_FleetWhoChanged(ctrl, *) {
	global FleetRow, FleetHostRow, FleetSetupGui
	local first := StrSplit(Trim(ctrl.Text), " ")[1], row

	;an empty roster shows a placeholder instead of an account, and that has
	;no number in front of it to read
	if !IsInteger(first)
		return
	if ((row := Integer(first)) <= 0)
		return
	ext_FleetSave("FleetRow", row)
	;the host flag follows the account, not the machine: tick it here and this
	;row is the one that hosts, whichever computer it happens to run on
	if FleetSetupGui["FleetIsHost"].Value
		ext_FleetSave("FleetHostRow", row)
}

ext_FleetHostChanged(ctrl, *) {
	global FleetRow

	ext_FleetSave("FleetHostRow", ctrl.Value ? FleetRow : 0)
}

;Write one setting the way the rest of the macro does.
ext_FleetSave(name, value) {
	global

	%name% := value
	IniWrite value, "settings\nm_config.ini", "Fleet", name
}

ext_FleetRosterDraw() {
	global FleetSetupGui, FleetRoster
	local keys := [], row, e

	if !(IsSet(FleetSetupGui) && IsObject(FleetSetupGui))
		return
	FleetSetupGui["FleetRosterList"].Delete()
	for row, _ in FleetRoster
		keys.Push(row)
	roster_Sort(keys)
	for _, row in keys {
		e := FleetRoster[row]
		FleetSetupGui["FleetRosterList"].Add(, row, e.name, e.role, e.user, e.owner ? "yes" : "")
	}
	Loop 5
		FleetSetupGui["FleetRosterList"].ModifyCol(A_Index, "AutoHdr")
	ext_FleetWhoDraw()
}

ext_FleetRosterSelect(ctrl, item, selected) {
	global FleetSetupGui, FleetRoster
	local row

	if (!selected || !item)
		return
	row := Integer(ctrl.GetText(item, 1))
	if !FleetRoster.Has(row)
		return
	FleetSetupGui["FleetEditRow"].Value := row
	FleetSetupGui["FleetEditName"].Value := FleetRoster[row].name
	FleetSetupGui["FleetEditRole"].Text := FleetRoster[row].role
	FleetSetupGui["FleetEditUser"].Value := FleetRoster[row].user
	FleetSetupGui["FleetEditOwner"].Value := FleetRoster[row].owner
}

;One button for adding and for editing, since a row number the fleet has not
;seen before is simply a new account.
ext_FleetRosterSave(*) {
	global FleetSetupGui, FleetRoster, FleetRosterPath
	local row, other

	if (!(row := Integer(FleetSetupGui["FleetEditRow"].Value)) || (row <= 0)) {
		MsgBox "Give the account a row number.`n`nIt is how a macro says which account it is, and the only thing that ties it to this list.", "Fleet", 0x40030
		return
	}
	;only one account can own the private server, so ticking it here clears it
	;elsewhere rather than leaving two and choosing one silently later
	if FleetSetupGui["FleetEditOwner"].Value
		for other, _ in FleetRoster
			FleetRoster[other].owner := 0
	FleetRoster[row] := { row: row
		, name: Trim(FleetSetupGui["FleetEditName"].Value)
		, role: FleetSetupGui["FleetEditRole"].Text
		, user: Trim(FleetSetupGui["FleetEditUser"].Value)
		, owner: FleetSetupGui["FleetEditOwner"].Value ? 1 : 0 }
	if (FleetRoster[row].name = "")
		FleetRoster[row].name := "row " row
	roster_Save(FleetRosterPath, FleetRoster)
	ext_FleetRosterDraw()
}

ext_FleetRosterRemove(*) {
	global FleetSetupGui, FleetRoster, FleetRosterPath
	local row

	row := Integer(FleetSetupGui["FleetEditRow"].Value)
	if !FleetRoster.Has(row)
		return
	FleetRoster.Delete(row)
	roster_Save(FleetRosterPath, FleetRoster)
	ext_FleetRosterDraw()
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
