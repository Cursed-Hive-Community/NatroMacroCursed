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
#Include "FleetServers.ahk"
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
;How long with nothing connected before this process gives up and goes.
;
;A coordinator is started by a macro and outlives it: the macro can be closed,
;or crash, and this process carries on holding the port and broadcasting to the
;network for as long as the machine is up. The macro ends the one it started,
;which covers the ordinary case - this covers the rest. Five minutes, because a
;macro reconnects within seconds of any interruption worth waiting out, and a
;coordinator nobody has spoken to for five minutes is a coordinator nobody
;wants.
FLEET_IDLE_SECS := 300

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
;A run given its own roster gets its own log beside it. A self-test reads the
;log back to see what the coordinator did, and it must be reading what this run
;did rather than the real fleet's history - nor scribbling on it. Same reason
;the roster is overridable in the first place.
if (A_Args.Length >= 5)
	logPath := RegExReplace(rosterPath, "i)\.ini$", ".log")
;who each row is meant to be. Kept in one file rather than configured on
;seven machines, and re-read when it changes so editing the panel does not
;mean restarting the coordinator.
roster := roster_Load(rosterPath)
;Which version of each configuration this coordinator serves, and the row that
;wrote it. The file's own timestamp cannot answer that - a replica is written
;when it arrives, so a machine holding a stale copy carries a newer timestamp
;than the machine holding the current one. Without a version, a macro that
;reconnected late and took over would serve its stale copy and every up-to-date
;macro would write it over their good one.
rosterVer := fleet_ConfigVersion(rosterPath)
;where the accounts sit, and who owns each of those places. Beside the roster
;rather than inside it: one flag on one row could not say that two servers have
;two different owners, and the owner is the only account whose /kick works.
serversPath := RegExReplace(rosterPath, "i)\.ini$", "_servers.ini")
servers := servers_Load(serversPath)
serversVer := fleet_ConfigVersion(serversPath)
;a configuration handed up by a macro, collected one frame per entry until the
;version it belongs to is whole - see fleet_OnSetRow
upRow := { version: -1, by: -1, want: 0, rows: Map() }
upServer := { version: -1, by: -1, want: 0, rows: Map() }
;Binding. The door is shut by default and opens for a couple of minutes when
;the host asks, which is the only moment a macro can be let in without
;already knowing the secret. A fleet left open is a fleet anything on the
;network can walk into, so it shuts itself.
bindUntil := 0
rosterStamp := fleet_RosterStamp()
;The server list travels with its own stamp as a generation number, which is
;what lets a deleted server disappear without a frame that means "delete".
;A macro that sees a generation it has not seen before throws its copy away
;and rebuilds from the frames that follow - so the list converges in one beat
;however it changed, and there is no half-applied update to end up in.
serversStamp := fleet_ServersStamp()
;Outstanding pings, by id. How far away a macro is cannot be read off the
;heartbeats - they say a macro is alive, not how long it takes to answer - so
;the round trip is asked for explicitly and timed in ticks. Unix seconds would
;report every hop on a local network as zero.
pingId := 0
pingAt := Map()
;the field the main last reported. Held here rather than in a static inside
;fleet_LeadField, because a resident that joins late - or comes back from a
;crash - has to be told where the hive is standing. Waiting for the main to
;change field means waiting for ever on a macro left on one field.
leadField := ""

;when a macro was last actually connected, for the idle timeout above
lastSeated := nowUnix()

fleet_Log("coordinator starting, port " port ", term " term ", row " hostRow)
;The port is the lock, and sock_Listen is asked to hold it exclusively - see
;the note there. Failing to take it means a coordinator is already up and this
;process has nothing to do but get out of the way, which is far better than
;listening alongside it and splitting the fleet in two.
;
;Retried for a few seconds first: a coordinator that was killed a moment ago
;can leave the port held briefly, and a handover that gives up on that is a
;handover that does not happen.
listener := 0
Loop 10 {
	if (listener := sock_Listen(port, fleet_OnSocket, 1))
		break
	Sleep 500
}
if !listener {
	fleet_Log("could not listen on port " port " - another coordinator already has it")
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
		case "LEAVE":
			fleet_OnLeave(s)
		case "SETROW":
			fleet_OnSetRow(s, frame)
		case "SETSERVER":
			fleet_OnSetServer(s, frame)
		case "FIELD", "GUIDING", "CHARGE", "MONDO_IN", "STATE":
			fleet_OnReport(s, frame)
		case "ACK", "FAIL":
			fleet_Touch(s)
			fleet_OnAck(s, frame)
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
	global peers, bySocket, secret, term, hostRow, roster, leadField
	local row, name, previous

	;final says whether the macro being turned away can do anything about it.
	;A wrong secret it cannot: nothing will change from knocking again. An
	;unknown row it might - a coordinator that has just taken over without a
	;configuration refuses everybody, and a macro that gave up permanently on
	;that would turn a failure which heals itself within a beat into a fleet
	;nobody can get back into.
	if (fleet_Field(frame, "secret") != secret) {
		fleet_Log("rejected a connection: wrong secret")
		sock_SendLine(s, fleet_Frame("BYE", Map("why", "bad secret", "final", 1)))
		sock_Close(s)
		return
	}
	row := Integer(fleet_Field(frame, "row", 0))
	if ((row <= 0) || !roster.Has(row)) {
		fleet_Log("rejected a connection: row " row " is not in the roster")
		sock_SendLine(s, fleet_Frame("BYE", Map("why", "unknown row", "final", 0)))
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
		, user: roster[row].user
		, machine: fleet_Field(frame, "machine", "")
		, socket: s, state: "online", lastSeen: nowUnix()
		, field: "", server: "", guidingField: "", guidingUntil: 0, charge: 0
		;-1 rather than 0: nothing has been measured yet, which is not the same
		;as a macro that answered instantly
		, rtt: -1, mondoIn: 0 }
	bySocket[s] := row
	fleet_Event("row " row " (" name ") joined")
	;tell the newcomer who is in charge before anything else, so it knows which
	;term to obey, then bring everyone's picture up to date
	sock_SendLine(s, fleet_Frame("HEARTBEAT", Map("term", term, "row", hostRow, "at", nowUnix())))
	fleet_Broadcast()
	;neither list is in fleet_Broadcast, which runs on every report a macro
	;makes. They change when somebody edits them, so they go out on a join and
	;on the beat and not five times a minute per macro.
	fleet_BroadcastRoster()
	fleet_BroadcastServers()
	;a resident arriving mid-session is told where the main is standing. Without
	;this it farms its own field until the main next changes, which on a macro
	;left on one field never happens - so a fuzzy that merely restarted would
	;spend the rest of the night out of position.
	fleet_FollowOne(peers[row])
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

;How many macros are connected right now.
;
;Not peers.Count: a row that has gone keeps its place in that table, marked
;offline, because the fleet is more useful knowing a macro is missing. So the
;count that answers "is anybody there" is the one with a socket behind it.
fleet_Seated() {
	global peers
	local p, n := 0

	for _, p in peers
		if p.socket
			n++
	return n
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

;A macro saying it is leaving on purpose. This is the opposite of fleet_OnClose
;above: a connection that drops leaves its row in place marked offline, because
;a macro that crashed is still part of the fleet and will be back, whereas a
;macro that was told to leave is not and its row goes - out of the roster file
;as well, so it does not reappear on the next reload.
fleet_OnLeave(s) {
	global roster, rosterPath, rosterStamp
	local row := fleet_RowOf(s)

	if !row
		return
	if roster.Has(row) {
		roster.Delete(row)
		fleet_BumpRoster()
	}
	;no BYE: it is the macro's own decision and it is not being refused
	fleet_Drop(row, "left the fleet", 0)
	fleet_Broadcast()
}

;Take a row out of the fleet altogether. GONE is the only frame that removes
;anything - every other change is carried by a ROSTER row whose state says what
;happened, which is why an offline macro needs no deletion and this does.
fleet_Drop(row, why, tell := 1) {
	global peers, bySocket
	local p

	if !peers.Has(row)
		return
	p := peers[row]
	if p.socket {
		;final: a row taken out of the roster by hand was meant to go, and
		;reconnecting would only be refused again
		if tell
			sock_SendLine(p.socket, fleet_Frame("BYE", Map("why", why, "final", 1)))
		bySocket.Delete(p.socket)
		sock_Close(p.socket)
	}
	peers.Delete(row)
	fleet_Event(p.name " " why)
	fleet_Send(fleet_Frame("GONE", Map("row", row)))
}

;An ACK that answers a ping is the only measurement of how far away a macro is.
;Any other ACK keeps the old behaviour of simply being noted - and a ping reply
;is deliberately not logged, since one per macro every five seconds would bury
;everything worth reading.
fleet_OnAck(s, frame) {
	global peers, pingAt
	local id := Integer(fleet_Field(frame, "id", 0)), waiting

	if (id && pingAt.Has(id)) {
		waiting := pingAt[id]
		pingAt.Delete(id)
		if peers.Has(waiting.row)
			peers[waiting.row].rtt := A_TickCount - waiting.tick
		return
	}
	fleet_Log("row " fleet_RowOf(s) " " frame.verb " id=" id)
}

;Ask every seated macro how long it takes to answer.
fleet_Ping() {
	global peers, pingId, pingAt
	local p, id, stale := []

	for _, p in peers {
		if ((p.state != "online") || !p.socket)
			continue
		pingAt[++pingId] := { row: p.row, tick: A_TickCount }
		sock_SendLine(p.socket, fleet_Frame("PING", Map("id", pingId)))
	}
	;a ping nobody answered would sit here for the life of the process
	for id, p in pingAt
		if ((A_TickCount - p.tick) > 60000)
			stale.Push(id)
	for _, id in stale
		pingAt.Delete(id)
}

;Say we are alive, and write off anyone who has not.
fleet_Beat() {
	global peers, term, hostRow, roster, rosterPath, rosterStamp
	global servers, serversPath, serversStamp, rosterVer, serversVer, lastSeated
	local p, stamp, fresh, ver

	;pick up an edited roster without a restart
	if ((stamp := fleet_RosterStamp()) != rosterStamp) {
		fresh := roster_Load(rosterPath)
		;A reload that comes back empty while macros are connected is a file
		;caught mid-write or briefly missing, not seven accounts deleted at
		;once. Believing it would strike the whole fleet off and send every
		;macro a BYE, which is a catastrophe produced by a benign race - so the
		;stamp is left untouched and the next beat reads it again.
		if (!fresh.Count && peers.Count)
			fleet_Log("ignored an empty roster reload - the file was unreadable")
		else {
			roster := fresh, rosterStamp := stamp
			;An edit by hand does not move the version, so the fleet would be
			;told the same version with different contents and would keep what
			;it already had. A version the editor bumped itself is adopted;
			;anything else is bumped here and written back, which is what makes
			;an edit from outside this process propagate at all.
			ver := fleet_ConfigVersion(rosterPath)
			if (ver.version > rosterVer.version)
				rosterVer := ver
			else
				fleet_BumpRoster()
			fleet_Event("roster reloaded, " roster.Count " rows, version "
				. rosterVer.version)
			fleet_ApplyRoster()
		}
	}
	for _, p in peers {
		if ((p.state = "online") && ((nowUnix() - p.lastSeen) > FLEET_QUIET_SECS)) {
			p.state := "stale"
			fleet_Event("row " p.row " (" p.name ") went quiet")
		}
	}
	;the servers, picked up the same way. No guard against an empty read is
	;needed here and none would mean anything: servers_Load answers a missing
	;or unreadable file with one unfilled main rather than with nothing.
	if ((stamp := fleet_ServersStamp()) != serversStamp) {
		servers := servers_Load(serversPath), serversStamp := stamp
		ver := fleet_ConfigVersion(serversPath)
		if (ver.version > serversVer.version)
			serversVer := ver
		else
			fleet_BumpServers()
		fleet_Event("servers reloaded, " servers.Count " of them, version "
			. serversVer.version)
	}
	;nobody connected for long enough that nobody wants us - see FLEET_IDLE_SECS
	if fleet_Seated()
		lastSeated := nowUnix()
	else if ((nowUnix() - lastSeated) > FLEET_IDLE_SECS) {
		fleet_Log("nothing has been connected for " FLEET_IDLE_SECS "s - exiting")
		ExitApp 0
	}
	fleet_Send(fleet_Frame("HEARTBEAT", Map("term", term, "row", hostRow, "at", nowUnix())))
	fleet_Ping()
	fleet_BroadcastRoster()
	fleet_BroadcastServers()
	;broadcast every beat, not only when something changed. The detail panel
	;shows values that go stale on their own - how long ago a macro was last
	;heard from, how long it took to answer - and a roster that only moves on
	;a change would leave them frozen at whatever they were when it last did.
	;It is one short line per row every five seconds.
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
			, "machine", p.machine, "user", p.user
		, "server", p.server, "field", p.field
			, "guiding", p.guidingField, "until", p.guidingUntil, "charge", p.charge
			;both are for the detail panel: how long this macro takes to answer,
			;and when it last said anything at all
			, "rtt", p.rtt, "seen", p.lastSeen)
		fleet_Send(fleet_Frame("ROSTER", f))
	}
}

;The roster as configured, one ROW frame per entry.
;
;Different from the ROSTER frames above, which say what a macro is doing right
;now - a row only gets one of those once it has connected at least once. This
;is the configuration: every account the fleet knows, running or not. It has to
;travel for two reasons. A row nobody has ever seen cannot otherwise be shown
;or edited anywhere but on this machine, and a macro cannot keep a replica of a
;configuration it is never sent.
;
;n says how many frames this generation has, so a reader knows when it holds
;all of them. Without it there is no moment at which a replica is safe to
;write, and half a roster written over a whole one loses accounts.
;
;An empty roster sends nothing at all, which is the right thing rather than an
;omission: a coordinator that has come up without a configuration must not be
;able to talk every macro into replacing a good replica with nothing.
fleet_BroadcastRoster() {
	global roster, rosterVer
	local r, e

	for r, e in roster
		fleet_Send(fleet_Frame("ROW", Map("v", rosterVer.version, "by", rosterVer.by
			, "n", roster.Count
			, "row", e.row, "name", e.name, "role", e.role
			, "user", e.user, "machine", e.machine)))
}

;The servers, one SERVER frame per slot, each carrying the generation the
;list is on. A macro keeps its copy only as long as the generation matches, so
;a server somebody deleted stops being drawn without any frame having to say
;it was deleted - the same trick the roster uses to avoid half-applied updates,
;applied to a list that can shrink.
fleet_BroadcastServers() {
	global servers, serversVer
	local s, e

	for s, e in servers
		fleet_Send(fleet_Frame("SERVER", Map("v", serversVer.version, "by", serversVer.by
			, "n", servers.Count
			, "slot", e.slot, "name", e.name, "link", e.link
			, "owner", e.owner, "kind", e.kind)))
}

;To every macro that is still connected.
fleet_Send(line) {
	global peers
	local p

	for _, p in peers
		if (p.socket)
			sock_SendLine(p.socket, line)
}

;Write the roster out as the next version, under our own name.
;
;One place, because a write that forgets to move the version is a write the
;fleet cannot see: every macro compares versions to decide whether what it has
;been sent is worth keeping, and an unchanged version reads as "nothing to do".
fleet_BumpRoster() {
	global roster, rosterPath, rosterStamp, rosterVer, hostRow

	rosterVer := { version: rosterVer.version + 1, by: hostRow }
	roster_Save(rosterPath, roster, rosterVer.version, rosterVer.by)
	;our own write would otherwise look like an outside edit and cost a
	;pointless reload on the next beat
	rosterStamp := fleet_RosterStamp()
	return 1
}
fleet_BumpServers() {
	global servers, serversPath, serversStamp, serversVer, hostRow

	serversVer := { version: serversVer.version + 1, by: hostRow }
	servers_Save(serversPath, servers, serversVer.version, serversVer.by)
	serversStamp := fleet_ServersStamp()
	return 1
}

;A macro handing a configuration up.
;
;It arrives when a macro holds a better one than this coordinator does, and
;that happens for an ordinary reason: a macro that was disconnected while the
;fleet was quiet can be the one that takes over, and it takes over with the
;copy it had. The fleet then has to climb back to the best copy anybody holds
;rather than settle for whichever macro happened to reconnect first.
;
;Collected per version, like everything that arrives one frame per entry, and
;taken only when whole and only when it beats what we have. That comparison is
;the whole of the authorisation: a configuration which is not strictly better
;is not taken, whoever sent it.
fleet_OnSetRow(s, frame) {
	global roster, rosterPath, rosterStamp, rosterVer, upRow
	local ver, want := fleet_Num(fleet_Field(frame, "n")), row

	;only from a macro that got past HELLO. The version comparison decides
	;whether a configuration is worth taking, but it says nothing about who is
	;entitled to offer one, and a connection that never proved it knew the
	;secret is not.
	if !fleet_RowOf(s)
		return 0
	ver := { version: fleet_Num(fleet_Field(frame, "v"))
		, by: fleet_Num(fleet_Field(frame, "by")) }
	if ((upRow.version != ver.version) || (upRow.by != ver.by))
		upRow := { version: ver.version, by: ver.by, want: want, rows: Map() }
	if (row := fleet_Num(fleet_Field(frame, "row")))
		upRow.rows[row] := { row: row
			, name: fleet_Field(frame, "name")
			, role: fleet_Field(frame, "role")
			, user: fleet_Field(frame, "user")
			, machine: fleet_Field(frame, "machine") }
	if (!upRow.want || (upRow.rows.Count != upRow.want))
		return 0
	if !fleet_ConfigBeats(ver, rosterVer) {
		fleet_KeepConflict(rosterPath, upRow.rows, ver, rosterVer, "roster")
		return 0
	}
	roster := upRow.rows, rosterVer := ver
	roster_Save(rosterPath, roster, ver.version, ver.by)
	rosterStamp := fleet_RosterStamp()
	fleet_Event("took the roster row " ver.by " handed up, version " ver.version
		. ", " roster.Count " rows")
	fleet_ApplyRoster()
	fleet_BroadcastRoster()
	return 1
}

fleet_OnSetServer(s, frame) {
	global servers, serversPath, serversStamp, serversVer, upServer
	local ver, want := fleet_Num(fleet_Field(frame, "n")), slot

	;a seated macro only - see fleet_OnSetRow
	if !fleet_RowOf(s)
		return 0
	ver := { version: fleet_Num(fleet_Field(frame, "v"))
		, by: fleet_Num(fleet_Field(frame, "by")) }
	if ((upServer.version != ver.version) || (upServer.by != ver.by))
		upServer := { version: ver.version, by: ver.by, want: want, rows: Map() }
	if (slot := fleet_Num(fleet_Field(frame, "slot")))
		upServer.rows[slot] := { slot: slot
			, name: fleet_Field(frame, "name")
			, link: fleet_Field(frame, "link")
			, owner: fleet_Num(fleet_Field(frame, "owner"))
			, kind: (fleet_Field(frame, "kind") = "main") ? "main" : "reserve" }
	if (!upServer.want || (upServer.rows.Count != upServer.want))
		return 0
	if !fleet_ConfigBeats(ver, serversVer) {
		fleet_KeepConflict(serversPath, upServer.rows, ver, serversVer, "servers")
		return 0
	}
	servers := servers_FixMain(upServer.rows), serversVer := ver
	servers_Save(serversPath, servers, ver.version, ver.by)
	serversStamp := fleet_ServersStamp()
	fleet_Event("took the servers row " ver.by " handed up, version " ver.version)
	fleet_BroadcastServers()
	return 1
}

;A configuration that lost is kept rather than dropped.
;
;Losing on version alone is ordinary and says nothing worth keeping. Losing a
;tie is not: equal versions written by different rows means both sides of a
;network split were edited separately, the rule that settles it is arbitrary,
;and the copy it discards is exactly the one somebody will want to look at. So
;that one is written beside the file it lost to, and said out loud.
fleet_KeepConflict(path, rows, lost, kept, what) {
	if (lost.version != kept.version) {
		fleet_Log("ignored a " what " handed up at version " lost.version
			. " - ours is " kept.version)
		return 0
	}
	if (what = "roster")
		roster_Save(path ".conflict", rows, lost.version, lost.by)
	else
		servers_Save(path ".conflict", rows, lost.version, lost.by)
	fleet_Event("two versions of the " what " at " lost.version ": kept row "
		. kept.by "'s, row " lost.by "'s is beside it in " what ".conflict")
	return 1
}

;The roster file as it stands, so a change can be noticed. Size and time
;together catch an edit that happens to keep the length the same.
;
;"none" rather than an empty string when the file is absent: the stamp rides on
;every broadcast as the generation number, and a generation has to be a value a
;macro can compare. The absence of a file is a state the roster can be in and
;come back from.
fleet_RosterStamp() {
	global rosterPath

	if !FileExist(rosterPath)
		return "none"
	return FileGetTime(rosterPath, "M") "/" FileGetSize(rosterPath)
}

;The server file as it stands. "none" rather than an empty string when there is
;no file: the generation has to be a value a macro can compare, and the absence
;of a file is a state the list can be in and come back from.
fleet_ServersStamp() {
	global serversPath

	if !FileExist(serversPath)
		return "none"
	return FileGetTime(serversPath, "M") "/" FileGetSize(serversPath)
}

;Carry an edited roster into the peers already connected, so a renamed or
;re-roled account does not have to reconnect for the change to be seen.
fleet_ApplyRoster() {
	global peers, roster
	local row, p, struck := []

	for row, p in peers {
		;struck off the roster by hand. Leaving the row on screen would suggest
		;its macro is still welcome, and it is not - the next HELLO is refused.
		;Collected rather than deleted here, because dropping a row mid-loop
		;mutates the map being walked.
		if !roster.Has(row) {
			struck.Push(row)
			continue
		}
		p.name := roster[row].name, p.role := roster[row].role
		p.user := roster[row].user
		;re-roled by hand into a resident, so it is owed the field the hive is
		;on - the same reason a resident gets one when it joins
		fleet_FollowOne(p)
	}
	for _, row in struck
		fleet_Drop(row, "was removed from the roster")
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
	;secs<=0 is the host shutting the door early rather than waiting it out -
	;the toggle on its own button sends this
	if (secs <= 0) {
		bindUntil := 0
		fleet_Event("stopped accepting new macros")
		return
	}
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
	local row, again

	if (nowUnix() > bindUntil) {
		fleet_Log("refused a bind: the door is shut")
		sock_SendLine(s, fleet_Frame("BYE", Map("why", "this fleet is not accepting new macros")))
		return
	}
	again := (row := fleet_RowFor(frame)) ? 1 : 0
	if !again
		row := fleet_NextRow()
	roster[row] := { row: row
		, name: fleet_Field(frame, "name", "row " row)
		, role: fleet_Field(frame, "role", "guid")
		, user: fleet_Field(frame, "user", "")
		, machine: fleet_Field(frame, "machine", "") }
	fleet_BumpRoster()
	fleet_Event((again ? "rebound " : "bound ") roster[row].name
		. " (" roster[row].role ") from "
		. fleet_Field(frame, "machine", "somewhere"))
	sock_SendLine(s, fleet_Frame("BOUND", Map("row", row, "secret", secret)))
}

;The row this account already has, or 0.
;
;A second setup of the same macro - after a settings reset, a reinstall, a move
;to another machine - should land back on its own row. Minting a new one leaves
;the old listed offline for ever, and an offline row is a row somebody goes
;looking for a reason behind.
;
;The Roblox username is the identity when it is set: one account is one row,
;and the account is what the whole fleet makes decisions about. Without one
;there is only the machine and the label, which together are as close as this
;gets - two macros on one machine have to be given different names anyway, or
;nothing in the fleet view can tell them apart either.
fleet_RowFor(frame) {
	global roster
	local user := fleet_Field(frame, "user"), machine := fleet_Field(frame, "machine")
	local name := fleet_Field(frame, "name"), r, e

	if (user != "")
		for r, e in roster
			if (e.user = user)
				return r
	if ((machine = "") || (name = ""))
		return 0
	for r, e in roster
		if ((e.machine = machine) && (e.name = name))
			return r
	return 0
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

;Point the followers at the field the main is farming - fuzzy and tad, and
;only those, which is what roster_Follows says. They improve the field they
;stand in, so they go where the main goes - but only
;to farm, which is all a FIELD report ever means. Forwarded once per change:
;the main re-enters nm_GoGather every trip, and moving the whole hive on an
;unchanged field would be pure churn.
fleet_LeadField(field) {
	global peers, leadField
	local p, sent := 0

	if (field = leadField)
		return 0
	leadField := field
	for _, p in peers
		sent += fleet_FollowOne(p)
	if sent
		fleet_Event("main farming " field " - " sent " fuzzy/tad following")
	return sent
}

;Send one macro where the hive is standing, if it is a macro that follows at
;all. Every GOTO goes through here, so "who follows" is written down once.
fleet_FollowOne(p) {
	global leadField

	if ((leadField = "") || !p.socket || (p.state != "online"))
		return 0
	if !roster_Follows(p.role)
		return 0
	return sock_SendLine(p.socket, fleet_Frame("GOTO", Map("field", leadField))) ? 1 : 0
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
;
;Capped, because the thing that writes to it fastest is a fault: a coordinator
;that cannot reach a macro logs a line every few seconds all night. Half a
;megabyte is further back than anyone reads, and the previous half stays beside
;it under .1. The size is only looked at every so often - a stat per line would
;cost more than the lines do.
fleet_Log(text) {
	global logPath
	static cap := 524288, written := 0

	if (Mod(++written, 200) = 0) {
		try {
			if (FileGetSize(logPath) > cap) {
				try FileDelete logPath ".1"
				FileMove logPath, logPath ".1", 1
			}
		}
	}
	try FileAppend FormatTime(A_Now, "HH:mm:ss") "  " text "`n", logPath, "UTF-8"
}
