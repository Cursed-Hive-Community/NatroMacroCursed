#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon

;The Fleet coordinator.
;
;It holds the roster and, later, the queues. It runs as its own process rather
;than inside a macro because a macro that is farming is blocked for minutes at a
;time - a walk, a ten minute balloon convert, an attack loop - and a coordinator
;living there would answer only between chores, which is exactly when it is
;least needed.
;
;Launched by whichever macro the panel names as host:
;
;	AutoHotkey64.exe /script submacros\Fleet.ahk <port> <secret> <term> <row> [roster]
;
;The term is what keeps two coordinators from fighting. Every takeover starts a
;higher one, it rides on every heartbeat, and a macro obeys only the highest it
;has seen. Without it, a coordinator that was merely slow - not dead - would
;come back and argue with its own replacement, and accounts would bounce between
;servers on contradictory orders.

#Include "%A_ScriptDir%\..\lib"
#Include "Socket.ahk"
#Include "FleetProtocol.ahk"
#Include "FleetRoster.ahk"
#Include "nowUnix.ahk"

;How often the coordinator says it is alive, and how long a silent macro has
;before it is written off. The macro side's own grace period is longer than
;this on purpose: it should take more than one missed beat to trigger a relief.
;
;The names end in _SECS for a reason. AutoHotkey identifiers are case
;insensitive, so a constant named FLEET_BEAT would be the very same name as
;the function fleet_Beat below, and assigning to it overwrites the function.
FLEET_BEAT_SECS := 5
FLEET_QUIET_SECS := 30
;the beacon goes out more often than the heartbeat, because it is what a
;macro starting up waits on before it can do anything at all
FLEET_BEACON_SECS := 2

port := (A_Args.Length >= 1) ? Integer(A_Args[1]) : 47600
secret := (A_Args.Length >= 2) ? A_Args[2] : ""
term := (A_Args.Length >= 3) ? Integer(A_Args[3]) : 1
;the row that started us. It rides on every heartbeat so the macro the panel
;named as host can tell whether it is being stood in for, and take its job back.
hostRow := (A_Args.Length >= 4) ? Integer(A_Args[4]) : 0

;row number -> what we know about that macro. The row is assigned by the panel
;and is the one thing a macro carries locally, so it is the identity here too.
peers := Map()
;socket -> row, for the reverse lookup a disconnect needs
bySocket := Map()

logPath := A_ScriptDir "\..\settings\fleet_log.txt"
;the roster file, overridable so a self-test can bring its own and never
;disturb the real one
rosterPath := (A_Args.Length >= 5) ? A_Args[5]
	: A_ScriptDir "\..\settings\fleet_roster.ini"
;who each row is meant to be. Kept in one file rather than configured on
;seven machines, and re-read when it changes so editing the panel does not
;mean restarting the coordinator.
roster := roster_Load(rosterPath)
;Binding. The door is shut by default and opens for a couple of minutes when
;the host asks, which is the only moment a macro can be let in without
;already knowing the secret. A fleet left open is a fleet anything on the
;network can walk into, so it shuts itself.
bindUntil := 0
rosterStamp := fleet_RosterStamp()

fleet_Log("coordinator starting, port " port ", term " term ", row " hostRow)
if !(listener := sock_Listen(port, fleet_OnSocket)) {
	fleet_Log("could not listen on port " port " - is another coordinator already up?")
	ExitApp 1
}
fleet_Log("listening")

;The beacon. A macro that had to be told an address would be wrong the moment
;the router hands out a new lease, so instead we shout where we are onto the
;local network and let the macros come to us. Bound to port zero - an
;ephemeral one - so it never competes with the macros for the listening port.
beacon := sock_UdpListen(0, (*) => 0)
if !beacon
	fleet_Log("no UDP socket - macros will have to be given an address by hand")

SetTimer fleet_Beat, FLEET_BEAT_SECS * 1000
SetTimer fleet_Beacon, FLEET_BEACON_SECS * 1000
fleet_Beacon()
return

;Everything the socket layer has to say about every connection.
fleet_OnSocket(s, event, data) {
	global bySocket

	if (event = "line")
		fleet_OnLine(s, data)
	else if (event = "close")
		fleet_OnClose(s)
}

;One frame from one macro.
fleet_OnLine(s, line) {
	local frame := fleet_Parse(line)

	if !frame {
		fleet_Log("unparseable frame: " line)
		return
	}
	switch frame.verb {
		case "HELLO":
			fleet_OnHello(s, frame)
		case "HEARTBEAT":
			fleet_Touch(s)
		case "OPEN":
			fleet_OnOpen(s, frame)
		case "BIND":
			fleet_OnBind(s, frame)
		case "FIELD", "GUIDING", "CHARGE", "MONDO_IN", "STATE":
			fleet_OnReport(s, frame)
		case "ACK", "FAIL":
			fleet_Touch(s)
			fleet_Log("row " fleet_RowOf(s) " " frame.verb " id=" fleet_Field(frame, "id"))
		default:
			fleet_Log("unknown verb " frame.verb " from row " fleet_RowOf(s))
	}
}

;A macro announcing itself. Two things are checked, and nowhere else: the
;secret, and that the row it claims actually exists in the roster. A
;connection that never gets past this is in no table and can do nothing.
;
;What the macro says about itself beyond its row number is ignored. Name and
;role come from the roster file, so the fleet cannot end up with two versions
;of who row 2 is depending on which machine was edited last.
fleet_OnHello(s, frame) {
	global peers, bySocket, secret, term, hostRow, roster
	local row, name, previous

	if (fleet_Field(frame, "secret") != secret) {
		fleet_Log("rejected a connection: wrong secret")
		sock_SendLine(s, fleet_Frame("BYE", Map("why", "bad secret")))
		sock_Close(s)
		return
	}
	row := Integer(fleet_Field(frame, "row", 0))
	if ((row <= 0) || !roster.Has(row)) {
		fleet_Log("rejected a connection: row " row " is not in the roster")
		sock_SendLine(s, fleet_Frame("BYE", Map("why", "unknown row")))
		sock_Close(s)
		return
	}
	;a macro that restarts reconnects on a new socket while the old one may not
	;have closed yet, so the row takes the newer connection and the old one goes
	if (peers.Has(row) && (previous := peers[row].socket) && (previous != s)) {
		bySocket.Delete(previous)
		sock_Close(previous)
	}
	name := roster[row].name
	peers[row] := { row: row, name: name
		, role: roster[row].role
		, user: roster[row].user, owner: roster[row].owner
		, machine: fleet_Field(frame, "machine", "")
		, socket: s, state: "online", lastSeen: nowUnix()
		, field: "", server: "", guidingField: "", guidingUntil: 0, charge: 0 }
	bySocket[s] := row
	fleet_Event("row " row " (" name ") joined")
	;tell the newcomer who is in charge before anything else, so it knows which
	;term to obey, then bring everyone's picture up to date
	sock_SendLine(s, fleet_Frame("HEARTBEAT", Map("term", term, "row", hostRow, "at", nowUnix())))
	fleet_Broadcast()
}

;FIELD, GUIDING, CHARGE, MONDO_IN - a macro telling the fleet what it sees.
;Every one of them also counts as a sign of life.
fleet_OnReport(s, frame) {
	global peers
	local row := fleet_RowOf(s), p

	if !row
		return
	p := peers[row], p.lastSeen := nowUnix()
	switch frame.verb {
		case "FIELD":
			p.field := fleet_Field(frame, "name")
			;the main's field is the one the residents follow. It arrives from
			;nm_GoGather, the farm path - a planter or booster trip is a
			;different function and never reports a field, so a resident never
			;chases the main anywhere but to farm.
			if ((p.role = "main") && (p.field != ""))
				fleet_LeadField(p.field)
		case "GUIDING":
			p.guidingField := fleet_Field(frame, "field")
			p.guidingUntil := Integer(fleet_Field(frame, "until", 0))
		case "CHARGE":
			p.charge := Integer(fleet_Field(frame, "tokens", 0))
		case "MONDO_IN":
			p.mondoIn := Integer(fleet_Field(frame, "secs", 0))
		case "STATE":
			p.server := fleet_Field(frame, "server")
	}
	fleet_Broadcast()
}

fleet_Touch(s) {
	global peers
	local row := fleet_RowOf(s)

	if row
		peers[row].lastSeen := nowUnix()
}

fleet_RowOf(s) {
	global bySocket
	return bySocket.Has(s) ? bySocket[s] : 0
}

;A connection went away. The row stays in the roster, marked offline - the fleet
;is more useful knowing a macro is missing than pretending it never existed.
fleet_OnClose(s) {
	global peers, bySocket
	local row := fleet_RowOf(s)

	if !row
		return
	peers[row].state := "offline", peers[row].socket := 0
	bySocket.Delete(s)
	fleet_Event("row " row " (" peers[row].name ") left")
	fleet_Broadcast()
}

;Say we are alive, and write off anyone who has not.
fleet_Beat() {
	global peers, term, hostRow, roster, rosterPath, rosterStamp
	local changed := 0, p, stamp

	;pick up an edited roster without a restart
	if ((stamp := fleet_RosterStamp()) != rosterStamp) {
		roster := roster_Load(rosterPath), rosterStamp := stamp
		fleet_Event("roster reloaded, " roster.Count " rows")
		fleet_ApplyRoster()
		changed := 1
	}
	for _, p in peers {
		if ((p.state = "online") && ((nowUnix() - p.lastSeen) > FLEET_QUIET_SECS)) {
			p.state := "stale"
			changed := 1
			fleet_Event("row " p.row " (" p.name ") went quiet")
		}
	}
	fleet_Send(fleet_Frame("HEARTBEAT", Map("term", term, "row", hostRow, "at", nowUnix())))
	if changed
		fleet_Broadcast()
}

;The roster, as one ROSTER frame per row. Sending each row on its own line means
;the picture converges without anyone having to reassemble a payload, and a row
;that has gone offline is simply a row whose state says so - there is nothing to
;delete and no way to end up with a half-applied update.
fleet_Broadcast() {
	global peers
	local p, f

	for _, p in peers {
		f := Map("row", p.row, "name", p.name, "role", p.role, "state", p.state
			, "machine", p.machine, "user", p.user, "owner", p.owner
		, "server", p.server, "field", p.field
			, "guiding", p.guidingField, "until", p.guidingUntil, "charge", p.charge)
		fleet_Send(fleet_Frame("ROSTER", f))
	}
}

;To every macro that is still connected.
fleet_Send(line) {
	global peers
	local p

	for _, p in peers
		if (p.socket)
			sock_SendLine(p.socket, line)
}

;The roster file as it stands, so a change can be noticed. Size and time
;together catch an edit that happens to keep the length the same.
fleet_RosterStamp() {
	global rosterPath

	if !FileExist(rosterPath)
		return ""
	return FileGetTime(rosterPath, "M") "/" FileGetSize(rosterPath)
}

;Carry an edited roster into the peers already connected, so a renamed or
;re-roled account does not have to reconnect for the change to be seen.
fleet_ApplyRoster() {
	global peers, roster
	local row, p

	for row, p in peers {
		if !roster.Has(row)
			continue
		p.name := roster[row].name, p.role := roster[row].role
		p.user := roster[row].user, p.owner := roster[row].owner
	}
}

;Shout where we are. The fingerprint says which fleet this is without putting
;the secret on the wire; the port says where to knock. 255.255.255.255 reaches
;every machine on this subnet, which is as far as a fleet ever spans.
fleet_Beacon() {
	global beacon, port, term, hostRow, secret, bindUntil, roster

	if !beacon
		return 0
	return sock_UdpSend(beacon, "255.255.255.255", port + 1
		, fleet_Frame("FLEET", Map("port", port, "term", term, "row", hostRow
			, "id", fleet_Fingerprint(secret)
			, "open", (nowUnix() < bindUntil) ? 1 : 0
			, "host", A_ComputerName, "size", roster.Count)))
}

;Open the door. Only the host may ask, and never for longer than five
;minutes - the point of a window is that it closes.
fleet_OnOpen(s, frame) {
	global bindUntil, hostRow
	local row := fleet_RowOf(s), secs := Integer(fleet_Field(frame, "secs", 120))

	if (!row || (hostRow && (row != hostRow)))
		return
	bindUntil := nowUnix() + Min(Max(secs, 10), 300)
	fleet_Event("accepting new macros for " (bindUntil - nowUnix()) " seconds")
}

;A macro asking to be let in. This is the one frame that arrives without a
;secret, because handing the secret over is what binding is for.
;
;The row number is assigned here and sent back. Nobody invents one, nobody
;has to remember which machine is which - the macro stores what it is told
;and uses it for every reconnection afterwards.
fleet_OnBind(s, frame) {
	global roster, rosterPath, rosterStamp, bindUntil, secret
	local row

	if (nowUnix() > bindUntil) {
		fleet_Log("refused a bind: the door is shut")
		sock_SendLine(s, fleet_Frame("BYE", Map("why", "this fleet is not accepting new macros")))
		return
	}
	row := fleet_NextRow()
	roster[row] := { row: row
		, name: fleet_Field(frame, "name", "row " row)
		, role: fleet_Field(frame, "role", "guid")
		, user: fleet_Field(frame, "user", "")
		, owner: 0 }
	roster_Save(rosterPath, roster)
	rosterStamp := fleet_RosterStamp()
	fleet_Event("bound " roster[row].name " (" roster[row].role ") from "
		. fleet_Field(frame, "machine", "somewhere"))
	sock_SendLine(s, fleet_Frame("BOUND", Map("row", row, "secret", secret)))
}

;The next free row. Rows are never reused: a number that once meant one
;account should not quietly come to mean another.
fleet_NextRow() {
	global roster
	local r, best := 0

	for r, _ in roster
		if (r > best)
			best := r
	return best + 1
}

;Point the residents at the field the main is farming. Fuzzy and tad alts
;improve the field they stand in, so they go where the main goes - but only
;to farm, which is all a FIELD report ever means. Forwarded once per change:
;the main re-enters nm_GoGather every trip, and moving the whole hive on an
;unchanged field would be pure churn.
fleet_LeadField(field) {
	global peers
	static last := ""
	local p, sent := 0

	if (field = last)
		return 0
	last := field
	for _, p in peers
		if (p.socket && (p.state = "online") && ((p.role = "fuzzy") || (p.role = "tad"))) {
			sock_SendLine(p.socket, fleet_Frame("GOTO", Map("field", field)))
			sent++
		}
	if sent
		fleet_Event("main farming " field " - " sent " resident(s) following")
	return sent
}

;Something worth a line in everybody's view, not only in the log file here.
;The macros keep their own copy, so the panel can show what the fleet has
;been doing without reading a file off somebody else's machine.
fleet_Event(text) {
	fleet_Log(text)
	fleet_Send(fleet_Frame("EVENT", Map("at", nowUnix(), "text", text)))
}

;A plain text log beside the macro's own settings. Debugging a fleet by watching
;seven windows is hopeless; one file with timestamps is not.
fleet_Log(text) {
	global logPath

	try FileAppend FormatTime(A_Now, "HH:mm:ss") "  " text "`n", logPath, "UTF-8"
}
