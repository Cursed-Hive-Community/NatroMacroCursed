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
;	AutoHotkey64.exe /script submacros\Fleet.ahk <port> <secret> <term>
;
;The term is what keeps two coordinators from fighting. Every takeover starts a
;higher one, it rides on every heartbeat, and a macro obeys only the highest it
;has seen. Without it, a coordinator that was merely slow - not dead - would
;come back and argue with its own replacement, and accounts would bounce between
;servers on contradictory orders.

#Include "%A_ScriptDir%\..\lib"
#Include "Socket.ahk"
#Include "FleetProtocol.ahk"
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

port := (A_Args.Length >= 1) ? Integer(A_Args[1]) : 47600
secret := (A_Args.Length >= 2) ? A_Args[2] : ""
term := (A_Args.Length >= 3) ? Integer(A_Args[3]) : 1

;row number -> what we know about that macro. The row is assigned by the panel
;and is the one thing a macro carries locally, so it is the identity here too.
peers := Map()
;socket -> row, for the reverse lookup a disconnect needs
bySocket := Map()

logPath := A_ScriptDir "\..\settings\fleet_log.txt"

fleet_Log("coordinator starting, port " port ", term " term)
if !(listener := sock_Listen(port, fleet_OnSocket)) {
	fleet_Log("could not listen on port " port " - is another coordinator already up?")
	ExitApp 1
}
fleet_Log("listening")
SetTimer fleet_Beat, FLEET_BEAT_SECS * 1000
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
		case "FIELD", "GUIDING", "CHARGE", "MONDO_IN", "STATE":
			fleet_OnReport(s, frame)
		case "ACK", "FAIL":
			fleet_Touch(s)
			fleet_Log("row " fleet_RowOf(s) " " frame.verb " id=" fleet_Field(frame, "id"))
		default:
			fleet_Log("unknown verb " frame.verb " from row " fleet_RowOf(s))
	}
}

;A macro announcing itself. The secret is checked here and nowhere else: a
;connection that never says HELLO is never in the roster, so it can do nothing.
fleet_OnHello(s, frame) {
	global peers, bySocket, secret, term
	local row, name, previous

	if (fleet_Field(frame, "secret") != secret) {
		fleet_Log("rejected a connection: wrong secret")
		sock_SendLine(s, fleet_Frame("BYE", Map("why", "bad secret")))
		sock_Close(s)
		return
	}
	row := Integer(fleet_Field(frame, "row", 0))
	if (row <= 0) {
		fleet_Log("rejected a connection: no row number")
		sock_SendLine(s, fleet_Frame("BYE", Map("why", "no row")))
		sock_Close(s)
		return
	}
	;a macro that restarts reconnects on a new socket while the old one may not
	;have closed yet, so the row takes the newer connection and the old one goes
	if (peers.Has(row) && (previous := peers[row].socket) && (previous != s)) {
		bySocket.Delete(previous)
		sock_Close(previous)
	}
	name := fleet_Field(frame, "name", "row " row)
	peers[row] := { row: row, name: name
		, role: fleet_Field(frame, "role", "unknown")
		, machine: fleet_Field(frame, "machine", "")
		, socket: s, state: "online", lastSeen: nowUnix()
		, field: "", server: "", guidingField: "", guidingUntil: 0, charge: 0 }
	bySocket[s] := row
	fleet_Log("row " row " (" name ") joined")
	;tell the newcomer who is in charge before anything else, so it knows which
	;term to obey, then bring everyone's picture up to date
	sock_SendLine(s, fleet_Frame("HEARTBEAT", Map("term", term, "at", nowUnix())))
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
	fleet_Log("row " row " (" peers[row].name ") left")
	fleet_Broadcast()
}

;Say we are alive, and write off anyone who has not.
fleet_Beat() {
	global peers, term
	local changed := 0, p

	for _, p in peers {
		if ((p.state = "online") && ((nowUnix() - p.lastSeen) > FLEET_QUIET_SECS)) {
			p.state := "stale"
			changed := 1
			fleet_Log("row " p.row " (" p.name ") went quiet")
		}
	}
	fleet_Send(fleet_Frame("HEARTBEAT", Map("term", term, "at", nowUnix())))
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
			, "machine", p.machine, "server", p.server, "field", p.field
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

;A plain text log beside the macro's own settings. Debugging a fleet by watching
;seven windows is hopeless; one file with timestamps is not.
fleet_Log(text) {
	global logPath

	try FileAppend FormatTime(A_Now, "HH:mm:ss") "  " text "`n", logPath, "UTF-8"
}
