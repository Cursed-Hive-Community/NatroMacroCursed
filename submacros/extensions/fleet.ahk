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
;Which configuration the fleet is on, and whether this macro agrees.
;
;The version is the thing the whole design rests on and it was visible nowhere,
;which left the one failure it exists to prevent impossible to diagnose from
;the screen. Said plainly when they agree, and said loudly when they do not.
ext_fleetConfigLine() {
	global ext_fleetRosterVer, ext_fleetRosterDisk

	if (ext_fleetRosterVer.version <= 0)
		return "no configuration yet"
	if ((ext_fleetRosterVer.version = ext_fleetRosterDisk.version)
		&& (ext_fleetRosterVer.by = ext_fleetRosterDisk.by))
		return "config v" ext_fleetRosterVer.version
	if fleet_ConfigBeats(ext_fleetRosterDisk, ext_fleetRosterVer)
		return "config v" ext_fleetRosterVer.version
			. " - THIS MACRO HOLDS v" ext_fleetRosterDisk.version ", handing it up"
	return "config v" ext_fleetRosterVer.version " by row " ext_fleetRosterVer.by
		. " - this macro holds v" ext_fleetRosterDisk.version
		. " by row " ext_fleetRosterDisk.by

}

;Who is running the fleet, in words, or "" while nobody has said.
;
;The coordinator reports the row that started it on every heartbeat, and that
;row is also the one whose settings folder it is reading out of - a coordinator
;is launched by a macro, in that macro's working directory. So this names the
;account and the machine the fleet's configuration actually lives on, which is
;what somebody needs when they go looking for where to change something.
ext_fleetCoordWho() {
	global ext_fleetCoordRow, ext_fleetPeers, FleetRow
	local p, who, where

	if !ext_fleetCoordRow
		return ""
	if (ext_fleetCoordRow = FleetRow)
		return "this macro"
	if !ext_fleetPeers.Has(ext_fleetCoordRow)
		return "row " ext_fleetCoordRow
	p := ext_fleetPeers[ext_fleetCoordRow]
	who := ext_FleetSeatName(p), where := ext_FleetCell(p, "machine")
	return (where != "") ? who " on " where : who
}

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
	global ext_fleetBoundWith

	if (row <= 0)
		return 0
	;On a timer, for the same reason as the replica. This runs inside the socket
	;callback for the binding connection, and what it has to do is write four
	;settings to disk and then close that very socket and restart the fleet -
	;none of which belongs inside a dispatch holding Critical, and none of which
	;wants to happen while the frame that triggered it is still in flight.
	ext_fleetBoundWith := { row: row, secret: newSecret }
	SetTimer ext_fleetFinishBind, -50
	return 1
}

ext_fleetFinishBind() {
	global ext_fleetBoundWith, ext_fleetBindSock, ext_fleetBindResult

	if !IsObject(ext_fleetBoundWith)
		return 0
	ext_FleetSave("FleetRow", ext_fleetBoundWith.row)
	ext_FleetSave("FleetHostRow", 0)
	if (ext_fleetBoundWith.secret != "")
		ext_FleetSave("FleetSecret", ext_fleetBoundWith.secret)
	ext_FleetSave("FleetCheck", 1)
	ext_fleetBoundWith := ""
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
	local path := ext_fleetRosterFile(), rows

	rows := roster_Load(path)
	rows[1] := { row: 1, name: name, role: role, user: user
		, machine: A_ComputerName }
	;version one, written by row one: a fleet being created has no history to
	;compare against and this is the first thing anybody will compare to
	roster_Save(path, rows, 1, 1)
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
		ext_fleetLostCoord()
		ext_fleetRetryLater()
	}
}

;The coordinator's connection has gone, so stop counting its row as alive.
;
;This is the whole of why failover never fired. The broadcast that said the
;coordinator was "online" is the last thing it ever said, and nothing cleared
;it - so every survivor kept electing the dead row as the successor, found that
;it was not itself, and waited. Nobody ever took over, and the fleet sat
;retrying for ever.
;
;We have better evidence than that broadcast: we were talking to it a moment
;ago and now we are not. Recorded against our own copy only, which is all a
;macro can honestly claim.
ext_fleetLostCoord() {
	global ext_fleetPeers, ext_fleetCoordRow

	if (ext_fleetCoordRow && ext_fleetPeers.Has(ext_fleetCoordRow))
		ext_fleetPeers[ext_fleetCoordRow]["state"] := "offline"
	return 1
}

;Announce ourselves. Only the row number and the secret matter: who row 2 is
;belongs to the roster file, not to whatever this macro believes about itself.
ext_fleetHello() {
	global ext_fleetSock, ext_fleetPeers, FleetRow, FleetSecret, ext_fleetMyField
	global ext_fleetServers, ext_fleetServerVer, ext_fleetRoster, ext_fleetRosterVer
	global ext_fleetHandedUp

	;Forget the old picture before asking for a new one. The coordinator answers
	;a HELLO with the whole roster, and rows are merged by number rather than
	;replaced wholesale - so anything that left while this macro was away would
	;otherwise sit in the table for ever, still wearing the state and the colour
	;it had at the moment the connection dropped.
	ext_fleetPeers.Clear()
	;the servers too, and their generation with them - a coordinator we have not
	;met may be reading a different file, and an empty generation guarantees the
	;first SERVER frame rebuilds rather than merges
	ext_fleetServers.Clear(), ext_fleetServerVer := { version: -1, by: -1 }
	ext_fleetRoster.Clear(), ext_fleetRosterVer := { version: -1, by: -1 }
	ext_fleetHandedUp := ""
	;and the field we last said we were farming. A coordinator we are meeting
	;for the first time - or one that has just been started by a takeover - has
	;no record of it, so the next gather trip has to say so again instead of
	;finding our own note that nothing has changed and staying quiet.
	ext_fleetMyField := ""
	sock_SendLine(ext_fleetSock, fleet_Frame("HELLO", Map("row", FleetRow
		, "secret", FleetSecret, "machine", A_ComputerName)))
}

;A frame from the coordinator.
ext_fleetOnLine(line) {
	global ext_fleetPeers, ext_fleetTerm, ext_fleetCoordRow, ext_fleetCoordSeen
	global ext_fleetEvents, ext_fleetFollowField, ext_fleetSock, ext_fleetRefused
	global ext_fleetServers, ext_fleetServerVer, ext_fleetServerWant
	global ext_fleetRoster, ext_fleetRosterVer, ext_fleetRosterWant
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
		case "PING":
			;answered first and with nothing else done: the coordinator is
			;timing the round trip, so any work here would be measured as
			;distance to this machine
			sock_SendLine(ext_fleetSock, fleet_Frame("ACK", Map("id", fleet_Field(frame, "id"))))
			ext_fleetCoordSeen := nowUnix()
		case "SERVER":
			;One version of the list at a time. A version this macro has not
			;seen means the list changed somehow - an edit, a deletion, a
			;different coordinator - and the only safe answer is to drop what we
			;have and take the frames that follow. What the coordinator is
			;serving is followed in memory whether or not it is the best copy
			;anybody holds, because the panel should show what the fleet is
			;actually running on; whether it reaches the disk is a separate
			;question, answered in ext_fleetReplicate.
			if (!ext_fleetSameVer(ext_fleetServerVer, frame)) {
				ext_fleetServers.Clear()
				ext_fleetServerVer := ext_fleetFrameVer(frame)
				ext_fleetServerWant := fleet_Num(fleet_Field(frame, "n"))
			}
			if (row := fleet_Num(fleet_Field(frame, "slot")))
				ext_fleetServers[row] := frame.fields
			ext_fleetReplicate()
			ext_fleetCoordSeen := nowUnix()
		case "ROW":
			;the roster as configured, which is not the same as the roster as it
			;is behaving - ROSTER above only describes accounts that have
			;connected at least once. Collected exactly like the servers, and
			;for the extra reason that this is what a macro taking over needs.
			if (!ext_fleetSameVer(ext_fleetRosterVer, frame)) {
				ext_fleetRoster.Clear()
				ext_fleetRosterVer := ext_fleetFrameVer(frame)
				ext_fleetRosterWant := fleet_Num(fleet_Field(frame, "n"))
			}
			if (row := fleet_Num(fleet_Field(frame, "row")))
				ext_fleetRoster[row] := frame.fields
			ext_fleetReplicate()
			ext_fleetCoordSeen := nowUnix()
		case "GONE":
			;the one frame that removes an account. Everything else is a ROSTER
			;row whose state says what happened, so this is how a macro that
			;left for good stops being drawn.
			row := Integer(fleet_Field(frame, "row", 0))
			if (row && ext_fleetPeers.Has(row))
				ext_fleetPeers.Delete(row)
			ext_fleetCoordSeen := nowUnix()
		case "GOTO":
			;the main is farming this field and we are a resident. Store it;
			;travelling there and gathering is the gather loop's job, added next.
			ext_fleetFollowField := fleet_Field(frame, "field")
			ext_fleetCoordSeen := nowUnix()
		case "BYE":
			;Two kinds of refusal, and treating them alike was a mistake worth
			;not repeating. A wrong secret, or an account deliberately taken out
			;of the fleet, is final: knocking again is refused every time, all
			;night, and the fleet is let go here so the macro carries on farming
			;alone - which is the rule this whole file is written to. An unknown
			;row is not final. A coordinator that has just taken over without a
			;configuration refuses everybody, and giving up on that permanently
			;turns a failure that heals itself within a beat into a fleet nobody
			;can get back into. The coordinator says which it is.
			;
			;The reason is kept for the panel rather than put in the status
			;line: being turned away by the fleet says nothing about what this
			;macro itself is doing.
			ext_fleetEvents.InsertAt(1, FormatTime(A_Now, "HH:mm:ss")
				. "  the fleet turned this macro away: "
				. fleet_Field(frame, "why", "refused"))
			while (ext_fleetEvents.Length > 80)
				ext_fleetEvents.Pop()
			;absent means final, so an older coordinator behaves as it used to
			if (Integer(fleet_Field(frame, "final", 1))) {
				ext_fleetRefused := fleet_Field(frame, "why", "refused")
				ext_fleetStop()
			}
	}
}

;Keep a copy of the fleet's configuration on this machine.
;
;This is the answer to the hole in a coordinator that reads its configuration
;out of its own settings folder: if that machine is the only one holding the
;files, losing it loses the fleet, and no amount of electing a replacement
;helps - the replacement comes up with nothing and refuses everybody. There is
;no master copy. There is one on every machine, and whichever macro coordinates
;serves its own.
;
;Written only when a generation is whole. The frames of a generation arrive one
;per entry with nothing marking the last, so each says how many there are;
;saving half a roster over a whole one loses accounts, and on the machine that
;coordinates it would be read straight back as a deletion.
;
;And never on the machine that coordinates. Its files are the originals, not
;copies - writing them would move their timestamp, which it reads as an edit,
;which it broadcasts as a new generation, which every macro writes again.
;Arm the write. Called from the socket dispatch, which holds Critical, where
;reading and writing files would stall every timer in the macro behind a disk -
;and this macro is also sending keystrokes to a game. A one-shot timer runs the
;work as its own thread a moment later, outside the dispatch. Re-arming simply
;moves the moment, so a burst of frames still produces one write.
ext_fleetReplicate() {
	SetTimer ext_fleetReplicaFlush, -50
	return 1
}

ext_fleetReplicaFlush() {
	global ext_fleetRoster, ext_fleetRosterVer, ext_fleetRosterWant, ext_fleetRosterDisk
	global ext_fleetServers, ext_fleetServerVer, ext_fleetServerWant, ext_fleetServerDisk
	static wasHost := -1

	;While this macro is the one hosting, its files are written by the
	;coordinator process rather than from here - every bind, every leave - so
	;the versions remembered below go stale without anything noticing. Left
	;that way, the first configuration to arrive after this macro stopped
	;coordinating would be compared against a version from before everything
	;its own coordinator had written, and a stale copy from elsewhere could
	;beat it. Which is the exact failure the version exists to prevent, so it
	;would be a poor place to leave one.
	;
	;Re-read on any change of role, which costs two reads of a few hundred
	;bytes and happens about as often as a coordinator changes hands.
	if (ext_fleetServerHost() != wasHost) {
		wasHost := ext_fleetServerHost()
		ext_fleetRosterDisk := fleet_ConfigVersion(ext_fleetRosterFile())
		ext_fleetServerDisk := fleet_ConfigVersion(ext_fleetServersFile())
	}
	if ext_fleetServerHost()
		return 0
	if ext_fleetReplicaWhole(ext_fleetRoster, ext_fleetRosterVer, ext_fleetRosterWant) {
		if fleet_ConfigBeats(ext_fleetRosterVer, ext_fleetRosterDisk) {
			if roster_Save(ext_fleetRosterFile(), ext_fleetRosterRows()
				, ext_fleetRosterVer.version, ext_fleetRosterVer.by)
				ext_fleetRosterDisk := ext_fleetRosterVer
			else
				ext_fleetProblem("could not write the roster replica to "
					. ext_fleetRosterFile()
					. " - this macro cannot stand in as coordinator")
		}
		else {
			ext_fleetSayDivergent("roster", ext_fleetRosterVer, ext_fleetRosterDisk)
			ext_fleetHandUp("roster")
		}
	}
	if ext_fleetReplicaWhole(ext_fleetServers, ext_fleetServerVer, ext_fleetServerWant) {
		if fleet_ConfigBeats(ext_fleetServerVer, ext_fleetServerDisk) {
			if servers_Save(ext_fleetServersFile(), ext_fleetServerRows()
				, ext_fleetServerVer.version, ext_fleetServerVer.by)
				ext_fleetServerDisk := ext_fleetServerVer
			else
				ext_fleetProblem("could not write the servers replica to "
					. ext_fleetServersFile())
		}
		else {
			ext_fleetSayDivergent("servers", ext_fleetServerVer, ext_fleetServerDisk)
			ext_fleetHandUp("servers")
		}
	}
	return 1
}

;The fleet is running one configuration and this macro holds another, and the
;rule says ours stays.
;
;Only worth a word when the versions are equal and were written by different
;rows - both sides of a split edited separately, which no version can settle
;and which the lowest row wins arbitrarily. Being behind is ordinary and fixes
;itself; being tied means somebody's edit is sitting on this disk and will
;never reach the fleet, and nothing else would ever say so. The coordinator
;keeps the losing copy in a .conflict file; this is the half of that which the
;person looking at this macro can see.
ext_fleetSayDivergent(what, theirs, mine) {
	global ext_fleetSaidDivergent
	local key

	if (theirs.version != mine.version)
		return 0
	if (theirs.by = mine.by)
		return 0
	key := what "/" theirs.version "/" theirs.by
	if (ext_fleetSaidDivergent = key)
		return 0
	ext_fleetSaidDivergent := key
	return ext_fleetProblem("two versions of the " what " at " theirs.version
		. ": the fleet runs row " theirs.by "'s, this macro holds row " mine.by "'s")
}

;Is this version complete enough to act on?
ext_fleetReplicaWhole(store, ver, want) {
	return (ver.version > 0) && want && (store.Count = want)
}

;The coordinator is serving something no better than what is on this disk, so
;offer it what is here.
;
;This is the half that keeps the fleet from freezing on a stale copy. The
;safety rule on its own - never write a worse configuration over a better one -
;stops the damage but leaves the fleet running on whatever the macro that
;happened to take over was holding, with nobody able to correct it. So the
;macro that holds better sends it, and the coordinator takes it if the version
;says it is better. Sent once per version it has seen, not once per frame:
;every row of a configuration arrives separately and all of them would
;otherwise provoke a hand-up of their own.
;
;Nothing is sent when the versions are equal and were written by the same row -
;that is the same configuration, not a disagreement about it.
ext_fleetHandUp(what) {
	global ext_fleetSock, ext_fleetRosterVer, ext_fleetServerVer
	global ext_fleetRosterDisk, ext_fleetServerDisk, ext_fleetHandedUp
	local theirs, mine, rows, row, e, key

	if !ext_fleetSock
		return 0
	if (what = "roster")
		theirs := ext_fleetRosterVer, mine := ext_fleetRosterDisk
	else
		theirs := ext_fleetServerVer, mine := ext_fleetServerDisk
	if ((theirs.version = mine.version) && (theirs.by = mine.by))
		return 0
	if !fleet_ConfigBeats(mine, theirs)
		return 0
	key := what "/" theirs.version "/" theirs.by
	if (ext_fleetHandedUp = key)
		return 0
	ext_fleetHandedUp := key
	if (what = "roster") {
		rows := roster_Load(ext_fleetRosterFile())
		for row, e in rows
			sock_SendLine(ext_fleetSock, fleet_Frame("SETROW"
				, Map("v", mine.version, "by", mine.by, "n", rows.Count
				, "row", e.row, "name", e.name, "role", e.role
				, "user", e.user, "machine", e.machine)))
		return rows.Count
	}
	rows := servers_Load(ext_fleetServersFile())
	for row, e in rows
		sock_SendLine(ext_fleetSock, fleet_Frame("SETSERVER"
			, Map("v", mine.version, "by", mine.by, "n", rows.Count
			, "slot", e.slot, "name", e.name, "link", e.link
			, "owner", e.owner, "kind", e.kind)))
	return rows.Count
}

;The version a frame says its configuration is on.
ext_fleetFrameVer(frame) {
	return { version: fleet_Num(fleet_Field(frame, "v"))
		, by: fleet_Num(fleet_Field(frame, "by")) }
}
ext_fleetSameVer(ver, frame) {
	return (ver.version = fleet_Num(fleet_Field(frame, "v")))
		&& (ver.by = fleet_Num(fleet_Field(frame, "by")))
}

;The two files the fleet's configuration lives in on this machine. Named here
;rather than wherever a window happens to want them, because the replica is
;written whether or not anybody has a window open - and because the coordinator
;derives the second name from the first in exactly this way.
ext_fleetRosterFile() {
	return A_WorkingDir "\settings\fleet_roster.ini"
}
ext_fleetServersFile() {
	return A_WorkingDir "\settings\fleet_roster_servers.ini"
}

;The replicas as roster_Save and servers_Save want them: a frame is a Map of
;wire fields, and these files are written from objects.
ext_fleetRosterRows() {
	global ext_fleetRoster
	local row, f, out := Map()

	for row, f in ext_fleetRoster
		out[row] := { row: row
			, name: ext_FleetCell(f, "name")
			, role: ext_FleetCell(f, "role")
			, user: ext_FleetCell(f, "user")
			, machine: ext_FleetCell(f, "machine") }
	return out
}
ext_fleetServerRows() {
	global ext_fleetServers
	local slot, f, out := Map()

	for slot, f in ext_fleetServers
		out[slot] := { slot: slot
			, name: ext_FleetCell(f, "name")
			, link: ext_FleetCell(f, "link")
			, owner: ext_FleetNum(f, "owner")
			, kind: (ext_FleetCell(f, "kind") = "main") ? "main" : "reserve" }
	return out
}

;Tell the coordinator which field we are farming, when it changes. Called from
;the gather loop - the farm path - so a planter harvest or a booster trip,
;each its own function, never reports one, and the residents following this
;never chase the main anywhere but to farm. Sent only on a change, since the
;gather loop runs the same field many times over.
ext_fleetReportField(field) {
	global ext_fleetSock, ext_fleetMyField

	if (!ext_fleetSock || (field = "") || !ext_fleetFollowReport())
		return 0
	if (field = ext_fleetMyField)
		return 0
	ext_fleetMyField := field
	return sock_SendLine(ext_fleetSock, fleet_Frame("FIELD", Map("name", field)))
}

;Is this trip one worth moving the whole hive for?
;
;Natro gathers in four kinds of field, and they are not equally worth
;following. Its own field and the boosted field are: a fuzzy standing in the
;boosted field is the entire point of having one. A quest field is a trip the
;main makes for itself, and a planter field is one it makes for a planter -
;dragging five accounts along for either is movement for its own sake, which
;costs travel time and gains nothing.
;
;Which is a judgement about a particular setup rather than a fact, so it is
;four switches in Advanced. They are read on the main and nowhere else, since
;the main is what announces; on any other macro they do nothing at all.
;
;A suppressed trip leaves the last announcement standing rather than cancelling
;it: the residents stay in the field the main will come back to, which is
;where they would have to walk anyway.
ext_fleetFollowReport() {
	global fieldOverrideReason
	global FleetFollowOwn, FleetFollowBoost, FleetFollowQuest, FleetFollowPlanter

	switch fieldOverrideReason {
		case "Boost":   return FleetFollowBoost
		case "Quest":   return FleetFollowQuest
		case "Planter": return FleetFollowPlanter
	}
	return FleetFollowOwn
}

;The field this macro should gather to stay with the main, or "" when it is
;not following one. GOTO reaches only the roles roster_Follows admits, so a set
;follow field already means "I was told to follow"; the FieldDefault guard just
;refuses a name this build has no pattern for rather than letting the gather
;loop throw on the lookup. The name round-trips unchanged from the main, which
;gathered it, so it is a valid key by construction - the guard is for the day
;that stops being true.
ext_fleetFollowTarget() {
	global FleetCheck, ext_fleetFollowField, FieldDefault, ext_fleetPeers, FleetRow
	local mine

	if (!FleetCheck || (ext_fleetFollowField = ""))
		return ""
	;A role changed in the roster editor has to take effect without restarting
	;the macro it describes, and nothing else ever withdraws a GOTO - so an
	;account that is no longer a resident stops following here. Checked against
	;the roster rather than against a local setting, because the roster is the
	;one copy everybody agrees on. While disconnected the last order stands: a
	;dropped connection is not a change of job, and reverting on every blip
	;would walk the macro back and forth for nothing.
	if ext_fleetPeers.Has(FleetRow) {
		mine := ext_FleetCell(ext_fleetPeers[FleetRow], "role")
		if ((mine != "") && !roster_Follows(mine)) {
			ext_fleetFollowField := ""
			return ""
		}
	}
	if !FieldDefault.Has(ext_fleetFollowField)
		return ""
	return ext_fleetFollowField
}

;Leaving on purpose, which the fleet cannot tell from a crash on its own - both
;look like a socket closing. Saying so is what turns an offline row into no row
;at all. sock_SendLine flushes as it writes, so the frame is on the wire before
;the caller closes the socket a moment later.
ext_fleetSayLeaving() {
	global ext_fleetSock

	if !ext_fleetSock
		return 0
	return sock_SendLine(ext_fleetSock, fleet_Frame("LEAVE"))
}

;Say we are still here. Cheap, and it is what tells the coordinator apart from a
;macro that has quietly died.
ext_fleetBeat() {
	global ext_fleetSock, ext_fleetRosterDisk

	;the heartbeat carries which configuration this macro holds, so that one
	;macro sitting on a different version from the rest can be seen rather than
	;deduced. It is the only symptom the stale-copy failure has.
	if ext_fleetSock
		sock_SendLine(ext_fleetSock, fleet_Frame("HEARTBEAT"
			, Map("cv", ext_fleetRosterDisk.version, "cby", ext_fleetRosterDisk.by)))
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
	local silent := (nowUnix() - ext_fleetCoordSeen), passedOver

	if (silent > FleetGraceSecs) {
		;Escalating, because one machine can carry several macros and losing it
		;takes all of their rows at once - so the obvious successor is often on
		;the machine that just died. One candidate is passed over per grace
		;period, which gives each a whole period to answer before the next is
		;asked, and it terminates: eventually every candidate ahead of us has
		;been passed over and we take the job ourselves.
		;
		;Counted off the silence rather than kept in a variable, because this
		;runs every five seconds and a counter incremented here would escalate
		;nine times a period.
		passedOver := (silent // FleetGraceSecs) - 1
		if (ext_fleetSuccessor(passedOver) = FleetRow)
			ext_fleetTakeOver("no coordinator for " silent "s")
		return
	}
	;the host reclaiming: only once the stand-in has actually been heard from,
	;so a host starting up does not fight a coordinator that is about to answer
	if ((FleetRow = FleetHostRow) && ext_fleetCoordRow && (ext_fleetCoordRow != FleetRow))
		ext_fleetTakeOver("host reclaiming from row " ext_fleetCoordRow)
}

;Whose turn it is to coordinate. Ours counts even when the roster is empty - a
;macro that has never reached a coordinator is still allowed to become one,
;otherwise the first one started would wait for ever.
;
;skip passes over that many candidates ahead of us, which is how the election
;gets past a successor that was on the same dead machine as the coordinator.
;Every macro holds the same roster and counts the same way, so they all reach
;the same answer without a message being sent about it.
ext_fleetSuccessor(skip := 0) {
	global ext_fleetPeers, FleetRow
	local row, p, ahead := []

	for row, p in ext_fleetPeers {
		if (p.Has("state") && (p["state"] != "online"))
			continue
		if (row < FleetRow)
			ahead.Push(row)
	}
	roster_Sort(ahead)
	return (skip < ahead.Length) ? ahead[skip + 1] : FleetRow
}

;Start a coordinator here, one term above whatever we last saw, and reconnect to
;it. The higher term is what makes the fleet follow us rather than the process
;we are replacing.
ext_fleetTakeOver(why) {
	global ext_fleetTerm, ext_fleetSock, ext_fleetCoordSeen, ext_fleetCoordPid
	global FleetPort, FleetSecret, FleetRow, exe_path32

	;A coordinator we started and which is still running is the coordinator. A
	;second one would be refused the port anyway, and leaving the first behind
	;is how a machine collects a handful of them - two accumulated in the test
	;VM before anybody noticed they were there.
	if (ext_fleetCoordPid && ProcessExist(ext_fleetCoordPid))
		return 0
	nm_setStatus("Starting", "Fleet coordinator`n" why)
	ext_fleetTerm++
	;the failure is caught rather than swallowed: a wrong path here means no
	;coordinator ever starts, and the macro would otherwise retry for ever
	;against a launch that silently does nothing
	try
		Run '"' exe_path32 '" /script "' A_WorkingDir '\submacros\Fleet.ahk" '
			. FleetPort ' "' FleetSecret '" ' ext_fleetTerm ' ' FleetRow
			, , "Hide", &ext_fleetCoordPid
	catch as e {
		ext_fleetCoordPid := 0
		ext_fleetProblem("could not start a coordinator: " e.Message)
	}
	;give it a moment to bind before knocking, and drop the dead connection so
	;the next attempt starts from loopback again
	if ext_fleetSock
		sock_Close(ext_fleetSock), ext_fleetSock := 0
	ext_fleetCoordSeen := nowUnix()
	SetTimer ext_fleetConnect, -2000
	return 1
}

;Stop the coordinator this macro started.
;
;It is a separate process and nothing else would ever end it. The macro that
;launched it can be closed, or crash, and the coordinator carries on holding
;the port and shouting its beacon at the network for as long as the machine is
;up. The coordinator has an idle timeout of its own for the crash case; this is
;the ordinary one.
ext_fleetEndCoord() {
	global ext_fleetCoordPid

	if (ext_fleetCoordPid && ProcessExist(ext_fleetCoordPid))
		try ProcessClose(ext_fleetCoordPid)
	ext_fleetCoordPid := 0
	return 1
}

;Registered with OnExit beside the macro's own handler rather than inside it -
;upstream's exit path is not ours to edit, and OnExit takes more than one.
ext_fleetOnExit(*) {
	ext_fleetEndCoord()
}

;Something went wrong in a way nobody would otherwise hear about.
;
;Almost everything in this subsystem is wrapped in a bare try, which is right
;for a repaint that failed and wrong for anything that matters. A fault goes in
;the fleet's own log where the panel shows it, and the last one is kept so a
;line of the panel can say so without scrolling.
ext_fleetProblem(text) {
	global ext_fleetEvents, ext_fleetLastProblem

	ext_fleetLastProblem := FormatTime(A_Now, "HH:mm:ss") "  " text
	ext_fleetEvents.InsertAt(1, ext_fleetLastProblem)
	while (ext_fleetEvents.Length > 80)
		ext_fleetEvents.Pop()
	return 1
}

;Bring the whole thing up. Called once, from the macro's start-up.
ext_fleetStart() {
	global FleetCheck, FleetRow, FleetHostRow, ext_fleetRefused
	global ext_fleetRosterDisk, ext_fleetServerDisk

	;a refusal is forgotten the moment somebody sets this macro up again -
	;that is what being set up again means
	ext_fleetRefused := ""
	;what this machine already holds, so the first configuration that arrives
	;can be compared against it rather than trusted on sight
	ext_fleetRosterDisk := fleet_ConfigVersion(ext_fleetRosterFile())
	ext_fleetServerDisk := fleet_ConfigVersion(ext_fleetServersFile())
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
	global ext_fleetSock, ext_fleetPeers, ext_fleetServers, ext_fleetServerVer
	global ext_fleetRoster, ext_fleetRosterVer, ext_fleetHandedUp

	;nothing known about the fleet survives not being connected to it
	ext_fleetPeers.Clear()
	ext_fleetServers.Clear(), ext_fleetServerVer := { version: -1, by: -1 }
	ext_fleetRoster.Clear(), ext_fleetRosterVer := { version: -1, by: -1 }
	ext_fleetHandedUp := ""
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
	global FleetCheck, ext_fleetFoundAt, ext_fleetRefused
	local silent

	if !FleetCheck
		return "Fleet is off"
	;said plainly, because "listening for a coordinator" would be a lie - this
	;macro has stopped looking and somebody has to do something about it
	if (ext_fleetRefused != "")
		return "The fleet refused this macro: " ext_fleetRefused
			. " - set it up again to rejoin"
	if !ext_fleetSock {
		return ext_fleetFoundAt
			? "Found a coordinator at " ext_fleetFoundAt " - connecting"
			: "Listening for a coordinator on the network"
	}
	silent := nowUnix() - ext_fleetCoordSeen
	;named rather than numbered. "row 1" means nothing to somebody wondering
	;which machine to go and look at; the account and the machine mean
	;everything, and the address it was reached on says less than either now
	;that the machine can be named.
	return "Fleet run by " ext_FleetOr(ext_fleetCoordWho(), "a macro it cannot name yet")
		. " - term " ext_fleetTerm " - " ext_fleetConfigLine()
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
;Reserve and offline get a row each rather than sharing one. A macro parked in
;the reserve server and a macro that is not running are opposite situations -
;one is ready, one needs attention - and lining them up together invites
;reading either as the other.
FLEET_SEATS_RESERVE := 6
FLEET_SEATS_OFFLINE := 6
;A card is a bordered backing with three labels inset into it. Three, because
;a Text control carries one font and the account has to be the thing the eye
;lands on; a backing, because the border has to go round the card rather than
;round each of its lines. 94 by 48 on a 98 by 54 pitch.
FLEET_CARD_W := 94
FLEET_CARD_H := 48

ext_FleetGUI(*) {
	global FleetGui, FLEET_SEATS_MAIN, FLEET_SEATS_RESERVE, FLEET_SEATS_OFFLINE
	local i

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
	FleetGui.Add("Text", "x16 y162 w300 vFleetReserveLabel", "RESERVE")
	FleetGui.Add("Text", "x404 y162 w200 Right vFleetReserveCount", "")
	FleetGui.Add("Text", "x16 y236 w300 vFleetOfflineLabel", "OFFLINE")
	FleetGui.Add("Text", "x404 y236 w200 Right vFleetOfflineCount", "")
	FleetGui.SetFont("Norm")

	;seat cards, six to a row
	Loop FLEET_SEATS_MAIN {
		i := A_Index - 1
		ext_FleetMakeCard("FleetSeatM" A_Index, 16 + Mod(i, 6) * 98, 52 + (i // 6) * 54)
	}
	Loop FLEET_SEATS_RESERVE {
		i := A_Index - 1
		ext_FleetMakeCard("FleetSeatR" A_Index, 16 + Mod(i, 6) * 98, 180)
	}
	Loop FLEET_SEATS_OFFLINE {
		i := A_Index - 1
		ext_FleetMakeCard("FleetSeatO" A_Index, 16 + Mod(i, 6) * 98, 254)
	}
	FleetGui.SetFont("s8 c808080 Norm", "Tahoma")
	FleetGui.Add("Text", "x16 y310 w588", "Click an account for its details.")
	FleetGui.SetFont("s8 cDefault Norm", "Tahoma")

	;newest first, so the line that just appeared is the one on screen and
	;nothing has to be scrolled
	FleetGui.Add("Text", "x16 y328 w588 h1 +0x10")
	FleetGui.SetFont("s8", "Consolas")
	FleetGui.Add("Edit", "x16 y336 w588 h112 ReadOnly -Wrap +VScroll vFleetLog", "")
	FleetGui.SetFont("s8 cDefault Norm", "Tahoma")

	FleetGui.Add("Button", "x16 y456 w100 h26", "Settings").OnEvent("Click", ext_FleetSetupGUI)
	FleetGui.Add("Button", "x504 y456 w100 h26", "Close").OnEvent("Click", ext_FleetGUIClose)

	ext_FleetRefresh()
	SetTimer ext_FleetRefresh, 1000
	FleetGui.Show("w620 h494")
}

ext_FleetGUIClose(*) {
	global FleetGui

	SetTimer ext_FleetRefresh, 0
	;the detail window belongs to a card in this one, so it goes too
	ext_FleetPeerClose()
	if (IsSet(FleetGui) && IsObject(FleetGui))
		FleetGui.Destroy(), FleetGui := ""
}

;Repaint the seats and the log. Called every second, so it only ever changes
;text and colour on controls that already exist.
ext_FleetRefresh() {
	global FleetGui, ext_fleetEvents
	global FLEET_SEATS_MAIN, FLEET_SEATS_RESERVE, FLEET_SEATS_OFFLINE
	local main := [], reserve := [], offline := [], p

	if !(IsSet(FleetGui) && IsObject(FleetGui))
		return
	try FleetGui["FleetSummary"].Text := ext_fleetSummary()

	;State decides first and the server only afterwards: a macro that is not
	;running belongs under OFFLINE whatever server it was last seen in, since
	;what it needs is attention rather than a place in a queue. Nothing reports
	;a server yet, so RESERVE stays empty until the queue does - and an empty
	;section says so rather than borrowing the offline macros to look busy.
	for _, p in ext_fleetView() {
		if (ext_FleetCell(p, "state") != "online")
			offline.Push(p)
		else if (ext_FleetCell(p, "server") = "reserve")
			reserve.Push(p)
		else
			main.Push(p)
	}

	ext_FleetPaintRow("FleetSeatM", FLEET_SEATS_MAIN, main, 1)
	ext_FleetPaintRow("FleetSeatR", FLEET_SEATS_RESERVE, reserve, 0)
	ext_FleetPaintRow("FleetSeatO", FLEET_SEATS_OFFLINE, offline, 0)
	try FleetGui["FleetMainCount"].Text := main.Length " / " ext_fleetCapacity()
	try FleetGui["FleetReserveCount"].Text := reserve.Length ? reserve.Length : "none"
	try FleetGui["FleetOfflineCount"].Text := offline.Length ? offline.Length : "none"

	try FleetGui["FleetLog"].Value := ext_fleetEvents.Length
		? ext_FleetJoin(ext_fleetEvents)
		: "Nothing has happened yet."
}

;Fill the cards of one section, and hide the ones nobody needs. Free places are
;only drawn in the main server: an empty reserve is not a place waiting to be
;filled, it is simply nothing.
ext_FleetPaintRow(prefix, pool, list, showFree) {
	global ext_fleetSeatRow
	local i, p, free := showFree ? ext_fleetCapacity() : 0

	Loop pool {
		i := A_Index
		if (i <= list.Length) {
			p := list[i]
			ext_FleetSetCard(prefix i, ext_FleetSeatName(p), ext_FleetCell(p, "role")
				, ext_FleetSeatFoot(p), ext_FleetSeatColour(p), true)
			ext_fleetSeatRow[prefix i] := ext_FleetNum(p, "row")
		}
		else if (i <= free) {
			ext_FleetSetCard(prefix i, "", "free", "", "E6E6E6", true)
			ext_fleetSeatRow[prefix i] := 0
		}
		else {
			ext_FleetSetCard(prefix i, "", "", "", "E6E6E6", false)
			ext_fleetSeatRow[prefix i] := 0
		}
	}
}

;One card: the account large, then its role, then the machine it runs on. That
;order is the point - the account is what a decision is made about, the machine
;only matters once something has to be fixed.
;
;Four controls, not three. The backing carries the border and the fill; the
;labels are inset two pixels into it so the border reads as a frame round the
;whole card instead of a line under each of its lines.
ext_FleetMakeCard(key, x, y) {
	global FleetGui, FLEET_CARD_W, FLEET_CARD_H
	local suffix, w := FLEET_CARD_W - 4

	FleetGui.Add("Text", "x" x " y" y " w" FLEET_CARD_W " h" FLEET_CARD_H " Border v" key "b", "")
	FleetGui.SetFont("s10 cDefault Bold", "Tahoma")
	FleetGui.Add("Text", "x" (x + 2) " y" (y + 3) " w" w " h18 Center v" key "n", "")
	FleetGui.SetFont("s8 cDefault Norm", "Tahoma")
	FleetGui.Add("Text", "x" (x + 2) " y" (y + 21) " w" w " h13 Center v" key "r", "")
	FleetGui.SetFont("s7 c606060 Norm", "Tahoma")
	FleetGui.Add("Text", "x" (x + 2) " y" (y + 34) " w" w " h11 Center v" key "m", "")
	FleetGui.SetFont("s8 cDefault Norm", "Tahoma")
	for _, suffix in ["b", "n", "r", "m"]
		FleetGui[key suffix].OnEvent("Click", ext_FleetSeatClick)
}

;The four controls of one card, painted as a block so they read as one. The
;backing is painted first and the labels over it, so a card never shows one
;macro's name on another's colour even for a frame.
ext_FleetSetCard(key, name, role, machine, colour, shown) {
	global FleetGui
	local parts := [["b", ""], ["n", name], ["r", role], ["m", machine]], e, ctrl

	for _, e in parts {
		try ctrl := FleetGui[key e[1]]
		catch
			continue
		;the fill is reapplied every time rather than only when it changes:
		;Windows does not repaint a static control's background on its own, and
		;a card that kept the colour of whoever sat there before is the bug this
		;guards against
		ctrl.Opt("Background" colour)
		ctrl.Text := e[2]
		ctrl.Visible := shown
		ctrl.Redraw()
	}
}

;A card was clicked. The control's own name says which seat it is, which saves
;binding a handler per row - the rows move between seats on every refresh, the
;seats do not.
ext_FleetSeatClick(ctrl, *) {
	global ext_fleetSeatRow
	local key := SubStr(ctrl.Name, 1, -1)

	if (ext_fleetSeatRow.Has(key) && ext_fleetSeatRow[key])
		ext_FleetPeerGUI(ext_fleetSeatRow[key])
}

;The title of a card, and of the detail window.
;
;The Roblox username comes first because that is the account - it is what the
;fleet makes decisions about and what a person recognises. The roster's own
;label is the fallback, and since the setup dialog fills that in with the
;computer name, a fleet whose accounts have no username set showed a wall of
;machine names with the machine repeated underneath. The row number is the last
;resort, because an untitled card is unreadable.
ext_FleetSeatName(p) {
	local user := ext_FleetCell(p, "user"), name := ext_FleetCell(p, "name")

	if (user != "")
		return user
	return (name != "") ? name : "row " ext_FleetNum(p, "row")
}

;The third line of a card. The machine, and the roster label beside it when
;that label is saying something the headline is not - with no username set the
;label *is* the headline, and repeating it under itself tells nobody anything.
ext_FleetSeatFoot(p) {
	local machine := ext_FleetCell(p, "machine"), name := ext_FleetCell(p, "name")

	if ((name = "") || (name = machine) || (ext_FleetCell(p, "user") = ""))
		return machine
	return name " - " machine
}

;Colour says state at a glance, which is the whole reason for drawing seats
;rather than listing rows.
ext_FleetSeatColour(p) {
	if (ext_FleetCell(p, "state") = "offline")
		return "DCDCDC"
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

;The same, as a number. A frame carries text, and a field an older coordinator
;never sent arrives empty rather than zero - Integer("") would throw.
ext_FleetNum(fields, name) {
	local v := ext_FleetCell(fields, name)

	return (v != "") ? Integer(v) : 0
}

;--- one account, in detail ---------------------------------------------------
;
;A card is three lines because three is what can be read at a glance across
;twelve of them. Everything else about a macro lives here, one click away.
;
;Some of these are deliberately placeholders. The queue that will report boost
;tokens and guiding stars is not written yet, so those lines say they have not
;been reported rather than showing a zero that reads as a measurement. When the
;queue starts sending CHARGE and GUIDING, this panel shows it with no further
;change - the protocol already carries both.

ext_FleetPeerGUI(row) {
	global FleetPeerGui, FleetPeerShown

	FleetPeerShown := row
	if (IsSet(FleetPeerGui) && IsObject(FleetPeerGui)) {
		ext_FleetPeerDraw()
		FleetPeerGui.Show()
		return
	}
	FleetPeerGui := Gui("+AlwaysOnTop +Border", "Fleet - account")
	FleetPeerGui.OnEvent("Close", ext_FleetPeerClose)

	FleetPeerGui.SetFont("s12 cDefault Bold", "Tahoma")
	FleetPeerGui.Add("Text", "x16 y12 w348 vPeerName", "")
	FleetPeerGui.SetFont("s8 cDefault Norm", "Tahoma")
	FleetPeerGui.Add("Text", "x16 y40 w348 vPeerSub", "")
	FleetPeerGui.Add("Text", "x16 y62 w348 h1 +0x10")

	;who and where
	ext_FleetPeerLine("PeerWhere", 74, "Server")
	ext_FleetPeerLine("PeerField", 96, "Field")
	ext_FleetPeerLine("PeerUser", 118, "Roblox user")
	ext_FleetPeerLine("PeerLabel", 140, "Roster label")
	ext_FleetPeerLine("PeerMachine", 162, "Machine")
	;read off the server list rather than off a flag on this account: an
	;account can own more than one server, which is the whole reason the flag
	;was taken off the roster
	ext_FleetPeerLine("PeerOwns", 184, "Owns")
	FleetPeerGui.Add("Text", "x16 y210 w348 h1 +0x10")
	;the queue, once it exists
	ext_FleetPeerLine("PeerTokens", 222, "Boost tokens")
	ext_FleetPeerLine("PeerGuiding", 244, "Guiding star")
	FleetPeerGui.Add("Text", "x16 y270 w348 h1 +0x10")
	;the link itself
	ext_FleetPeerLine("PeerRtt", 282, "Response time")
	ext_FleetPeerLine("PeerSeen", 304, "Last heard from")
	;which configuration this particular macro is holding. Per account rather
	;than once for the fleet, because the failure worth seeing is one macro
	;sitting on a version of its own.
	ext_FleetPeerLine("PeerConfig", 326, "Configuration")

	FleetPeerGui.Add("Button", "x264 y362 w100 h26", "Close").OnEvent("Click", ext_FleetPeerClose)

	ext_FleetPeerDraw()
	SetTimer ext_FleetPeerDraw, 1000
	FleetPeerGui.Show("w380 h400")
}

;Label left, value right. Every line the same shape reads faster than sentences.
ext_FleetPeerLine(name, y, label) {
	global FleetPeerGui

	FleetPeerGui.SetFont("s8 c808080 Norm", "Tahoma")
	FleetPeerGui.Add("Text", "x16 y" y " w110", label)
	FleetPeerGui.SetFont("s8 cDefault Norm", "Tahoma")
	FleetPeerGui.Add("Text", "x132 y" y " w232 v" name, "")
}

ext_FleetPeerClose(*) {
	global FleetPeerGui

	SetTimer ext_FleetPeerDraw, 0
	if (IsSet(FleetPeerGui) && IsObject(FleetPeerGui))
		FleetPeerGui.Destroy(), FleetPeerGui := ""
}

ext_FleetPeerDraw() {
	global FleetPeerGui, FleetPeerShown, ext_fleetPeers
	local p, guiding, left, rtt

	if !(IsSet(FleetPeerGui) && IsObject(FleetPeerGui))
		return
	;the account can leave the fleet while its panel is open, and a panel
	;showing the last thing it said would be a lie
	if !ext_fleetPeers.Has(FleetPeerShown) {
		try FleetPeerGui["PeerName"].Text := "Gone"
		try FleetPeerGui["PeerSub"].Text := "This account is no longer in the fleet."
		return
	}
	p := ext_fleetPeers[FleetPeerShown]
	try FleetPeerGui["PeerName"].Text := ext_FleetSeatName(p)
	try FleetPeerGui["PeerSub"].Text := ext_FleetCell(p, "role")
		. " - " ext_FleetCell(p, "state")

	;no server field until the queue assigns one, so being seated is as much as
	;can honestly be said
	try FleetPeerGui["PeerWhere"].Text := (ext_FleetCell(p, "server") != "")
		? ext_FleetCell(p, "server")
		: ((ext_FleetCell(p, "state") = "online") ? "main server" : "not seated")
	try FleetPeerGui["PeerField"].Text := ext_FleetOr(ext_FleetCell(p, "field"), "not farming")
	try FleetPeerGui["PeerUser"].Text := ext_FleetOr(ext_FleetCell(p, "user")
		, "not set - the cards fall back to the label below")
	try FleetPeerGui["PeerLabel"].Text := ext_FleetOr(ext_FleetCell(p, "name"), "none")
	try FleetPeerGui["PeerMachine"].Text := ext_FleetOr(ext_FleetCell(p, "machine"), "unknown")
	try FleetPeerGui["PeerOwns"].Text := ext_FleetOr(ext_fleetOwnedBy(FleetPeerShown)
		, "no server")

	;250 is a full charge, which is what a guiding star costs
	try FleetPeerGui["PeerTokens"].Text := (ext_FleetNum(p, "charge") > 0)
		? ext_FleetNum(p, "charge") " / 250"
		: "not reported yet"
	guiding := ext_FleetCell(p, "guiding")
	left := ext_FleetNum(p, "until") - nowUnix()
	try FleetPeerGui["PeerGuiding"].Text := (guiding = "")
		? "none"
		: guiding . ((left > 0)
			? " - " Floor(left / 60) ":" Format("{:02}", Mod(left, 60)) " left"
			: " - over")

	rtt := ext_FleetCell(p, "rtt")
	try FleetPeerGui["PeerRtt"].Text := ((rtt != "") && (Integer(rtt) >= 0))
		? Integer(rtt) " ms"
		: "not measured yet"
	try FleetPeerGui["PeerSeen"].Text := ext_FleetAgo(ext_FleetNum(p, "seen"))
	try FleetPeerGui["PeerConfig"].Text := ext_FleetPeerConfig(p)
}

;What configuration one macro says it is holding, against what the fleet runs.
;
;"in step" rather than a version number when they agree, because the number
;only matters when it is the wrong one - and a panel of matching numbers is a
;panel nobody reads.
ext_FleetPeerConfig(p) {
	global ext_fleetRosterVer
	local v := ext_FleetNum(p, "cv"), by := ext_FleetNum(p, "cby")

	if !v
		return "has not said"
	if ((v = ext_fleetRosterVer.version) && (by = ext_fleetRosterVer.by))
		return "v" v ", in step with the fleet"
	return "v" v " by row " by " - THE FLEET RUNS v" ext_fleetRosterVer.version
		. " by row " ext_fleetRosterVer.by
}

ext_FleetOr(value, fallback) {
	return (value != "") ? value : fallback
}

;"4s ago" rather than a clock time: what a reader wants to know is how stale
;this is, not what time it was.
ext_FleetAgo(stamp) {
	local age

	if (stamp <= 0)
		return "never"
	age := nowUnix() - stamp
	if (age < 60)
		return age "s ago"
	if (age < 3600)
		return Floor(age / 60) "m " Mod(age, 60) "s ago"
	return Floor(age / 3600) "h " Mod(Floor(age / 60), 60) "m ago"
}

;--- settings, in a window of their own --------------------------------------

;Three sections, and the first one has no fields at all any more.
;
;It used to ask you to invent row numbers, type them into a table, then go to
;every other machine and pick which row it was and retype the secret. That is
;building the directory before anything can talk. Binding turns it round: the
;two sides find each other, and the table fills itself in as macros arrive.
ext_FleetSetupGUI(*) {
	global FleetSetupGui, FleetRoster, FleetRosterPath, FleetServersPath
	local GuiCtrl

	if (IsSet(FleetSetupGui) && IsObject(FleetSetupGui)) {
		FleetSetupGui.Show()
		return
	}
	FleetRosterPath := ext_fleetRosterFile()
	FleetRoster := roster_Load(FleetRosterPath)
	FleetServersPath := ext_fleetServersFile()

	FleetSetupGui := Gui("+AlwaysOnTop +Border", "Fleet - settings")
	FleetSetupGui.OnEvent("Close", ext_FleetSetupClose)
	FleetSetupGui.SetFont("s8 cDefault Bold", "Tahoma")
	FleetSetupGui.Add("GroupBox", "x8 y4 w584 h68", "1 - this macro")
	FleetSetupGui.Add("GroupBox", "x8 y76 w584 h66", "2 - the servers, shared with the fleet")
	FleetSetupGui.Add("GroupBox", "x8 y146 w584 h150", "3 - the accounts")
	FleetSetupGui.SetFont("Norm")

	FleetSetupGui.Add("Text", "x18 y22 w420 h36 vFleetWho", "")
	FleetSetupGui.Add("Button", "x446 y20 w136 h22 vFleetAct1", "").OnEvent("Click", ext_FleetAct1)
	FleetSetupGui.Add("Button", "x446 y44 w136 h22 vFleetAct2", "").OnEvent("Click", ext_FleetAct2)

	;Two edit boxes used to sit here, one main and one reserve, typed again on
	;every machine. There can be any number of reserves now and each one names
	;the account that owns it, which is a table rather than a pair of fields -
	;so it has a window, and this says what is in it.
	FleetSetupGui.Add("Text", "x18 y94 w460 h40 vFleetServerSummary", "")
	FleetSetupGui.Add("Button", "x486 y96 w96 h22", "Servers").OnEvent("Click", ext_FleetServersGUI)

	;no row column: the numbers are assigned at binding and nobody needs to see
	;them. They are still in Advanced for the day something has to be matched up
	;against a log.
	;no Owner column either: owning a server is a fact about the server, and it
	;is set beside the server's own link
	FleetSetupGui.Add("ListView", "x16 y164 w340 h122 -Multi vFleetRosterList"
		, ["Name", "Role", "Roblox user"])
	FleetSetupGui["FleetRosterList"].OnEvent("ItemSelect", ext_FleetRosterSelect)
	FleetSetupGui.Add("Text", "x364 y168 w36", "Name:")
	FleetSetupGui.Add("Edit", "x404 y166 w178 h18 vFleetEditName")
	FleetSetupGui.Add("Text", "x364 y194 w36", "Role:")
	FleetSetupGui.Add("DropDownList", "x404 y192 w100 vFleetEditRole", roster_Roles())
	FleetSetupGui.Add("Text", "x364 y220 w36", "User:")
	FleetSetupGui.Add("Edit", "x404 y218 w178 h18 vFleetEditUser")
	FleetSetupGui.SetFont("c808080")
	FleetSetupGui.Add("Text", "x364 y244 w218 vFleetRosterNote", "")
	FleetSetupGui.SetFont("cDefault")
	FleetSetupGui.Add("Button", "x364 y268 w104 h24 vFleetRosterUpdate", "Update")
		.OnEvent("Click", ext_FleetRosterSave)
	FleetSetupGui.Add("Button", "x478 y268 w104 h24 vFleetRosterRemove", "Remove")
		.OnEvent("Click", ext_FleetRosterRemove)

	FleetSetupGui.Add("Button", "x8 y304 w100 h26", "Advanced").OnEvent("Click", ext_FleetAdvanced)
	FleetSetupGui.Add("Button", "x492 y304 w100 h26", "Close").OnEvent("Click", ext_FleetSetupClose)

	ext_FleetRosterDraw()
	ext_FleetWhoDraw()
	ext_FleetServerSummary()
	SetTimer ext_FleetWhoDraw, 1000
	SetTimer ext_FleetRosterWatch, 1000
	FleetSetupGui.Show("w600 h342")
}

ext_FleetSetupClose(*) {
	global FleetSetupGui

	SetTimer ext_FleetWhoDraw, 0
	SetTimer ext_FleetRosterWatch, 0
	if (IsSet(FleetSetupGui) && IsObject(FleetSetupGui))
		FleetSetupGui.Destroy(), FleetSetupGui := ""
}

;The roster file changes underneath this window - a macro leaving takes its own
;row out of it, and on the host that happens while the table is on screen. So
;the table follows the file rather than only being read when the window opens.
;Size and time together catch an edit that happens to keep the length the same.
ext_FleetRosterWatch() {
	global FleetSetupGui, FleetRoster, FleetRosterPath, FleetRosterStamp
	local stamp := FileExist(FleetRosterPath)
		? FileGetTime(FleetRosterPath, "M") "/" FileGetSize(FleetRosterPath)
		: ""

	if !(IsSet(FleetSetupGui) && IsObject(FleetSetupGui))
		return
	if (IsSet(FleetRosterStamp) && (stamp = FleetRosterStamp))
		return
	FleetRosterStamp := stamp
	FleetRoster := roster_Load(FleetRosterPath)
	ext_FleetRosterDraw()
}

;Section one says where this macro stands and offers the one or two things worth
;doing from there. Three states, and each gets different buttons rather than a
;row of buttons that are mostly greyed out.
ext_FleetWhoDraw() {
	global FleetSetupGui, FleetRoster, FleetRow, ext_fleetBindOpenUntil
	local me, left, who

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
	;Against who is coordinating, not who was named as host. The two differ
	;after a takeover, and this said "hosts the fleet" on a macro that did not -
	;then offered it a door to open that the coordinator would refuse, because
	;the coordinator only obeys the row that started it.
	if ext_fleetCoordinating() {
		left := ext_fleetBindOpenUntil - nowUnix()
		FleetSetupGui["FleetWho"].Text := me "`nThis macro is running the fleet."
		ext_FleetButton("FleetAct1", (left > 0)
			? "Stop accepting (" Floor(left / 60) ":" Format("{:02}", Mod(left, 60)) ")"
			: "Accept new macros")
		ext_FleetButton("FleetAct2", "Leave the fleet")
		return
	}
	FleetSetupGui["FleetWho"].Text := me "`nJoined this fleet."
		. ((who := ext_fleetCoordWho()) != "" ? "  Run by " who "." : "")
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
	global FleetRow, ext_fleetBindOpenUntil

	if (FleetRow <= 0) {
		ext_FleetJoinGUI()
		return
	}
	if ext_fleetCoordinating() {
		;toggle: an open door shuts, a shut one opens for two minutes - the
		;window the coordinator will honour anyway
		if (ext_fleetBindOpenUntil > nowUnix()) {
			ext_fleetOpenDoor(0)
			ext_fleetBindOpenUntil := 0
		} else if ext_fleetOpenDoor(120)
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
	;said before the socket goes, so the fleet takes this row off the roster
	;instead of listing it offline for ever
	ext_fleetSayLeaving()
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
	FleetJoinGui.Add("Text", "x262 y26 w142", "The Roblox username is what the fleet window shows for this account. The name is only a label.")
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
	;the global is set either way, so the screen and this session agree; it is
	;the ini that may refuse, and a setting that did not reach disk is a macro
	;that forgets what it was told the next time it starts
	try
		IniWrite value, "settings\nm_config.ini", "Fleet", name
	catch as e
		ext_fleetProblem("could not save " name " to settings\nm_config.ini: "
			. e.Message)
}

;--- the servers -------------------------------------------------------------
;
;One main private server and as many reserves as a setup needs: somewhere to
;park an account that has to leave the main, somewhere to stage a guiding star,
;somewhere to put a macro that is between jobs.
;
;Each one names the account that owns it, because only the owner's /kick clears
;anybody out - so "who can empty this server" is a fact about the server. One
;flag on one roster row could not say that two servers have two different
;owners, which is why that flag is gone from the roster editor.
;
;A window of its own, because it is a table and the setup window already has
;three sections stacked in it.

;Is this the macro whose configuration files the fleet actually uses?
;
;Against the row that is coordinating right now, not the one the panel named as
;host. Those differ after a takeover, and this asked the wrong one: the
;designated host would offer to edit files nobody was reading, while the macro
;actually coordinating refused to edit the files it was reading. Both backwards.
;
;The row the coordinator reports on every heartbeat is the row that started it,
;and a coordinator is started in its starter's own working directory - so that
;row is exactly the one whose settings folder the fleet is living out of.
;
;A macro with no row yet counts too: it has nothing to join, and its file is
;the one it will host with.
ext_fleetServerHost() {
	global FleetRow

	return (FleetRow <= 0) || ext_fleetCoordinating()
}

;Is this macro the one running the coordinator right now?
;
;Not FleetHostRow, which is only the macro the panel named as host and which
;stops being the coordinator the moment somebody stands in for it. Everything
;that asks "may I do the coordinator's job" has to ask this instead, and more
;than one thing had been asking the other.
ext_fleetCoordinating() {
	global FleetRow, ext_fleetCoordRow

	return (FleetRow > 0) && (FleetRow = ext_fleetCoordRow)
}

;The list this window shows.
;
;On the host, the file - which is also what gets edited. Anywhere else, what
;was broadcast, read only: a window where you can type a link that silently
;does nothing is worse than no window.
ext_fleetServerList() {
	global FleetServers, FleetServersPath

	if ext_fleetServerHost() {
		FleetServers := servers_Load(FleetServersPath)
		return FleetServers
	}
	FleetServers := ext_fleetServerRows()
	return FleetServers
}

;Bring the old pair of settings across, once.
;
;They were two edit boxes in the settings window, retyped on every machine, and
;somebody may well have pasted real links into them. Losing a link in silence
;is rude. Done on the first open rather than at startup because it writes a
;file, and a macro that is not hosting has no business writing one.
ext_fleetSeedServers() {
	global FleetServersPath, FleetServerMain, FleetServerReserve, FleetRow
	local list

	if (FileExist(FleetServersPath) || !ext_fleetServerHost())
		return 0
	if ((FleetServerMain = "") && (FleetServerReserve = ""))
		return 0
	list := Map()
	list[1] := { slot: 1, name: "Main", link: FleetServerMain, owner: 0, kind: "main" }
	if (FleetServerReserve != "")
		list[2] := { slot: 2, name: "Reserve", link: FleetServerReserve
			, owner: 0, kind: "reserve" }
	return servers_Save(FleetServersPath, list, 1, FleetRow)
}

ext_FleetServersGUI(*) {
	global FleetServersGui, FleetServerSlot

	if (IsSet(FleetServersGui) && IsObject(FleetServersGui)) {
		FleetServersGui.Show()
		return
	}
	ext_fleetSeedServers()
	FleetServerSlot := 0

	FleetServersGui := Gui("+AlwaysOnTop +Border", "Fleet - servers")
	FleetServersGui.OnEvent("Close", ext_FleetServersClose)
	FleetServersGui.SetFont("s8 c808080 Norm", "Tahoma")
	FleetServersGui.Add("Text", "x16 y12 w588 vFleetServerNote", "")
	FleetServersGui.SetFont("s8 cDefault Norm", "Tahoma")

	FleetServersGui.Add("ListView", "x16 y44 w588 h150 -Multi vFleetServerList"
		, ["Server", "Link", "Owner"])
	FleetServersGui["FleetServerList"].OnEvent("ItemSelect", ext_FleetServerSelect)

	FleetServersGui.Add("Text", "x16 y206 w44", "Name:")
	FleetServersGui.Add("Edit", "x64 y204 w170 h18 vFleetServerName")
	FleetServersGui.Add("Text", "x248 y206 w44", "Owner:")
	FleetServersGui.Add("DropDownList", "x296 y204 w220 vFleetServerOwner"
		, ext_fleetOwnerChoices())
	FleetServersGui.Add("Text", "x16 y232 w44", "Link:")
	FleetServersGui.Add("Edit", "x64 y230 w540 h18 vFleetServerLink")

	FleetServersGui.Add("Button", "x16 y260 w104 h26 vFleetServerUpdate", "Update")
		.OnEvent("Click", ext_FleetServerSave)
	FleetServersGui.Add("Button", "x128 y260 w104 h26 vFleetServerAdd", "Add reserve")
		.OnEvent("Click", ext_FleetServerAdd)
	FleetServersGui.Add("Button", "x240 y260 w104 h26 vFleetServerDel", "Remove")
		.OnEvent("Click", ext_FleetServerRemove)

	FleetServersGui.SetFont("s8 c808080 Norm", "Tahoma")
	FleetServersGui.Add("Text", "x16 y296 w588"
		, "The main server is where the fleet works and cannot be removed. An owner`nmatters because only that account's /kick does anything.")
	FleetServersGui.SetFont("s8 cDefault Norm", "Tahoma")
	FleetServersGui.Add("Button", "x504 y334 w100 h26", "Close").OnEvent("Click", ext_FleetServersClose)

	ext_FleetServerDraw()
	SetTimer ext_FleetServerWatch, 1000
	FleetServersGui.Show("w620 h372")
}

ext_FleetServersClose(*) {
	global FleetServersGui

	SetTimer ext_FleetServerWatch, 0
	if (IsSet(FleetServersGui) && IsObject(FleetServersGui))
		FleetServersGui.Destroy(), FleetServersGui := ""
}

;The list changes underneath this window - the coordinator rewrites the file
;when it reloads, and on a resident the broadcast is the only source there is.
;Redrawn only when it has actually changed, because a redraw loses whichever
;line was selected.
ext_FleetServerWatch() {
	global FleetServersGui, FleetServersPath, FleetServerStamp, ext_fleetServerGen
	local stamp

	if !(IsSet(FleetServersGui) && IsObject(FleetServersGui))
		return
	stamp := ext_fleetServerHost()
		? (FileExist(FleetServersPath)
			? FileGetTime(FleetServersPath, "M") "/" FileGetSize(FleetServersPath)
			: "none")
		: ext_fleetServerGen
	if (stamp = FleetServerStamp)
		return
	FleetServerStamp := stamp
	ext_FleetServerDraw()
}

ext_FleetServerDraw() {
	global FleetServersGui, FleetServers, FleetServerSlot
	local list, keys := [], slot, e, editable := ext_fleetServerHost()

	if !(IsSet(FleetServersGui) && IsObject(FleetServersGui))
		return
	list := ext_fleetServerList()
	FleetServersGui["FleetServerList"].Delete()
	for slot, _ in list
		keys.Push(slot)
	roster_Sort(keys)
	for _, slot in keys {
		e := list[slot]
		;the main says so in the table rather than being sorted to the top: the
		;slot order is what the file shows, and two orders would not match
		FleetServersGui["FleetServerList"].Add(
			, e.name ((e.kind = "main") ? "  (main)" : "")
			, ext_FleetOr(e.link, "no link set")
			, ext_fleetOwnerName(e.owner))
	}
	Loop 3
		FleetServersGui["FleetServerList"].ModifyCol(A_Index, "AutoHdr")

	try FleetServersGui["FleetServerNote"].Text := editable
		? "Set here once. The coordinator hands the list to every macro in the fleet."
		: "Shown as the fleet broadcast it. Change it on the macro that hosts the fleet."
	for _, slot in ["FleetServerName", "FleetServerLink", "FleetServerOwner"
		, "FleetServerUpdate", "FleetServerAdd", "FleetServerDel"]
		try FleetServersGui[slot].Enabled := editable
	;a line that is no longer there must not stay in the edit fields, where
	;Update would write it back
	if !list.Has(FleetServerSlot)
		ext_FleetServerFields("", "", 0)
}

;The three controls that describe one server, filled or emptied together.
ext_FleetServerFields(name, link, owner) {
	global FleetServersGui, FleetServerOwnerRows
	local i, row

	try FleetServersGui["FleetServerName"].Value := name
	try FleetServersGui["FleetServerLink"].Value := link
	for i, row in FleetServerOwnerRows
		if (row = owner) {
			try FleetServersGui["FleetServerOwner"].Value := i
			return
		}
	try FleetServersGui["FleetServerOwner"].Value := 1
}

ext_FleetServerSelect(ctrl, item, selected) {
	global FleetServers, FleetServerSlot, FleetServersGui
	local keys := [], slot, e

	if (!selected || !item)
		return
	for slot, _ in FleetServers
		keys.Push(slot)
	roster_Sort(keys)
	if (item > keys.Length)
		return
	FleetServerSlot := keys[item]
	e := FleetServers[FleetServerSlot]
	;the dropdown is rebuilt here because accounts arrive while this window is
	;open - a server cannot be given to an account the list has never offered
	try FleetServersGui["FleetServerOwner"].Delete()
	try FleetServersGui["FleetServerOwner"].Add(ext_fleetOwnerChoices())
	ext_FleetServerFields(e.name, e.link, e.owner)
}

ext_FleetServerSave(*) {
	global FleetServersGui, FleetServers, FleetServersPath, FleetServerSlot
	global FleetServerOwnerRows
	local pick

	if (!FleetServerSlot || !FleetServers.Has(FleetServerSlot)) {
		MsgBox "Pick a server in the list first.", "Fleet", 0x40030
		return
	}
	FleetServers[FleetServerSlot].name := Trim(FleetServersGui["FleetServerName"].Value)
	FleetServers[FleetServerSlot].link := Trim(FleetServersGui["FleetServerLink"].Value)
	pick := FleetServersGui["FleetServerOwner"].Value
	FleetServers[FleetServerSlot].owner := ((pick >= 1) && (pick <= FleetServerOwnerRows.Length))
		? FleetServerOwnerRows[pick]
		: 0
	if (FleetServers[FleetServerSlot].name = "")
		FleetServers[FleetServerSlot].name := "server " FleetServerSlot
	ext_fleetSaveServers()
	ext_FleetServerDraw()
	ext_FleetServerSummary()
}

ext_FleetServerAdd(*) {
	global FleetServers, FleetServersPath
	local slot

	slot := servers_NextSlot(FleetServers)
	FleetServers[slot] := { slot: slot, name: "Reserve " servers_Reserves(FleetServers) + 1
		, link: "", owner: 0, kind: "reserve" }
	ext_fleetSaveServers()
	ext_FleetServerDraw()
	ext_FleetServerSummary()
}

ext_FleetServerRemove(*) {
	global FleetServers, FleetServersPath, FleetServerSlot

	if (!FleetServerSlot || !FleetServers.Has(FleetServerSlot))
		return
	if (FleetServers[FleetServerSlot].kind = "main") {
		MsgBox "The main server cannot be removed - a fleet has to work somewhere."
			. "`n`nPaste a different link into it instead.", "Fleet", 0x40030
		return
	}
	if (MsgBox("Remove " FleetServers[FleetServerSlot].name "?", "Fleet", 0x40024) != "Yes")
		return
	FleetServers.Delete(FleetServerSlot)
	FleetServerSlot := 0
	ext_fleetSaveServers()
	ext_FleetServerDraw()
	ext_FleetServerSummary()
}

;The accounts the owner dropdown offers, and the row each entry means.
;
;"nobody" first, because no owner named is the normal state until somebody says
;so - and a dropdown whose first entry is an account makes that account look
;chosen when nothing has been.
;
;From the roster file where there is one, and from what was broadcast where
;there is not: the file is only populated on the machine that hosts.
ext_fleetOwnerChoices() {
	global FleetRoster, ext_fleetPeers, FleetServerOwnerRows
	local row, e, names := ["nobody"], keys := [], source

	FleetServerOwnerRows := [0]
	source := (IsSet(FleetRoster) && FleetRoster.Count) ? FleetRoster : ext_fleetPeers
	for row, _ in source
		keys.Push(row)
	roster_Sort(keys)
	for _, row in keys {
		names.Push(ext_fleetOwnerName(row))
		FleetServerOwnerRows.Push(row)
	}
	return names
}

;What to call the account that owns a server. In one place, so the table, the
;dropdown and the detail panel never disagree about an account's name.
ext_fleetOwnerName(row) {
	global FleetRoster, ext_fleetPeers

	if !row
		return "nobody"
	if (IsSet(FleetRoster) && FleetRoster.Has(row))
		return (FleetRoster[row].user != "") ? FleetRoster[row].user : FleetRoster[row].name
	if ext_fleetPeers.Has(row)
		return ext_FleetSeatName(ext_fleetPeers[row])
	return "row " row
}

;The servers one account owns, named. An account can own several, which is the
;thing the roster flag was unable to say.
ext_fleetOwnedBy(row) {
	global ext_fleetServers
	local slot, f, out := ""

	for slot, f in ext_fleetServers
		if (row && (ext_FleetNum(f, "owner") = row))
			out .= (out != "" ? ", " : "") ext_FleetOr(ext_FleetCell(f, "name"), "server " slot)
	return out
}

;Section two of the setup window, in two lines: where the main is, and how many
;reserves there are. The link is shown rather than hidden, because a link that
;is wrong is the thing that goes wrong and it has to be recognisable at a
;glance.
ext_FleetServerSummary() {
	global FleetSetupGui
	local list, main, n

	if !(IsSet(FleetSetupGui) && IsObject(FleetSetupGui))
		return
	list := ext_fleetServerList(), main := servers_Main(list), n := servers_Reserves(list)
	try FleetSetupGui["FleetServerSummary"].Text := "Main: "
		. ((main && (main.link != "")) ? ext_FleetShort(main.link, 72) : "no link set")
		. "`n" (n ? n " reserve" ((n > 1) ? "s" : "") : "No reserves")
		. ((main && main.owner) ? "  -  main owned by " ext_fleetOwnerName(main.owner) : "")
}

;A private server link is longer than any space it is given, and the half worth
;recognising is the end - the link code. So the middle goes, never the tail.
ext_FleetShort(text, n) {
	local half

	if (StrLen(text) <= n)
		return text
	half := (n // 2) - 3
	return SubStr(text, 1, half) " ... " SubStr(text, -half)
}

;An edit made here is the next version of the configuration, so it says so.
;
;Without the bump the coordinator would reload the file, find the same version
;on different contents, and tell the fleet nothing had changed - it does catch
;that and bump it itself, but a moment later and under its own name. Doing it
;here keeps the edit attributed to the macro that made it, which is what
;settles a tie between two edits made on both sides of a split.
ext_fleetSaveRoster() {
	global FleetRoster, FleetRosterPath, FleetRow, ext_fleetRosterDisk
	local ver := fleet_ConfigVersion(FleetRosterPath)

	ext_fleetRosterDisk := { version: ver.version + 1, by: FleetRow }
	if roster_Save(FleetRosterPath, FleetRoster
		, ext_fleetRosterDisk.version, ext_fleetRosterDisk.by)
		return 1
	ext_fleetProblem("could not write " FleetRosterPath " - the change was lost")
	MsgBox "The change could not be written to`n`n" FleetRosterPath
		. "`n`nIt has not been saved. Check the folder is writable.", "Fleet", 0x40010
	return 0
}
ext_fleetSaveServers() {
	global FleetServers, FleetServersPath, FleetRow, ext_fleetServerDisk
	local ver := fleet_ConfigVersion(FleetServersPath)

	ext_fleetServerDisk := { version: ver.version + 1, by: FleetRow }
	if servers_Save(FleetServersPath, FleetServers
		, ext_fleetServerDisk.version, ext_fleetServerDisk.by)
		return 1
	ext_fleetProblem("could not write " FleetServersPath " - the change was lost")
	MsgBox "The change could not be written to`n`n" FleetServersPath
		. "`n`nIt has not been saved. Check the folder is writable.", "Fleet", 0x40010
	return 0
}

;--- the roster editor -------------------------------------------------------

ext_FleetRosterDraw() {
	global FleetSetupGui, FleetRoster, FleetRosterOrder
	local keys := [], row, e, name

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
		FleetSetupGui["FleetRosterList"].Add(, e.name, e.role, e.user)
	}
	Loop 3
		FleetSetupGui["FleetRosterList"].ModifyCol(A_Index, "AutoHdr")

	;The table is live on every macro now - it is read from the replica, which
	;the coordinator keeps up to date. Editing is not: an edit here writes the
	;local file, and the next generation of the replica writes straight over it.
	;Better to refuse than to accept a change and quietly lose it. Routing the
	;edit to the coordinator is what makes this editable everywhere, and that
	;is not written yet.
	for _, name in ["FleetEditName", "FleetEditRole", "FleetEditUser"]
		try FleetSetupGui[name].Enabled := ext_fleetServerHost()
	for _, name in ["FleetRosterUpdate", "FleetRosterRemove"]
		try FleetSetupGui[name].Enabled := ext_fleetServerHost()
	try FleetSetupGui["FleetRosterNote"].Text := ext_fleetServerHost()
		? ""
		: "Changed on " ext_FleetOr(ext_fleetCoordWho(), "whichever macro coordinates")
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
}

;Editing only. Accounts arrive by binding, so there is no Add here - a row this
;list has never seen would be a row no macro answers to.
ext_FleetRosterSave(*) {
	global FleetSetupGui, FleetRoster, FleetRosterPath, FleetEditRow

	if (!FleetEditRow || !FleetRoster.Has(FleetEditRow)) {
		MsgBox "Pick an account in the list first.", "Fleet", 0x40030
		return
	}
	FleetRoster[FleetEditRow].name := Trim(FleetSetupGui["FleetEditName"].Value)
	FleetRoster[FleetEditRow].role := FleetSetupGui["FleetEditRole"].Text
	FleetRoster[FleetEditRow].user := Trim(FleetSetupGui["FleetEditUser"].Value)
	if (FleetRoster[FleetEditRow].name = "")
		FleetRoster[FleetEditRow].name := "row " FleetEditRow
	ext_fleetSaveRoster()
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
	ext_fleetSaveRoster()
	FleetEditRow := 0
	ext_FleetRosterDraw()
}

;Port, grace and a hand-typed address. Tucked away because a fleet on an
;ordinary network needs none of them, and a window that shows everything at
;once is a window nobody reads.
ext_FleetAdvanced(*) {
	global FleetSetupGui, FleetAdvGui, FleetPort, FleetGraceSecs, FleetAddress
	global FleetFollowOwn, FleetFollowBoost, FleetFollowQuest, FleetFollowPlanter
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

	;Which trips the followers are dragged along on - see ext_fleetFollowReport.
	;Here rather than in the Fleet tab because it is a decision taken once for
	;a whole setup, and because only one macro in the fleet is affected by it.
	;
	;The title names the two roles instead of saying "residents", which read as
	;every account that is not the main - and guid and atk never follow.
	FleetAdvGui.SetFont("s8 cDefault Bold", "Tahoma")
	FleetAdvGui.Add("GroupBox", "x12 y222 w360 h62"
		, "Fuzzy and tad accounts follow the main into")
	FleetAdvGui.SetFont("s8 cDefault Norm", "Tahoma")
	ext_FleetFollowBox("FleetFollowOwn", 24, 240, "Its own field", FleetFollowOwn)
	ext_FleetFollowBox("FleetFollowBoost", 196, 240, "The boosted field", FleetFollowBoost)
	ext_FleetFollowBox("FleetFollowQuest", 24, 260, "A quest field", FleetFollowQuest)
	ext_FleetFollowBox("FleetFollowPlanter", 196, 260, "A planter field", FleetFollowPlanter)
	FleetAdvGui.SetFont("c808080")
	FleetAdvGui.Add("Text", "x12 y290 w360"
		, "Only fuzzy and tad follow - a guid and an atk have their`nown work at their own times. Set this on the macro that leads.")
	FleetAdvGui.SetFont("cDefault")

	;The bench is here rather than on the Fleet tab because it is a thing you
	;reach for when something is wrong, and because it has no business being one
	;click from the panel somebody watches all night.
	FleetAdvGui.SetFont("c808080")
	FleetAdvGui.Add("Text", "x12 y326 w360"
		, "The test bench stands in for the other macros, so a feature can be`ntried without setting them all up. Its own port and its own files.")
	FleetAdvGui.SetFont("cDefault")
	FleetAdvGui.Add("Button", "x12 y360 w170 h24", "Open the test bench")
		.OnEvent("Click", ext_FleetBench)

	FleetAdvGui.Add("Button", "x292 y360 w80 h24", "Close").OnEvent("Click", ext_FleetAdvClose)
	FleetAdvGui.Show("w384 h398")
}

;One of the four, saved the way every other setting in the macro is.
ext_FleetFollowBox(name, x, y, caption, value) {
	global FleetAdvGui
	local GuiCtrl

	(GuiCtrl := FleetAdvGui.Add("CheckBox", "x" x " y" y " w160 h18 v" name
		" Checked" value, caption)).Section := "Fleet"
	GuiCtrl.OnEvent("Click", nm_saveConfig)
}

;Open the bench, which is its own process. Not included into the macro: it
;listens and connects on a port of its own, and a tool that shares this
;process could reach the real fleet's state by accident.
ext_FleetBench(*) {
	global exe_path32
	local pid := 0

	try
		Run '"' exe_path32 '" /script "' A_WorkingDir '\submacros\FleetBench.ahk"'
			, , , &pid
	catch as e {
		ext_fleetProblem("could not open the test bench: " e.Message)
		MsgBox "The test bench would not start.`n`n" e.Message, "Fleet", 0x40010
		return 0
	}
	return pid
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
		left := ext_FleetNum(p, "until") - nowUnix()
		if ((left > 0) && (!best || (left < best)))
			best := left, who := ext_FleetCell(p, "name")
	}
	if best
		return "Star " Floor(best / 60) ":" Format("{:02}", Mod(best, 60)) " (" who ")"
	return "No star running"
}
