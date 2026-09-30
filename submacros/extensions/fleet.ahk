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

;The Fleet panel.
;
;Laid out as three steps and a picture, because the hard part of setting a fleet
;up is not the values - it is knowing which of them differ from machine to
;machine. Step one is the only thing each macro answers for itself; steps two
;and three are identical everywhere, and the panel says so on screen rather than
;leaving it to be discovered.
;
;Port, grace period and a hand-typed address live behind Advanced. They have
;working defaults, and a fleet found by beacon needs none of them.
ext_FleetGUI(*) {
	global FleetGui, FleetRoster, FleetRosterPath
	global FleetRow, FleetHostRow, FleetSecret, FleetServerMain, FleetServerReserve
	local GuiCtrl

	if (IsSet(FleetGui) && IsObject(FleetGui)) {
		FleetGui.Show()
		return
	}
	FleetRosterPath := A_WorkingDir "\settings\fleet_roster.ini"
	FleetRoster := roster_Load(FleetRosterPath)

	FleetGui := Gui("+AlwaysOnTop +Border", "Fleet")
	FleetGui.OnEvent("Close", ext_FleetGUIClose)
	FleetGui.SetFont("s8 cDefault Bold", "Tahoma")
	FleetGui.Add("GroupBox", "x8 y4 w584 h64", "Step 1 - which account is this macro?")
	FleetGui.Add("GroupBox", "x8 y72 w584 h88", "Step 2 - the same on every macro")
	FleetGui.Add("GroupBox", "x8 y168 w584 h150", "Step 3 - the accounts")
	FleetGui.Add("GroupBox", "x8 y326 w584 h170", "The fleet right now")
	FleetGui.SetFont("Norm")

	;--- step 1: the only answer that differs per machine ------------------
	FleetGui.Add("Text", "x18 y25 w86", "This macro is:")
	FleetGui.Add("DropDownList", "x108 y22 w250 vFleetWhoAmI").OnEvent("Change", ext_FleetWhoChanged)
	FleetGui.Add("CheckBox", "x372 y24 w210 vFleetIsHost Checked" ((FleetHostRow > 0) && (FleetHostRow = FleetRow))
		, "This macro hosts the coordinator").OnEvent("Click", ext_FleetHostChanged)
	FleetGui.SetFont("c808080")
	FleetGui.Add("Text", "x18 y46 w564"
		, "Every macro answers this one differently. Everything below is identical on all of them.")
	FleetGui.SetFont("cDefault")

	;--- step 2: shared -----------------------------------------------------
	FleetGui.Add("Text", "x18 y93 w86", "Fleet secret:")
	(GuiCtrl := FleetGui.Add("Edit", "x108 y91 w170 h18 vFleetSecret", FleetSecret)).Section := "Fleet"
	GuiCtrl.OnEvent("Change", nm_saveConfig)
	FleetGui.SetFont("c808080")
	FleetGui.Add("Text", "x286 y93 w300", "Any word, as long as it matches on every macro.")
	FleetGui.SetFont("cDefault")
	FleetGui.Add("Text", "x18 y117 w86", "Main server:")
	(GuiCtrl := FleetGui.Add("Edit", "x108 y115 w474 h18 vFleetServerMain", FleetServerMain)).Section := "Fleet"
	GuiCtrl.OnEvent("Change", nm_saveConfig)
	FleetGui.Add("Text", "x18 y139 w86", "Reserve:")
	(GuiCtrl := FleetGui.Add("Edit", "x108 y137 w474 h18 vFleetServerReserve", FleetServerReserve)).Section := "Fleet"
	GuiCtrl.OnEvent("Change", nm_saveConfig)

	;--- step 3: the roster -------------------------------------------------
	FleetGui.Add("ListView", "x16 y186 w340 h122 -Multi vFleetRosterList"
		, ["Row", "Name", "Role", "Roblox user", "Owner"])
	FleetGui["FleetRosterList"].OnEvent("ItemSelect", ext_FleetRosterSelect)
	FleetGui.Add("Text", "x364 y188 w32", "Row:")
	FleetGui.Add("Edit", "x398 y186 w40 h18 Number vFleetEditRow")
	FleetGui.Add("Text", "x446 y188 w36", "Name:")
	FleetGui.Add("Edit", "x484 y186 w98 h18 vFleetEditName")
	FleetGui.Add("Text", "x364 y212 w32", "Role:")
	FleetGui.Add("DropDownList", "x398 y210 w84 vFleetEditRole", roster_Roles())
	FleetGui.Add("Text", "x364 y236 w32", "User:")
	FleetGui.Add("Edit", "x398 y234 w184 h18 vFleetEditUser")
	FleetGui.Add("CheckBox", "x398 y258 w184 vFleetEditOwner", "Owns the private server")
	FleetGui.Add("Button", "x364 y280 w104 h24", "Add / update").OnEvent("Click", ext_FleetRosterSave)
	FleetGui.Add("Button", "x478 y280 w104 h24", "Remove").OnEvent("Click", ext_FleetRosterRemove)

	;--- the live picture ---------------------------------------------------
	FleetGui.Add("Text", "x16 y344 w568 vFleetSummary", ext_fleetSummary())
	FleetGui.Add("ListView", "x16 y364 w568 h124 -Multi vFleetLive"
		, ["Row", "Name", "Role", "State", "Machine", "Field", "Server"])

	FleetGui.Add("Button", "x8 y502 w90 h24", "Advanced").OnEvent("Click", ext_FleetAdvanced)
	FleetGui.Add("Button", "x502 y502 w90 h24", "Close").OnEvent("Click", ext_FleetGUIClose)

	ext_FleetRosterDraw()
	ext_FleetRefresh()
	;the live half is only worth having if it keeps up with the fleet
	SetTimer ext_FleetRefresh, 1000
	FleetGui.Show("w600 h534")
}

ext_FleetGUIClose(*) {
	global FleetGui

	SetTimer ext_FleetRefresh, 0
	if (IsSet(FleetGui) && IsObject(FleetGui))
		FleetGui.Destroy(), FleetGui := ""
}

;Port, grace and a hand-typed address. Tucked away because a fleet on an
;ordinary network needs none of them, and a panel that shows everything at once
;is a panel nobody can read.
ext_FleetAdvanced(*) {
	global FleetGui, FleetAdvGui, FleetPort, FleetGraceSecs, FleetAddress
	local GuiCtrl

	if (IsSet(FleetAdvGui) && IsObject(FleetAdvGui)) {
		FleetAdvGui.Show()
		return
	}
	FleetAdvGui := Gui("+AlwaysOnTop +Owner" FleetGui.Hwnd, "Fleet - advanced")
	FleetAdvGui.OnEvent("Close", (*) => (FleetAdvGui.Destroy(), FleetAdvGui := ""))
	FleetAdvGui.SetFont("s8 cDefault Norm", "Tahoma")

	FleetAdvGui.Add("Text", "x12 y14 w96", "Port:")
	(GuiCtrl := FleetAdvGui.Add("Edit", "x112 y12 w70 h18 Number vFleetPort", FleetPort)).Section := "Fleet"
	GuiCtrl.OnEvent("Change", nm_saveConfig)
	FleetAdvGui.SetFont("c808080")
	FleetAdvGui.Add("Text", "x12 y34 w360", "The beacon uses the next port up. Change it on every macro or none.")
	FleetAdvGui.SetFont("cDefault")

	FleetAdvGui.Add("Text", "x12 y60 w96", "Grace period:")
	(GuiCtrl := FleetAdvGui.Add("Edit", "x112 y58 w70 h18 Number vFleetGraceSecs", FleetGraceSecs)).Section := "Fleet"
	GuiCtrl.OnEvent("Change", nm_saveConfig)
	FleetAdvGui.Add("Text", "x188 y60 w40", "sec")
	FleetAdvGui.SetFont("c808080")
	FleetAdvGui.Add("Text", "x12 y80 w360", "How long the coordinator may stay silent before another macro takes over.")
	FleetAdvGui.SetFont("cDefault")

	FleetAdvGui.Add("Text", "x12 y106 w96", "Address:")
	(GuiCtrl := FleetAdvGui.Add("Edit", "x112 y104 w180 h18 vFleetAddress", FleetAddress)).Section := "Fleet"
	GuiCtrl.OnEvent("Change", nm_saveConfig)
	FleetAdvGui.SetFont("c808080")
	FleetAdvGui.Add("Text", "x12 y126 w360"
		, "Leave this empty. The coordinator is found by beacon, and an address typed`nhere would be wrong the moment the router hands out a new lease. Fill it in`nonly if broadcasts are blocked on your network.")
	FleetAdvGui.SetFont("cDefault")

	FleetAdvGui.Add("Button", "x292 y176 w80 h24", "Close").OnEvent("Click", (*) => (FleetAdvGui.Destroy(), FleetAdvGui := ""))
	FleetAdvGui.Show("w384 h212")
}

;--- step 1 ----------------------------------------------------------------

;The account list, as names rather than numbers. A row number means nothing to
;the person filling this in; "2 - fuzzy 1" does.
ext_FleetWhoDraw() {
	global FleetGui, FleetRoster, FleetRow
	local keys := [], row, items := [], pick := 0

	if !(IsSet(FleetGui) && IsObject(FleetGui))
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
	FleetGui["FleetWhoAmI"].Delete()
	FleetGui["FleetWhoAmI"].Add(items)
	FleetGui["FleetWhoAmI"].Value := pick ? pick : 1
}

;Picking an account here is the one setting this machine owns.
ext_FleetWhoChanged(ctrl, *) {
	global FleetRow, FleetHostRow, FleetGui
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
	if FleetGui["FleetIsHost"].Value
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

;--- step 3 ----------------------------------------------------------------

ext_FleetRosterDraw() {
	global FleetGui, FleetRoster
	local keys := [], row, e

	if !(IsSet(FleetGui) && IsObject(FleetGui))
		return
	FleetGui["FleetRosterList"].Delete()
	for row, _ in FleetRoster
		keys.Push(row)
	roster_Sort(keys)
	for _, row in keys {
		e := FleetRoster[row]
		FleetGui["FleetRosterList"].Add(, row, e.name, e.role, e.user, e.owner ? "yes" : "")
	}
	Loop 5
		FleetGui["FleetRosterList"].ModifyCol(A_Index, "AutoHdr")
	ext_FleetWhoDraw()
}

ext_FleetRosterSelect(ctrl, item, selected) {
	global FleetGui, FleetRoster
	local row

	if (!selected || !item)
		return
	row := Integer(ctrl.GetText(item, 1))
	if !FleetRoster.Has(row)
		return
	FleetGui["FleetEditRow"].Value := row
	FleetGui["FleetEditName"].Value := FleetRoster[row].name
	FleetGui["FleetEditRole"].Text := FleetRoster[row].role
	FleetGui["FleetEditUser"].Value := FleetRoster[row].user
	FleetGui["FleetEditOwner"].Value := FleetRoster[row].owner
}

;One button for adding and for editing, since a row number the fleet has not
;seen before is simply a new account.
ext_FleetRosterSave(*) {
	global FleetGui, FleetRoster, FleetRosterPath
	local row, other

	if (!(row := Integer(FleetGui["FleetEditRow"].Value)) || (row <= 0)) {
		MsgBox "Give the account a row number.`n`nIt is how a macro says which account it is, and the only thing that ties it to this list.", "Fleet", 0x40030
		return
	}
	;only one account can own the private server, so ticking it here clears it
	;elsewhere rather than leaving two and choosing one silently later
	if FleetGui["FleetEditOwner"].Value
		for other, _ in FleetRoster
			FleetRoster[other].owner := 0
	FleetRoster[row] := { row: row
		, name: Trim(FleetGui["FleetEditName"].Value)
		, role: FleetGui["FleetEditRole"].Text
		, user: Trim(FleetGui["FleetEditUser"].Value)
		, owner: FleetGui["FleetEditOwner"].Value ? 1 : 0 }
	if (FleetRoster[row].name = "")
		FleetRoster[row].name := "row " row
	roster_Save(FleetRosterPath, FleetRoster)
	ext_FleetRosterDraw()
}

ext_FleetRosterRemove(*) {
	global FleetGui, FleetRoster, FleetRosterPath
	local row

	row := Integer(FleetGui["FleetEditRow"].Value)
	if !FleetRoster.Has(row)
		return
	FleetRoster.Delete(row)
	roster_Save(FleetRosterPath, FleetRoster)
	ext_FleetRosterDraw()
}

;--- the live picture -------------------------------------------------------

ext_FleetRefresh() {
	global FleetGui
	local lv, p

	if !(IsSet(FleetGui) && IsObject(FleetGui))
		return
	try FleetGui["FleetSummary"].Value := ext_fleetSummary()
	lv := FleetGui["FleetLive"]
	lv.Delete()
	for _, p in ext_fleetView()
		lv.Add(, ext_FleetCell(p, "row"), ext_FleetCell(p, "name"), ext_FleetCell(p, "role")
			, ext_FleetCell(p, "state"), ext_FleetCell(p, "machine")
			, ext_FleetCell(p, "field"), ext_FleetCell(p, "server"))
	Loop 7
		lv.ModifyCol(A_Index, "AutoHdr")
}

;A roster frame carries whatever the coordinator chose to send, so a field that
;is not there is normal rather than a fault.
ext_FleetCell(fields, name) {
	return fields.Has(name) ? fields[name] : ""
}

;The one line of fleet state that belongs on the main window, so the panel does
;not have to be open to notice the fleet has fallen over.
ext_fleetTabStatus() {
	global MainGui

	try MainGui["FleetStatusText"].Text := ext_fleetSummary()
}
