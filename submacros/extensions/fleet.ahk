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

;Where to look for the coordinator, in order.
;
;Loopback first, always. If the coordinator is on this machine that is both the
;fastest path and the correct answer, and it costs one refused connection to
;find out - a refusal on loopback comes back immediately. It also handles the
;case that matters most: a macro whose neighbour on the same machine has just
;taken over as acting coordinator.
ext_fleetConnect() {
	global FleetPort, FleetAddress, ext_fleetSock, ext_fleetTrying

	if ext_fleetSock
		return 0
	ext_fleetTrying := "127.0.0.1"
	ext_fleetSock := sock_Connect("127.0.0.1", FleetPort, ext_fleetOnSocket)
	if !ext_fleetSock
		ext_fleetRetryLater()
	return 1
}

;Everything the socket layer reports about our one connection.
ext_fleetOnSocket(s, event, data) {
	global ext_fleetSock, ext_fleetTrying, FleetAddress, FleetPort

	if (event = "connect") {
		if (data = "") {
			ext_fleetHello()
			return
		}
		;loopback refused means the coordinator is not here - try the address the
		;panel was given, once, before falling back to waiting
		sock_Close(s), ext_fleetSock := 0
		if ((ext_fleetTrying = "127.0.0.1") && (FleetAddress != "")
			&& (FleetAddress != "127.0.0.1")) {
			ext_fleetTrying := FleetAddress
			ext_fleetSock := sock_Connect(FleetAddress, FleetPort, ext_fleetOnSocket)
			if ext_fleetSock
				return
		}
		ext_fleetRetryLater()
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
	global FleetCheck, ext_fleetTrying
	local silent

	if !FleetCheck
		return "Fleet is off"
	if !ext_fleetSock
		return "Not connected - looking for a coordinator"
	silent := nowUnix() - ext_fleetCoordSeen
	return "Connected to " ext_fleetTrying
		. (ext_fleetCoordRow ? " (row " ext_fleetCoordRow ")" : "")
		. ", term " ext_fleetTerm
		. ((silent > 15) ? " - quiet for " silent "s" : "")
}

;The Fleet panel.
;
;Two halves that answer two different questions. The top is configuration - who
;this macro is, where the coordinator lives, and the roster of every account.
;The bottom is the live picture, which is the half you actually watch.
;
;The roster is edited here and nowhere else. It is written to
;settings\fleet_roster.ini, which the coordinator re-reads when it changes, so a
;rename takes effect without restarting anything.
ext_FleetGUI(*) {
	global FleetGui, FleetRoster, FleetRosterPath
	global FleetRow, FleetHostRow, FleetPort, FleetSecret, FleetAddress, FleetGraceSecs
	global FleetServerMain, FleetServerReserve
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
	FleetGui.Add("GroupBox", "x8 y4 w300 h108", "This macro")
	FleetGui.Add("GroupBox", "x314 y4 w268 h108", "Servers")
	FleetGui.Add("GroupBox", "x8 y116 w574 h132", "Roster")
	FleetGui.Add("GroupBox", "x8 y252 w574 h150", "The fleet right now")
	FleetGui.SetFont("Norm")

	;--- this macro -------------------------------------------------------
	FleetGui.Add("Text", "x18 y24 w86", "My row:")
	(GuiCtrl := FleetGui.Add("Edit", "x104 y22 w40 h18 Number vFleetRow", FleetRow)).Section := "Fleet"
	GuiCtrl.OnEvent("Change", nm_saveConfig)
	FleetGui.Add("Text", "x152 y24 w60", "Host row:")
	(GuiCtrl := FleetGui.Add("Edit", "x214 y22 w40 h18 Number vFleetHostRow", FleetHostRow)).Section := "Fleet"
	GuiCtrl.OnEvent("Change", nm_saveConfig)

	FleetGui.Add("Text", "x18 y46 w86", "Port:")
	(GuiCtrl := FleetGui.Add("Edit", "x104 y44 w60 h18 Number vFleetPort", FleetPort)).Section := "Fleet"
	GuiCtrl.OnEvent("Change", nm_saveConfig)
	FleetGui.Add("Text", "x172 y46 w42", "Grace:")
	(GuiCtrl := FleetGui.Add("Edit", "x214 y44 w40 h18 Number vFleetGraceSecs", FleetGraceSecs)).Section := "Fleet"
	GuiCtrl.OnEvent("Change", nm_saveConfig)
	FleetGui.Add("Text", "x258 y46 w40", "sec")

	FleetGui.Add("Text", "x18 y68 w86", "Secret:")
	(GuiCtrl := FleetGui.Add("Edit", "x104 y66 w190 h18 vFleetSecret", FleetSecret)).Section := "Fleet"
	GuiCtrl.OnEvent("Change", nm_saveConfig)

	;left blank on the host's own machine, where loopback finds it anyway
	FleetGui.Add("Text", "x18 y90 w86", "Coordinator:")
	(GuiCtrl := FleetGui.Add("Edit", "x104 y88 w190 h18 vFleetAddress", FleetAddress)).Section := "Fleet"
	GuiCtrl.OnEvent("Change", nm_saveConfig)

	;--- servers ----------------------------------------------------------
	FleetGui.Add("Text", "x324 y24 w54", "Main:")
	(GuiCtrl := FleetGui.Add("Edit", "x324 y40 w248 h18 vFleetServerMain", FleetServerMain)).Section := "Fleet"
	GuiCtrl.OnEvent("Change", nm_saveConfig)
	FleetGui.Add("Text", "x324 y64 w54", "Reserve:")
	(GuiCtrl := FleetGui.Add("Edit", "x324 y80 w248 h18 vFleetServerReserve", FleetServerReserve)).Section := "Fleet"
	GuiCtrl.OnEvent("Change", nm_saveConfig)

	;--- roster -----------------------------------------------------------
	FleetGui.Add("ListView", "x16 y134 w330 h104 -Multi vFleetRosterList", ["Row", "Name", "Role", "User", "Owner"])
	FleetGui["FleetRosterList"].OnEvent("ItemSelect", ext_FleetRosterSelect)
	FleetGui.Add("Text", "x356 y136 w40", "Row:")
	FleetGui.Add("Edit", "x400 y134 w40 h18 Number vFleetEditRow")
	FleetGui.Add("Text", "x448 y136 w36", "Name:")
	FleetGui.Add("Edit", "x486 y134 w88 h18 vFleetEditName")
	FleetGui.Add("Text", "x356 y160 w40", "Role:")
	FleetGui.Add("DropDownList", "x400 y158 w80 vFleetEditRole", roster_Roles())
	FleetGui.Add("Text", "x488 y160 w36", "User:")
	FleetGui.Add("Edit", "x356 y182 w124 h18 vFleetEditUser")
	FleetGui.Add("CheckBox", "x488 y184 w86 vFleetEditOwner", "Owns server")
	FleetGui.Add("Button", "x356 y208 w70 h22", "Save row").OnEvent("Click", ext_FleetRosterSave)
	FleetGui.Add("Button", "x432 y208 w70 h22", "Remove").OnEvent("Click", ext_FleetRosterRemove)

	;--- the live picture -------------------------------------------------
	FleetGui.Add("Text", "x16 y268 w560 vFleetSummary", ext_fleetSummary())
	FleetGui.Add("ListView", "x16 y286 w550 h108 -Multi vFleetLive"
		, ["Row", "Name", "Role", "State", "Machine", "Field", "Server"])

	ext_FleetRosterDraw()
	ext_FleetRefresh()
	;the live half is only worth anything if it keeps up with the fleet
	SetTimer ext_FleetRefresh, 1000
	FleetGui.Show("w592 h412")
}

ext_FleetGUIClose(*) {
	global FleetGui

	SetTimer ext_FleetRefresh, 0
	if (IsSet(FleetGui) && IsObject(FleetGui))
		FleetGui.Destroy(), FleetGui := ""
}

;Redraw the roster list from the file we hold in memory.
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
}

;Clicking a row loads it into the editor beside the list.
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

;Save adds or overwrites - one button for both, since a row number the fleet has
;never seen is simply a new account.
ext_FleetRosterSave(*) {
	global FleetGui, FleetRoster, FleetRosterPath
	local row, other

	if (!(row := Integer(FleetGui["FleetEditRow"].Value)) || (row <= 0)) {
		MsgBox "Give the row a number. It is what a macro carries locally, and the only thing that ties it to this list.", "Fleet", 0x40030
		return
	}
	;only one account can own the private server, so setting the flag here
	;clears it everywhere else rather than leaving two and picking one silently
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

;The live half, once a second.
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

;A roster frame carries whatever the coordinator chose to send, so a missing
;field is normal rather than a fault.
ext_FleetCell(fields, name) {
	return fields.Has(name) ? fields[name] : ""
}

;The one line of fleet state that belongs on the main window, so the panel does
;not have to be open to notice the fleet has fallen over.
ext_fleetTabStatus() {
	global MainGui

	try MainGui["FleetStatusText"].Text := ext_fleetSummary()
}
