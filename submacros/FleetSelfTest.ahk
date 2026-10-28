#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon

;An end-to-end check of the Fleet coordinator.
;
;It launches a real coordinator on a test port, connects two pretend macros to
;it, and watches whether the roster reaches both of them. Run it the same way as
;the socket test:
;
;	.\submacros\AutoHotkey64.exe /script .\submacros\FleetSelfTest.ahk
;
;Fifty-one things are checked, each because it is a way the design could be wrong
;rather than merely broken:
;
;	1. both macros appear in the roster        the coordinator keeps a roster
;	2. each macro sees the other               it is broadcast, not just held
;	3. "fuzzy 1" keeps its space               field encoding survives the wire
;	4. a wrong secret is refused               the only door has a lock on it
;	5. the main's field becomes a GOTO         residents can follow the main
;	6. a late resident is sent the field       following survives a restart
;	7. an unreadable roster strikes nobody     a race cannot empty the fleet
;	8. a ping is answered and timed            the panel can show a round trip
;	9. a macro that leaves is removed          leaving differs from crashing
;	10. a second coordinator is refused        the port is the lock
;	11. a second setup reuses its own row      no ghost rows in the roster
;	12. the server list reaches a macro        servers are shared, not retyped
;	13. a deleted server disappears            a list that shrinks still converges
;	14. a row nobody has seen is broadcast     every macro can hold a replica
;	15. a refusal says whose problem it is     a recoverable one is retried
;	16. a stale configuration cannot win       a late macro cannot undo the rest
;	17. a better configuration is taken        the fleet climbs to the best copy
;	18. a tie keeps one and files the other    nothing is lost deciding
;	19. a roster cleared on purpose is applied  a wipe is not an unreadable file
;	20. a macro's own version reaches the fleet a divergence has somewhere to show
;	21. a bench configuration never wins       a test tool cannot replace a fleet
;	22. and not over the wire either           the same rule, between processes
;	23. an empty id does not build a path      a fleet with no identity is not a folder
;	24. a path with a separator in it is out   the id arrives from the wire
;	25. two fleets are two folders             the whole point of the change
;	26. an id never starts with a digit        an ini would eat the leading zero
;	27. an old fleet's id is its fingerprint   every machine agrees without being told
;	28. binding hands the identity over        a newcomer writes in the right folder
;	29. only the mandated row may command      standing in is not being in charge
;	30. a mandate nobody holds passes on       an account that never comes back
;	31. a macro without it is refused          asking is not the same as being owed
;	32. the mandated row hands the job on      and the old process stands down
;	33. the binding door refuses out loud      a silent no looks like a yes
;	34. the beacon says where and which fleet  discovery had no check at all
;	35. and whether the door is open           that flag is the join button
;	36. another fleet's macro is told so       and does not give up for ever
;	37. an unknown identity falls through      an older macro behaves as before
;	38. and the wire says so, not finally      a wrong door is not a closed one
;	39. an oversized log rotates on line one   a quiet macro's file stays small
;	40. the main's field is on the roster      a missed GOTO heals within a beat
;	41. only a follower leaves for the main    and never for the field it is in
;	42. a fleet left behind loses its coordinator  a new fleet can have the port
;	43. and nobody else's                      another fleet's is left running
;	44. a second main is refused at the door   the followers have one leader
;	45. and the rule names the main it found   so the refusal can say who
;	46. an edit made anywhere beats both copies its own and the fleet's
;	47. a roster with two mains is recognised  so a hand-up cannot sneak one in
;	48. a follower away from the main shows    the panel says what is wrong
;	49. a higher term's beacon wins            a stale coordinator loses its macros
;	50. durations become this machine's times  two clocks never meet
;	51. and the coordinator sends durations    the wire carries no clock
;
;Twenty-one and twenty-two guard a path nobody would notice until it had
;happened. Point a real macro at the test bench and it replicates the bench's
;configuration into its own files; point it back at the real fleet and it hands
;that configuration up, and if the version happens to be the higher one the
;real coordinator takes it. A tool built to protect the fleet would have
;replaced its roster. So a configuration the bench made loses to one it did
;not, whatever the versions say, in the comparison and on the wire.
;
;Twenty-nine to thirty-three are the mandate. A coordinator is a process any macro
;can start, so "who may give it orders" was answered by "whoever launched
;it" - and after a failover that is a macro which stood in for five minutes
;and now holds the binding door. The mandate travels with the order instead,
;and its escape hatch is the roster rather than a clock: an account removed
;from the fleet can no longer hold the say over it.
;
;Twenty-three to twenty-eight are the folder per fleet. A macro belongs to the
;real fleet and to the bench over its life, and the two configurations used to
;share one pair of files - so binding to the bench wrote over the real roster.
;Each fleet now owns a folder named by its identity, which is handed over at
;binding beside the secret.
;
;Twenty-three and twenty-four are the dangerous half. The id reaches a macro
;from the wire, and both an empty one and one with a separator in it would
;decide which folder that macro writes its configuration into. Twenty-six is
;the trap that nearly shipped: these are stored in an ini, nm_importConfig
;turns anything IsInteger accepts into an Integer, and an identity of 00123456
;would have come back as 123456 - a folder name that stopped matching the one
;it was written as, about once in every two hundred fleets.
;
;Nineteen is the other half of the guard behind seven. An empty roster has to
;be refused when it is a file caught mid-write and obeyed when somebody cleared
;the table, and the version is the only thing that tells those apart: one
;carries the next version, the other carries none at all.
;
;Sixteen to eighteen are the versioning, and sixteen is the one that matters.
;Two macros that were disconnected can reconnect before the rest, one of them
;takes over, and it takes over holding the copy it had - which is older than
;the copy everybody else holds. Nothing in a file's timestamp can tell those
;apart: a replica is written when it arrives, so the stale machine's file is
;the one with the newer timestamp. Without a version in the file, the stale
;configuration spread and overwrote every good copy in the fleet.
;
;Fourteen and fifteen are the two halves of surviving the loss of the machine
;that coordinates. The configuration used to live only in that machine's
;settings folder, so electing a replacement produced a coordinator with an
;empty roster, which refused every macro - and a refusal was treated as final,
;so the whole fleet left for good. Now the configuration is broadcast, every
;macro writes a replica of it, and a refusal that a coordinator might recover
;from is marked as one.
;
;Thirteen is the one worth spelling out. Nothing in the protocol says "delete a
;server": each frame carries the generation the list is on, and a macro that
;sees a generation it has not seen throws its copy away before taking the
;frames that follow. So a list that shrank converges in one beat, with no
;transaction to be caught half-applied - the same reason the roster broadcasts
;state rather than deletions.
;
;Ten is the one that was never going to be noticed by reading the code. Windows
;lets two processes listen on one port when SO_REUSEADDR is set, so both
;coordinators of a handover ran at once and the connections were split between
;them - and a macro, seeing only the one that answered it, could not tell. The
;term number was supposed to settle that and cannot: neither half ever hears
;the other's term.
;
;Checks 6 and 7 are the two that cost real bugs. Six is the resident that
;reconnects: the field is only forwarded when it changes, so a resident that
;came back was told nothing until the main moved - which on a macro left on one
;field is never. Seven is the roster file read while it was being written: a
;reload that came back empty struck every account off and sent the whole fleet
;a refusal, from nothing worse than two processes sharing one file.
;
;Checks 8 and 9 need two coordinator beats to land - a round trip measured on
;one beat is broadcast on the next - so the test runs for a few seconds longer
;than the others would need.
;
;Thirty-six and thirty-seven are the fault that the folder per fleet created.
;A macro tries 127.0.0.1 first, whatever fleet is listening there, and two
;fleets on one machine are now a supported arrangement - so a macro regularly
;knocks on a stranger's door on its own machine. The answer was "bad secret",
;marked final, and a final refusal makes a macro let go of its fleet and stop
;looking. Knocking on the wrong door cost it its own fleet.
;
;Thirty-four and thirty-five are the discovery beacon, which until now nothing
;checked. It is how a macro finds a coordinator at all - without it an address
;has to be typed on every machine, and it would be wrong the moment the router
;hands out a new lease. Its open flag is what turns the join button on, and its
;label is what stops somebody joining a test fleet believing it was theirs.
;
;It leaves nothing running: the coordinator it started is closed at the end.

#Include "%A_ScriptDir%\..\lib"
#Include "Socket.ahk"
#Include "FleetProtocol.ahk"
#Include "FleetRoster.ahk"
#Include "FleetServers.ahk"

PORT := 47655
SECRET := "selftest"

;The coordinator only admits rows that exist in a roster, so the test brings
;its own. It goes in a file of its own rather than the real one: a self-test
;that overwrites your fleet in order to prove the fleet works is no test.
ROSTER := A_ScriptDir "\..\settings\fleet_roster_selftest.ini"
;The coordinator puts its log beside whatever roster it was given, so this is
;this run's log and nobody else's - which is what makes it safe to delete and
;meaningful to read back.
;
;Not named LOG: AutoHotkey identifiers are case insensitive, and Log is the
;built-in logarithm. The collision is not only with functions of our own.
LOGFILE := RegExReplace(ROSTER, "i)\.ini$", ".log")
try FileDelete LOGFILE
;and its own server list, derived from the roster path exactly as the
;coordinator derives it - two of them, so one is left after a deletion
SERVERS := RegExReplace(ROSTER, "i)\.ini$", "_servers.ini")
;the link carries a space, a percent and an equals sign on purpose: all three
;are characters the wire protocol has to survive, and a real private server
;link contains at least the last of them
servers_Save(SERVERS, Map(1, { slot: 1, name: "Main", kind: "main", owner: 2
		, link: "https://roblox.test/main?code=a b%c" }
	, 2, { slot: 2, name: "Reserve", kind: "reserve", owner: 3
		, link: "https://roblox.test/reserve" }), 3, 1)
;row 3 exists in the roster from the start but does not connect until the main
;has already reported its field - which is what a resident restarting looks like
roster_Save(ROSTER, Map(1, { row: 1, name: "main", role: "main", user: ""
		, machine: "selftest" }
	, 2, { row: 2, name: "fuzzy 1", role: "fuzzy", user: ""
		, machine: "selftest" }
	, 3, { row: 3, name: "fuzzy 2", role: "fuzzy", user: "fuzzy2"
		, machine: "selftest" })
	;version five rather than one, so there is room below it for a stale copy
	;to be offered and refused
	, 5, 1)

;The handover gets a coordinator of its own, on its own port and its own
;roster. Everything else here shares one, and this is the one check whose
;whole point is that the coordinator stops - running it against the shared
;one would end the test two thirds of the way through.
HANDPORT := 47656
HANDROSTER := A_ScriptDir "\..\settings\fleet_roster_handover.ini"
roster_Save(HANDROSTER, Map(1, { row: 1, name: "main", role: "main", user: ""
		, machine: "selftest" }
	, 2, { row: 2, name: "fuzzy 1", role: "fuzzy", user: ""
		, machine: "selftest" }), 1, 1)
try FileDelete RegExReplace(HANDROSTER, "i)\.ini$", ".log")
handPid := 0, hand1 := 0, hand2 := 0
;Two coordinators started from this folder for two different fleets, and one
;of them stopped by fleet id - the stray a macro leaves behind when it creates
;a new fleet or joins another. Measured: the old one kept the port, the new
;fleet had no coordinator, and its macros were turned away for minutes.
strayPid := 0, keepPid := 0, strayStopped := -1
handRefused := ""           ;what row 2 was told when it asked for a handover
handDoor := ""              ;and when it tried to open the binding door
;The beacon, which had never been checked by anything. It is the whole of
;discovery - a macro that cannot hear one has to be given an address by hand -
;and it is also what the join window reads to decide whether a fleet is
;accepting macros and what it calls itself.
beaconSeen := Map()
beaconSock := sock_UdpListen(HANDPORT + 1, OnBeacon)
handTold := Map()           ;the order, as each client received it

coordPid := 0, rivalPid := 0, finished := 0
boundRow := -1              ;which row a second setup of row 3 was handed back
boundFid := ""              ;and which fleet it was told it had joined
clientD := 0, clientE := 0
secondMainWhy := ""         ;what a macro binding as a second main was told
srvGen := ""                ;the generation of the server list last seen
srv := Map()                ;the server list as the main macro holds it
srvMainLink := "", srvMainOwner := -1
myCv := -1                  ;the version the main said it held, come back round
goneAtWipe := -1            ;how many rows had been struck before the wipe
cfg := Map()                ;the roster as configured, as the main macro holds it
cfgGen := "", cfgWant := 0
;noted as they go past rather than read back at the end: row 2 leaves the fleet
;later in this test and the roster legitimately shrinks, so what was true while
;three accounts were configured has to be caught while it is true
cfgMost := 0                ;the most rows a single generation ever promised
cfgUnseen := ""             ;a configured row that had not connected when it arrived
cfgLowVer := 9999           ;the lowest version the coordinator ever served
cfgHighVer := 0             ;and the highest, which a bench must never reach
cfgTookUp := 0              ;the version at which the handed-up roster came back
byeFinal := Map()           ;what each refusal said about being final
seenBy := Map()             ;client label -> Map of row -> roster frame it received
refused := ""               ;what the bad-secret connection was told
otherWhy := ""              ;and what a macro of another fleet was told

Run '"' A_AhkPath '" /script "' A_ScriptDir '\Fleet.ahk" ' PORT ' ' SECRET ' 1 1 "' ROSTER '"'
	, , , &coordPid
;the coordinator has to bind before anyone can knock
Sleep 1200

seenBy["main"] := Map(), seenBy["fuzzy"] := Map(), seenBy["late"] := Map()
gotoField := "", fieldSent := 0
lateField := ""             ;what a resident joining afterwards was told
leadOnRoster := ""          ;the main's field, as the late resident read it off the roster
pinged := 0                 ;did the fuzzy macro get asked how fast it answers
goneRows := Map()           ;every row the main was told had left
bothSeen := Map("main", 0, "fuzzy", 0)   ;each client saw the whole roster, at some point
row2 := ""                  ;the last ROSTER frame about row 2, kept for the report
rttSeen := -1               ;a round trip the coordinator actually measured
clientC := 0
clientA := sock_Connect("127.0.0.1", PORT, OnA)
clientB := sock_Connect("127.0.0.1", PORT, OnB)
clientBad := sock_Connect("127.0.0.1", PORT, OnBad)
;a macro that belongs to a different fleet, which is what every macro looks
;like to its own loopback on a machine running two of them
clientOther := sock_Connect("127.0.0.1", PORT, OnOther)

;the late resident, long after the main said where it was farming
SetTimer Late, -5000
;the second coordinator, which must not get the port. It gives up after a few
;seconds of retrying, so it is started early enough to have finished by the
;time the report is written.
SetTimer Rival, -6500
;the host opens its door, and an account that already has a row asks for one
SetTimer Open, -6000
SetTimer Rebind, -6800
SetTimer SecondMain, -7100
;a server deleted, late enough that the first list has certainly arrived
SetTimer DropServer, -9000
;the main says which configuration it holds, which should come back to it
SetTimer SayVersion, -8500
;And the roster cleared on purpose, which is not the same as an unreadable one.
;Late enough to land on a beat of its own: it strikes every row off, so a beat
;that both wiped and carried something else would deliver the something else to
;nobody - which is how this timing was found.
SetTimer Wipe, -14000
;a stale configuration offered, then a better one, then one that ties
SetTimer HandUpStale, -7500
SetTimer HandUpBetter, -10500
SetTimer HandUpTie, -11000
SetTimer HandUpBench, -11200
;a macro with the right secret and a row that is not in the roster, which is
;what every macro looks like to a coordinator that came up without one
SetTimer Stranger, -9500
;the roster file as a reader catches it mid-write
SetTimer Blank, -8000
;the fuzzy macro leaves on purpose, late enough that its measured round trip
;has already been broadcast and can be checked
SetTimer Leave, -11500
;The handover, on its own coordinator: row 2 asks and is refused, then row 1
;asks and is obeyed. Seven and a half seconds all told - a bind, two clients,
;a pause long enough for a beacon to go out with the door open, the order, and
;two and a half more before the process stands down. The report waits for all
;of it: at twenty-two seconds it was reading ProcessExist half a second before
;the process went, and calling a handover that worked a failure.
SetTimer Handover, -15000
SetTimer Stray, -3000
SetTimer Report, -25000
return

;Every beacon from the handover coordinator, kept by field so the report can
;say which one was missing rather than only that something was.
OnBeacon(s, event, data, from) {
	global beaconSeen
	local frame := fleet_Parse(data), name

	if (!frame || (frame.verb != "FLEET"))
		return
	for _, name in ["port", "id", "open", "host", "size", "label", "term", "row"]
		beaconSeen[name] := fleet_Field(frame, name)
	beaconSeen["from"] := from
}

;--- the handover -----------------------------------------------------------
;
;A coordinator is a process any macro can start, so "who may give it orders"
;used to be answered by "whoever launched it" - and after a failover that is a
;macro which stood in for five minutes. The mandate is passed explicitly here,
;as row 1, so row 2 is a macro in the fleet that does not hold the say.
;Their own ports, rosters and ids, so neither can touch the fleet under test.
Stray(*) {
	global strayPid, keepPid, SECRET

	Run '"' A_AhkPath '" /script "' A_ScriptDir '\Fleet.ahk" 47658 ' SECRET ' 1 1 "'
		. A_ScriptDir '\..\settings\fleet_roster_stray.ini" "fstrayold" 1', , , &strayPid
	Run '"' A_AhkPath '" /script "' A_ScriptDir '\Fleet.ahk" 47660 ' SECRET ' 1 1 "'
		. A_ScriptDir '\..\settings\fleet_roster_keep.ini" "fstraykeep" 1', , , &keepPid
	SetTimer StrayStop, -2500
}
StrayStop(*) {
	global strayStopped

	strayStopped := fleet_StopCoordinators(RegExReplace(A_ScriptDir, "\\[^\\]+$"), "fstrayold")
}

Handover(*) {
	global HANDPORT, SECRET, HANDROSTER, handPid

	Run '"' A_AhkPath '" /script "' A_ScriptDir '\Fleet.ahk" ' HANDPORT
		;the eighth argument is what the fleet calls itself in a join window - a
		;bench fleet on your own machine otherwise looks exactly like the real one
		. ' ' SECRET ' 1 1 "' HANDROSTER '" fhandover 1 "a test fleet"'
		, , , &handPid
	SetTimer HandoverJoin, -1200
}
HandoverJoin(*) {
	global HANDPORT, hand1, hand2

	hand1 := sock_Connect("127.0.0.1", HANDPORT, OnHand1)
	hand2 := sock_Connect("127.0.0.1", HANDPORT, OnHand2)
	SetTimer HandoverWrongRow, -1200
}
;Row 2 asking. It is in the roster and connected, so nothing but the mandate
;stands between it and the fleet changing hands.
HandoverWrongRow(*) {
	global hand1, hand2

	;the binding door is the same privilege, and it used to be refused in
	;silence - which made the button that asks for it look as though it worked
	sock_SendLine(hand2, fleet_Frame("OPEN", Map("secs", 60)))
	sock_SendLine(hand2, fleet_Frame("HOST", Map("row", 2)))
	;and from the row that may: the beacon has to be caught with its door open,
	;because that flag is what turns the join button on
	sock_SendLine(hand1, fleet_Frame("OPEN", Map("secs", 60)))
	SetTimer HandoverRightRow, -2600
}
HandoverRightRow(*) {
	global hand1

	sock_SendLine(hand1, fleet_Frame("HOST", Map("row", 2)))
}
OnHand1(s, event, data) {
	HandHandle(1, "main", s, event, data)
}
OnHand2(s, event, data) {
	HandHandle(2, "fuzzy 1", s, event, data)
}
HandHandle(row, name, s, event, data) {
	global SECRET, handRefused, handTold, handDoor
	local frame

	if (event = "connect") {
		if (data = "")
			sock_SendLine(s, fleet_Frame("HELLO", Map("row", row, "name", name
				, "role", (row = 1) ? "main" : "fuzzy", "secret", SECRET
				, "machine", A_ComputerName)))
		return
	}
	if ((event != "line") || !(frame := fleet_Parse(data)))
		return
	if (frame.verb = "FAIL") {
		if (fleet_Field(frame, "verb") = "OPEN")
			handDoor := fleet_Field(frame, "why")
		else
			handRefused := fleet_Field(frame, "why")
	}
	else if (frame.verb = "TAKEOVER")
		;both clients must hear it: the preference for who coordinates by
		;default lives on every macro, and one that still named itself would
		;reclaim the job and undo the handover
		handTold[row] := fleet_Field(frame, "row")
			. "/" fleet_Field(frame, "mandate")
}

;A resident arriving after everyone else, which is a resident that crashed and
;came back. It should be told where the hive is standing without the main
;having to change field for its benefit.
Late(*) {
	global clientC

	clientC := sock_Connect("127.0.0.1", PORT, OnC)
}

;Only the host may open the door, and clientA is the host - row 1 is what the
;coordinator was started with.
Open(*) {
	global clientA

	sock_SendLine(clientA, fleet_Frame("OPEN", Map("secs", 60)))
}

;Row 3 setting itself up a second time, which is what a settings reset or a
;reinstall looks like from here. It should be handed row 3 back. Minting a
;fourth row would leave row 3 in the roster offline for ever, and an offline
;row is a row somebody goes looking for a reason behind.
;An account binding as main while row 1 already is. Two mains would give the
;followers two fields to follow and cut every trip short.
SecondMain(*) {
	global PORT
	sock_Connect("127.0.0.1", PORT, OnSecondMain)
}
OnSecondMain(s, event, data) {
	global secondMainWhy
	local frame

	if (event = "connect") {
		if (data = "")
			sock_SendLine(s, fleet_Frame("BIND", Map("name", "another main"
				, "role", "main", "user", "secondmain", "machine", "a third machine")))
		return
	}
	if ((event = "line") && (frame := fleet_Parse(data)))
		secondMainWhy := frame.verb ": " fleet_Field(frame, "why")
}

Rebind(*) {
	global clientD

	clientD := sock_Connect("127.0.0.1", PORT, OnRebind)
}

OnRebind(s, event, data) {
	global boundRow, boundFid
	local frame

	if (event = "connect") {
		if (data = "")
			sock_SendLine(s, fleet_Frame("BIND", Map("name", "fuzzy 2"
				, "role", "fuzzy", "user", "fuzzy2", "machine", "a new machine")))
		return
	}
	if ((event = "line") && (frame := fleet_Parse(data)) && (frame.verb = "BOUND")) {
		boundRow := Integer(fleet_Field(frame, "row", 0))
		;the fleet's identity rides along with the secret, so a newcomer knows
		;which folder its copy of this configuration belongs in
		boundFid := fleet_Field(frame, "fid")
	}
}

;A second coordinator on the same port, which is what every handover starts.
;It must be refused: listening alongside the first would split the fleet
;between two processes that no macro can see at the same time.
;A macro of another fleet entirely, knocking on this one's door. It carries a
;secret that is wrong here, because a macro of another fleet always does - the
;point is that this is not what a wrong secret means, and that answering it as
;though it were costs that macro its own fleet.
OnOther(s, event, data) {
	global byeFinal, otherWhy
	local frame

	if (event = "connect") {
		if (data = "")
			sock_SendLine(s, fleet_Frame("HELLO", Map("row", 1
				, "name", "a stranger", "secret", "not ours"
				, "fid", "fsomewhereelse", "machine", "another machine")))
		return
	}
	if ((event = "line") && (frame := fleet_Parse(data))
		&& (frame.verb = "BYE")) {
		otherWhy := fleet_Field(frame, "why")
		byeFinal["another fleet"] := fleet_Field(frame, "final", "missing")
	}
}

Rival(*) {
	global PORT, SECRET, ROSTER, rivalPid

	Run '"' A_AhkPath '" /script "' A_ScriptDir '\Fleet.ahk" ' PORT ' ' SECRET ' 9 1 "' ROSTER '"'
		, , "Hide", &rivalPid
}

;The good secret, an unknown row. This is not the intruder below - it is what
;an ordinary macro looks like to a coordinator that has just taken over without
;a configuration, and it has to be told the refusal is one it can come back
;from. Treating it as final is how losing one machine used to empty the fleet.
Stranger(*) {
	global clientE

	clientE := sock_Connect("127.0.0.1", PORT, OnStranger)
}

OnStranger(s, event, data) {
	global SECRET, byeFinal
	local frame

	if (event = "connect") {
		if (data = "")
			sock_SendLine(s, fleet_Frame("HELLO", Map("row", 77, "name", "nobody"
				, "secret", SECRET, "machine", A_ComputerName)))
		return
	}
	if ((event = "line") && (frame := fleet_Parse(data)) && (frame.verb = "BYE"))
		byeFinal["unknown row"] := fleet_Field(frame, "final", "missing")
}

;What a macro says about its own configuration, on the heartbeat. Without it
;there is nowhere to see that one macro is sitting on a version of its own,
;which is the only symptom the stale-copy failure has.
SayVersion(*) {
	global clientA

	sock_SendLine(clientA, fleet_Frame("HEARTBEAT", Map("cv", 42, "cby", 7)))
}

;The table cleared on purpose: no rows, and the next version.
;
;This must be obeyed, where a file that merely parses to nothing must not. It
;is destructive and correctly so - every account is gone, so every macro is
;turned away - which is why the count of rows already struck is taken first,
;so the earlier checks can still say what was true before it.
Wipe(*) {
	global ROSTER, goneRows, goneAtWipe

	goneAtWipe := goneRows.Count
	roster_Save(ROSTER, Map(), 11, 1)
}

;A configuration from the past, offered by a seated macro.
;
;This is the macro that was disconnected while the fleet moved on, reconnected,
;and now holds an older copy than the coordinator. It must not win. Before the
;files carried a version there was nothing to compare and it always did.
HandUpStale(*) {
	global clientA

	Push(clientA, 2, 7, Map(1, "stale one"))
}

;And a configuration from the future, which must win.
;
;All three rows, because adopting a roster that is missing one would strike
;that account off - correct behaviour for a real edit, and not what is being
;tested here.
HandUpBetter(*) {
	global clientA

	Push(clientA, 9, 7, Map(1, "main", 2, "fuzzy 1", 3, "handed up"))
}

;The same version as the one just taken, written by a different row: both sides
;of a split edited separately. The lower row wrote the one we have, so ours
;stays and theirs is kept beside it.
HandUpTie(*) {
	global clientA

	Push(clientA, 9, 9, Map(1, "main", 2, "fuzzy 1", 3, "tie loser"))
}

;One SETROW frame per row, which is how a whole configuration travels.
Push(sock, version, by, names, bench := 0) {
	local row, name

	for row, name in names
		sock_SendLine(sock, fleet_Frame("SETROW", Map("v", version, "by", by
			, "bench", bench, "n", names.Count, "row", row, "name", name
			, "role", (row = 1) ? "main" : "fuzzy"
			, "user", "", "machine", "selftest")))
}

;The test bench, offering a configuration at a version nothing real could
;reach. It must still lose, because of the mark and not the number.
HandUpBench(*) {
	global clientA

	Push(clientA, 999, 7, Map(1, "hijacked by the bench"), 1)
}

;One server deleted. The macro's copy has to end up holding one and not two,
;and no frame says "delete" - the generation riding on the frames is the whole
;of the mechanism.
DropServer(*) {
	global SERVERS
	local list := servers_Load(SERVERS)

	list.Delete(2)
	;a deletion is the next version, exactly as the coordinator would write it
	servers_Save(SERVERS, list, 4, 1)
}

;The roster file as it looks for the instant between a delete and a write, or
;on a read that failed. The coordinator must not read this as "every account
;has been removed" - doing so struck the whole fleet off and refused all of it.
Blank(*) {
	global ROSTER

	try FileDelete ROSTER
	try FileAppend ";nothing readable here`r`n", ROSTER, "UTF-8"
}

;What ext_FleetLeave does on the macro side: say so, then go. The coordinator
;should strike the row rather than list it offline.
Leave(*) {
	global clientB

	sock_SendLine(clientB, fleet_Frame("LEAVE"))
}

OnA(s, event, data) {
	Handle("main", 1, "main", s, event, data)
}
OnB(s, event, data) {
	;the space in the name is the point: it is the character the wire protocol
	;has to encode, and a naive implementation would split the frame on it
	Handle("fuzzy", 2, "fuzzy 1", s, event, data)
}
OnC(s, event, data) {
	Handle("late", 3, "fuzzy 2", s, event, data)
}

Handle(label, row, name, s, event, data) {
	global seenBy, SECRET, gotoField, fieldSent, pinged, goneRows
	global bothSeen, row2, rttSeen, lateField
	global srv, srvGen, srvMainLink, srvMainOwner
	global cfg, cfgGen, cfgWant, cfgMost, cfgUnseen, cfgLowVer, cfgHighVer
	global cfgTookUp, myCv, leadOnRoster
	local frame, r, f, rows

	if (event = "connect") {
		if (data != "")
			return
		sock_SendLine(s, fleet_Frame("HELLO", Map("row", row, "name", name
			, "role", label, "secret", SECRET, "machine", A_ComputerName)))
		return
	}
	if (event != "line")
		return
	if !(frame := fleet_Parse(data))
		return
	if (frame.verb = "ROSTER") {
		seenBy[label][Integer(fleet_Field(frame, "row", 0))] := frame
		if ((label = "main") && (Integer(fleet_Field(frame, "row", 0)) = 1)
			&& (Integer(fleet_Field(frame, "cv", 0)) > 0))
			myCv := Integer(fleet_Field(frame, "cv", 0))
		;noted as it goes past rather than read back at the end: row 2 is struck
		;from the live view later in this test, and these checks still have to
		;be able to say what was true while it was there
		if (seenBy[label].Has(1) && seenBy[label].Has(2))
			bothSeen[label] := 1
		;read the way a follower reads it, from the rows alone and with no GOTO
		;involved - caught while it is true, since the wipe later empties the
		;fleet on purpose
		if ((label = "late") && (leadOnRoster = "")) {
			rows := Map()
			for r, f in seenBy["late"]
				rows[r] := f.fields
			leadOnRoster := roster_LeadField(rows)
		}
		if (Integer(fleet_Field(frame, "row", 0)) = 2) {
			row2 := frame
			if (Integer(fleet_Field(frame, "rtt", -1)) >= 0)
				rttSeen := Integer(fleet_Field(frame, "rtt", -1))
		}
		;once the main can see the whole fleet, it reports the field it is
		;farming - exactly what nm_GoGather does - and the coordinator should
		;turn that into a GOTO for every resident
		if ((label = "main") && seenBy["main"].Has(1) && seenBy["main"].Has(2) && !fieldSent) {
			fieldSent := 1
			sock_SendLine(s, fleet_Frame("FIELD", Map("name", "Sunflower")))
		}
	}
	else if (frame.verb = "GOTO") {
		if (label = "fuzzy")
			gotoField := fleet_Field(frame, "field")
		else if (label = "late")
			lateField := fleet_Field(frame, "field")
	}
	else if ((label = "main") && (frame.verb = "ROW")) {
		;the configured roster, collected the way the extension collects it -
		;a generation never seen before replaces the copy rather than merging
		;keyed on the version and its author, which is what the extension does
		;for real - a file's timestamp cannot order two machines' copies
		if (cfgGen != fleet_Field(frame, "v") "/" fleet_Field(frame, "by")) {
			cfg := Map()
			cfgGen := fleet_Field(frame, "v") "/" fleet_Field(frame, "by")
			cfgWant := Integer(fleet_Field(frame, "n", 0))
			if (cfgWant > cfgMost)
				cfgMost := cfgWant
		}
		cfg[Integer(fleet_Field(frame, "row", 0))] := frame
		if (Integer(fleet_Field(frame, "v", 0)) < cfgLowVer)
			cfgLowVer := Integer(fleet_Field(frame, "v", 0))
		if (Integer(fleet_Field(frame, "v", 0)) > cfgHighVer)
			cfgHighVer := Integer(fleet_Field(frame, "v", 0))
		;the handed-up roster coming back out of the coordinator is the only
		;way to see that it was taken rather than merely accepted in silence
		if ((fleet_Field(frame, "name") == "handed up") && !cfgTookUp)
			cfgTookUp := Integer(fleet_Field(frame, "v", 0))
		;the whole point of these frames: an account that is configured but has
		;never connected has no ROSTER frame and is invisible everywhere else,
		;so it could neither be shown nor replicated
		if !seenBy["main"].Has(Integer(fleet_Field(frame, "row", 0)))
			cfgUnseen := fleet_Field(frame, "name")
				. " (" fleet_Field(frame, "machine") ")"
	}
	else if ((label = "main") && (frame.verb = "SERVER")) {
		;the generation logic the extension does for real, in miniature. A
		;generation never seen before means the list changed somehow, and the
		;old copy is thrown away rather than merged into.
		if (srvGen != fleet_Field(frame, "v") "/" fleet_Field(frame, "by")) {
			srv := Map()
			srvGen := fleet_Field(frame, "v") "/" fleet_Field(frame, "by")
		}
		srv[Integer(fleet_Field(frame, "slot", 0))] := frame
		if (fleet_Field(frame, "kind") = "main") {
			srvMainLink := fleet_Field(frame, "link")
			srvMainOwner := Integer(fleet_Field(frame, "owner", -1))
		}
	}
	else if (frame.verb = "PING") {
		;answered the way a real macro does; without this there is nothing for
		;the coordinator to time and the round trip stays unmeasured
		if (label = "fuzzy")
			pinged := 1
		sock_SendLine(s, fleet_Frame("ACK", Map("id", fleet_Field(frame, "id"))))
	}
	else if ((label = "main") && (frame.verb = "GONE")) {
		goneRows[Integer(fleet_Field(frame, "row", 0))] := 1
		;GONE is the only frame that removes a row, so the panel's own view has
		;to act on it - this is that, in miniature
		if (seenBy["main"].Has(Integer(fleet_Field(frame, "row", 0))))
			seenBy["main"].Delete(Integer(fleet_Field(frame, "row", 0)))
	}
}

;The connection that should not get in.
OnBad(s, event, data) {
	global refused, byeFinal
	local frame

	if (event = "connect") {
		if (data = "")
			sock_SendLine(s, fleet_Frame("HELLO", Map("row", 9, "name", "intruder"
				, "secret", "wrong")))
		return
	}
	if ((event = "line") && (frame := fleet_Parse(data)) && (frame.verb = "BYE"))
		refused := fleet_Field(frame, "why")
		, byeFinal["bad secret"] := fleet_Field(frame, "final", "missing")
	else if (event = "close")
		refused := refused ? refused : "closed"
}

Report(*) {
	global seenBy, refused, coordPid, rivalPid, finished, clientA, clientB, clientBad
	global HANDROSTER, handPid, handRefused, handTold, handDoor
	global beaconSeen, HANDPORT, beaconSock, strayPid, keepPid, strayStopped, secondMainWhy
	global clientC, clientD, clientE, boundRow, SERVERS, myCv, goneAtWipe, boundFid
	global srv, srvGen, srvMainLink, srvMainOwner
	global cfg, cfgWant, cfgMost, cfgUnseen, cfgLowVer, cfgHighVer
	global cfgTookUp, byeFinal, otherWhy, clientOther
	global ROSTER, gotoField
	global bothSeen, row2, rttSeen, pinged, goneRows, lateField
	local lines := [], allOk := 1, summary, path, leftRoster, logText
	local idsOk, idsSeen, newId, mandRoster, handLog
	global LOGFILE

	if finished
		return
	finished := 1

	;read before the file is deleted below: a row that left should be gone from
	;the roster on disk too, which is what stops it coming back on a reload
	leftRoster := FileExist(ROSTER) ? roster_Load(ROSTER) : Map()
	;and the log read once, here, before anything is closed. ProcessClose
	;returns before the process is actually gone, and a coordinator still
	;holding the file open for append makes this read fail - which it did,
	;intermittently, and only in the part of the report a human reads.
	logText := FleetLog()

	allOk := Check(lines, "both rows reach the main macro"
		, bothSeen["main"]) && allOk
	allOk := Check(lines, "both rows reach the fuzzy macro"
		, bothSeen["fuzzy"]) && allOk
	allOk := Check(lines, "the space in `"fuzzy 1`" survived"
		, IsObject(row2) && (fleet_Field(row2, "name") == "fuzzy 1")) && allOk
	allOk := Check(lines, "a wrong secret was refused"
		, refused != "") && allOk
	allOk := Check(lines, "the main's field reaches the resident as a GOTO"
		, gotoField == "Sunflower") && allOk
	allOk := Check(lines, "a resident joining late is sent the main's field"
		, lateField == "Sunflower") && allOk
	;row 1 is the main, and it was never removed from anything - so if the
	;coordinator struck it off, it did so because it believed an empty file
	;against the count taken before the deliberate wipe below, which strikes
	;everybody off on purpose and would otherwise look like the same fault
	allOk := Check(lines, "an unreadable roster strikes nobody off"
		, (goneAtWipe = 1) && seenBy["main"].Has(1)) && allOk
	allOk := Check(lines, "a ping is answered and timed"
		, pinged && (rttSeen >= 0)) && allOk
	allOk := Check(lines, "a macro that leaves is struck from the fleet"
		, goneRows.Has(2) && !seenBy["main"].Has(2) && !leftRoster.Has(2)) && allOk
	;read from this run's own log, which is why the coordinator puts it beside
	;the roster it was handed. "listening" twice would be the bug itself.
	allOk := Check(lines, "a second coordinator is refused the port"
		, InStr(logText, "another coordinator already has it")) && allOk
	;3, not 4: the Roblox username is the identity, so the same account setting
	;itself up again lands on the row it already had
	allOk := Check(lines, "a second setup of one account reuses its row"
		, boundRow = 3) && allOk
	allOk := Check(lines, "the server list reaches a macro, link and owner intact"
		, (srvMainLink == "https://roblox.test/main?code=a b%c")
			&& (srvMainOwner = 2)) && allOk
	allOk := Check(lines, "a deleted server disappears from the macro's copy"
		, (srv.Count = 1) && srv.Has(1)) && allOk
	;Row 3 is configured from the start and does not connect for five seconds,
	;so for those five seconds it exists in the roster and nowhere else. The
	;count matters as much as the rows: without it a macro never knows when
	;its replica is whole enough to write, and half a roster written over a
	;whole one loses accounts.
	allOk := Check(lines, "a configured row that has never connected is broadcast"
		, (cfgUnseen == "fuzzy 2 (selftest)") && (cfgMost = 3)) && allOk
	allOk := Check(lines, "a bad secret is final and an unknown row is not"
		, (byeFinal.Has("bad secret") && (byeFinal["bad secret"] = 1))
			&& (byeFinal.Has("unknown row") && (byeFinal["unknown row"] = 0))) && allOk
	;version 2 was offered and would have been served if it had been taken
	allOk := Check(lines, "a stale configuration handed up is refused"
		, cfgLowVer >= 5) && allOk
	allOk := Check(lines, "a better configuration handed up is taken"
		, cfgTookUp = 9) && allOk
	;the tie loser is written beside the file rather than dropped, which is the
	;whole reason an arbitrary rule is tolerable
	allOk := Check(lines, "a tie keeps ours and files theirs"
		, FileExist(ROSTER ".conflict")
			&& (roster_Load(ROSTER ".conflict").Has(3))) && allOk
	;the exact line, because the whole question is whether it was applied or
	;mistaken for the unreadable file that check seven is about
	allOk := Check(lines, "a roster cleared on purpose is applied, not ignored"
		, InStr(logText, "roster reloaded, 0 rows, version 11")) && allOk
	allOk := Check(lines, "a macro's own configuration version reaches the fleet"
		, myCv = 42) && allOk
	;the comparison itself, with nothing on the wire: version 1 marked as the
	;bench's against version 999 that is not, and the mark has to decide it
	allOk := Check(lines, "a bench configuration loses to a real one"
		, !fleet_ConfigBeats({ version: 999, by: 1, bench: 1 }
			, { version: 1, by: 1 })
		&& fleet_ConfigBeats({ version: 1, by: 1 }
			, { version: 999, by: 1, bench: 1 })) && allOk
	;and the same between processes: the bench offered version 999 and the
	;coordinator must never have served it
	allOk := Check(lines, "a bench configuration is refused over the wire"
		, cfgHighVer < 999) && allOk

	;--- a folder per fleet -------------------------------------------------
	;
	;Written before the mechanism was, and these two are why: an id is a folder
	;name that arrives from the wire. An empty one has to fall back to the old
	;flat file rather than build settings\fleet\\roster.ini, and one carrying a
	;separator has to be refused outright - a coordinator must not be able to
	;choose where a macro writes.
	allOk := Check(lines, "an empty fleet id falls back to the old flat file"
		, (fleet_RosterPath("C:\nm", "") = "C:\nm\settings\fleet_roster.ini")
		&& !fleet_IsId("")) && allOk
	allOk := Check(lines, "an id with a separator in it is refused"
		, !fleet_IsId("..\..\settings") && !fleet_IsId("a/b") && !fleet_IsId("a.b")
		&& fleet_IsId("f3a9c1b2")) && allOk
	;the whole point: two fleets cannot reach each other's files, so a stale or
	;a bench copy can no longer be compared with a real one at all
	allOk := Check(lines, "two fleets keep two folders, roster and servers"
		, (fleet_RosterPath("C:\nm", "fone") != fleet_RosterPath("C:\nm", "ftwo"))
		&& (fleet_ServersPath("C:\nm", "fone")
			= "C:\nm\settings\fleet\fone\roster_servers.ini")) && allOk
	;an ini turns 00123456 into 123456, so an identity that opens with a digit
	;is a folder name that stops matching itself. Two hundred draws is enough to
	;catch a generator that merely usually starts with a letter.
	idsOk := 1, idsSeen := Map()
	Loop 200 {
		newId := fleet_NewId()
		idsSeen[newId] := 1
		if (!fleet_IsId(newId) || IsInteger(newId) || !RegExMatch(newId, "^[a-z]"))
			idsOk := 0
	}
	allOk := Check(lines, "a new fleet id is a folder name an ini cannot eat"
		, idsOk && (idsSeen.Count > 190)) && allOk
	;a fleet that predates the idea: every machine in it has to reach the same
	;answer from the secret alone, because nobody is going to tell them
	allOk := Check(lines, "an old fleet's id is the fingerprint of its secret"
		, (fleet_LegacyId("abc") = fleet_LegacyId("abc"))
		&& (fleet_LegacyId("abc") != fleet_LegacyId("abd"))
		&& fleet_IsId(fleet_LegacyId("abc"))
		&& (fleet_LegacyId("") = "")) && allOk
	;and the wire half: a macro being bound is told which fleet it joined, or it
	;would write this fleet's configuration into the folder of its last one
	allOk := Check(lines, "binding hands over the fleet's identity"
		, fleet_IsId(boundFid)) && allOk

	;--- a log that stays small -----------------------------------------------
	;
	;Every macro now writes one, and a macro writes a handful of lines per run -
	;so a size checked only every two hundred lines would never be checked, and
	;the file would grow across restarts for good. The first line of a run has
	;to look. Cap and interval are shrunk so the test needs a few lines, not
	;half a megabyte.
	appendLog := A_ScriptDir "\..\settings\fleet_append_selftest.log"
	try FileDelete appendLog
	try FileDelete appendLog ".1"
	FileAppend StrRepeatSelfTest("x", 300) "`n", appendLog, "UTF-8"
	appendOk := fleet_Append(appendLog, "first line of a run", 100, 1000)
	allOk := Check(lines, "the first line of a run rotates an oversized log"
		, appendOk && FileExist(appendLog ".1") && (FileGetSize(appendLog) < 100)) && allOk
	try FileDelete appendLog
	try FileDelete appendLog ".1"

	;--- following the main ---------------------------------------------------
	;
	;The GOTO is an event, and a follower that was reconnecting when it went
	;out never saw it again until the main changed field - which on a main left
	;on one field is never. The roster goes out on every beat, so the field read
	;off it is state: a follower that missed the order is right a beat later.
	allOk := Check(lines, "a follower finds the main's field on the roster"
		, leadOnRoster == "Sunflower") && allOk
	;and what cuts a gather short. A guid farms its own field and must never
	;be pulled out of it; a field name differing only in capitals is the same
	;field in Natro, and reading it as a move would cut every trip short.
	allOk := Check(lines, "only a fuzzy or tad is pulled out of another field"
		, roster_FollowMoves("fuzzy", "Sunflower", "Pine Tree")
		&& roster_FollowMoves("tad", "Sunflower", "Pine Tree")
		&& !roster_FollowMoves("guid", "Sunflower", "Pine Tree")
		&& !roster_FollowMoves("main", "Sunflower", "Pine Tree")
		&& !roster_FollowMoves("fuzzy", "", "Pine Tree")
		&& !roster_FollowMoves("tad", "sunflower", "Sunflower")) && allOk

	;--- the mandate --------------------------------------------------------
	;
	;Written before the verb that reads it. The row that launched a coordinator
	;is not the row entitled to command it: after a failover those are different
	;macros, and the second had been given the first one's say.
	mandRoster := Map(1, { row: 1 }, 3, { row: 3 })
	allOk := Check(lines, "only the mandated row may command the coordinator"
		, fleet_MayCommand(1, 1, mandRoster)
		&& !fleet_MayCommand(1, 3, mandRoster)
		&& !fleet_MayCommand(1, 0, mandRoster)
		;a coordinator with no mandate named obeys the fleet, which is how the
		;bench and every older build keep working
		&& fleet_MayCommand(0, 3, mandRoster)) && allOk
	;the escape hatch: the mandated account is no longer in the fleet, so the
	;say passes to the rows that are - and only to them
	allOk := Check(lines, "a mandate nobody holds any more passes to the fleet"
		, fleet_MayCommand(9, 3, mandRoster)
		&& fleet_MayCommand(9, 1, mandRoster)
		&& !fleet_MayCommand(9, 7, mandRoster)) && allOk
	;and the same on the wire, against a coordinator told its mandate is row 1
	handLog := ""
	try handLog := FileRead(RegExReplace(HANDROSTER, "i)\.ini$", ".log"), "UTF-8")
	allOk := Check(lines, "a macro without the mandate is refused the handover"
		, InStr(handRefused, "only row 1")
		&& InStr(handLog, "refused a handover asked for by row 2")) && allOk
	;the order reaches everybody, carries the say with it, and the process that
	;handed over stops - which on one machine is the only way the next one can
	;have the port
	allOk := Check(lines, "the mandated row hands the coordinator on, and it stops"
		, (handTold.Has(1) && (handTold[1] = "2/1"))
		&& (handTold.Has(2) && (handTold[2] = "2/1"))
		&& InStr(handLog, "handed the coordinator on")
		&& !ProcessExist(handPid)) && allOk
	allOk := Check(lines, "a second main is refused at the door"
		, InStr(secondMainWhy, "BYE") && InStr(secondMainWhy, "already the main")) && allOk
	allOk := Check(lines, "the rule finds the main, and not the account itself"
		, (roster_MainOtherThan(Map(1, { role: "main" }, 2, { role: "fuzzy" }), 3) = 1)
		&& (roster_MainOtherThan(Map(1, { role: "main" }, 2, { role: "fuzzy" }), 1) = 0)
		&& (roster_MainOtherThan(Map(2, { role: "fuzzy" }), 3) = 0)) && allOk
	;An edit made on any macro is handed up, and the coordinator takes it only
	;if its version beats what it serves - so the edit has to beat both the copy
	;on this disk and the one the fleet runs, whichever is ahead.
	ev1 := fleet_EditVersion({ version: 5, by: 1 }, { version: 7, by: 1 }, 3)
	ev2 := fleet_EditVersion({ version: 9, by: 2 }, { version: 7, by: 1 }, 3)
	allOk := Check(lines, "an edit made anywhere beats both copies"
		, (ev1.version = 8) && (ev1.by = 3)
		&& fleet_ConfigBeats(ev1, { version: 7, by: 1 })
		&& fleet_ConfigBeats(ev2, { version: 9, by: 2 })
		&& fleet_ConfigBeats(ev2, { version: 7, by: 1 })) && allOk
	;What a card's colour says. A follower standing somewhere other than the
	;main's field is the one thing worth seeing at a glance across the panel.
	allOk := Check(lines, "a follower away from the main's field is told apart"
		, (roster_SeatState(Map("state", "online", "role", "fuzzy", "field", "Bamboo"), "Pine Tree") = "away")
		&& (roster_SeatState(Map("state", "online", "role", "tad", "field", "pine tree"), "Pine Tree") = "online")
		&& (roster_SeatState(Map("state", "online", "role", "guid", "field", "Bamboo"), "Pine Tree") = "online")
		&& (roster_SeatState(Map("state", "online", "role", "fuzzy", "field", "Bamboo"), "") = "online")
		&& (roster_SeatState(Map("state", "stale", "role", "fuzzy", "field", "Bamboo"), "Pine Tree") = "silent")
		&& (roster_SeatState(Map("state", "offline", "role", "fuzzy"), "Pine Tree") = "offline")) && allOk
	;P3. A macro used to latch onto the first beacon of its fleet whatever its
	;term, so a coordinator that had been replaced could keep the macros that
	;happened to hear it first. The highest term wins, on the beacon as on the
	;heartbeat; no term at all is an older coordinator and is not held against it.
	allOk := Check(lines, "a beacon with a higher term wins, a lower one is ignored"
		, (fleet_BeaconVerdict(1, 3, 1) = "ignore")
		&& (fleet_BeaconVerdict(3, 3, 1) = "note")
		&& (fleet_BeaconVerdict(4, 3, 1) = "switch")
		&& (fleet_BeaconVerdict(4, 3, 0) = "note")
		&& (fleet_BeaconVerdict(2, 0, 0) = "note")
		&& (fleet_BeaconVerdict(0, 3, 1) = "note")) && allOk
	;A guiding star's end and "last heard from" were absolute times taken on one
	;machine and read on another, so two minutes of drift between PCs made the
	;countdown two minutes wrong. They travel as durations, turned back into
	;times on arrival against this machine's clock.
	lt := fleet_LocalTimes(Map("left", "90", "age", "4"), 1000)
	lt0 := fleet_LocalTimes(Map("until", "5000", "seen", "777"), 1000)
	allOk := Check(lines, "durations become this machine's times on arrival"
		, (lt["until"] = 1090) && (lt["seen"] = 996)
		&& (lt0["until"] = 5000) && (lt0["seen"] = 777)) && allOk
	allOk := Check(lines, "the coordinator sends how long ago, not when"
		, IsObject(row2) && (fleet_Field(row2, "age") != "")
		&& (Integer(fleet_Field(row2, "age")) >= 0)
		&& (fleet_Field(row2, "left") != "")) && allOk
	allOk := Check(lines, "a roster with two mains is recognised"
		, roster_HasTwoMains(Map(1, { role: "main" }, 4, { role: "main" }))
		&& !roster_HasTwoMains(Map(1, { role: "main" }, 4, { role: "tad" }))
		&& !roster_HasTwoMains(Map(4, { role: "tad" }))) && allOk
	lines.Push("a second main was told: " ((secondMainWhy != "") ? secondMainWhy : "nothing"))
	;the stray, found by its fleet id among this folder's processes
	allOk := Check(lines, "the coordinator of a fleet left behind is stopped"
		, (strayStopped = 1) && strayPid && !ProcessExist(strayPid)) && allOk
	allOk := Check(lines, "and another fleet's coordinator is left running"
		, keepPid && ProcessExist(keepPid)) && allOk
	lines.Push("stray coordinators stopped: " strayStopped)
	if keepPid
		try ProcessClose(keepPid)
	if strayPid
		try ProcessClose(strayPid)
	for _, f in ["stray", "keep"] {
		try FileDelete A_ScriptDir "\..\settings\fleet_roster_" f ".ini"
		try FileDelete A_ScriptDir "\..\settings\fleet_roster_" f ".log"
	}
	;the same privilege, and the refusal that used to be silent
	allOk := Check(lines, "the binding door says no instead of ignoring it"
		, InStr(handDoor, "only row 1")) && allOk

	;--- the beacon ---------------------------------------------------------
	;
	;Nothing had ever checked it, and it is the whole of discovery: a macro that
	;hears no beacon has to be given an address by hand, which is the state this
	;fork exists to get away from. It also carries the two things the join
	;window decides on - whether the door is open, and what the fleet calls
	;itself.
	allOk := Check(lines, "the beacon says where to knock and which fleet it is"
		, (fleet_Num(beaconSeen.Has("port") ? beaconSeen["port"] : 0) = HANDPORT)
		&& (beaconSeen.Has("id")
			&& (beaconSeen["id"] = fleet_Fingerprint(SECRET)))
		&& (beaconSeen.Has("host") && (beaconSeen["host"] != ""))
		&& (beaconSeen.Has("from") && (beaconSeen["from"] != ""))) && allOk
	;the open flag is what turns the join button on, and the label is what stops
	;somebody joining a test fleet believing it was theirs
	allOk := Check(lines, "and whether it is accepting macros, and what it is"
		, (beaconSeen.Has("open") && (beaconSeen["open"] = "1"))
		&& (beaconSeen.Has("label") && (beaconSeen["label"] = "a test fleet"))
		&& (fleet_Num(beaconSeen.Has("size") ? beaconSeen["size"] : -1) = 2))
		&& allOk

	;--- knocking on the wrong door -----------------------------------------
	;
	;Written before the mechanism. The pure half first: an identity on both
	;sides decides, and one missing on either side cannot, so the secret goes on
	;deciding as it always did.
	allOk := Check(lines, "a macro from another fleet is recognised as such"
		, !fleet_SameFleet("fother", "fours")
		&& fleet_SameFleet("fours", "fours")) && allOk
	allOk := Check(lines, "an identity nobody sent leaves the secret deciding"
		, fleet_SameFleet("", "fours")
		&& fleet_SameFleet("fother", "")
		&& fleet_SameFleet("", "")) && allOk
	;and on the wire, where it matters: not final, so the macro keeps looking
	;for its own fleet instead of letting go of it
	allOk := Check(lines, "and the refusal is not final, so it keeps looking"
		, InStr(otherWhy, "fleet")
		&& byeFinal.Has("another fleet")
		&& (byeFinal["another fleet"] = 0)) && allOk

	if IsObject(row2)
		lines.Push("", "row 2 as the main macro last saw it:"
			, "  name=" fleet_Field(row2, "name")
			. "  role=" fleet_Field(row2, "role")
			. "  state=" fleet_Field(row2, "state")
			. "  rtt=" fleet_Field(row2, "rtt") "ms")
	else
		lines.Push("", "The main macro never heard about row 2.")
	lines.Push("after it left: GONE for row 2=" (goneRows.Has(2) ? "yes" : "no")
		. ", still in the live view=" (seenBy["main"].Has(2) ? "yes" : "no")
		. ", still in the roster file=" (leftRoster.Has(2) ? "yes" : "no"))
	lines.Push("the late resident was told: " (lateField != "" ? lateField : "nothing")
		. ", and read off the roster: " (leadOnRoster != "" ? leadOnRoster : "nothing"))
	lines.Push("row 3 set itself up again and was handed row "
		. ((boundRow >= 0) ? boundRow : "nothing at all")
		. " of fleet " ((boundFid != "") ? boundFid : "(it was not told)"))
	lines.Push("the main said it held v42 and got back: "
		. ((myCv >= 0) ? "v" myCv : "nothing")
		. ", rows struck before the wipe: " goneAtWipe)
	lines.Push("versions served: lowest " cfgLowVer ", highest " cfgHighVer
		. " (999 would mean the bench won)")
	lines.Push("lowest version ever served: " cfgLowVer
		. ", handed-up roster came back at: " (cfgTookUp ? cfgTookUp : "never"))
	lines.Push("configured rows: " cfgMost " promised at the fullest, "
		. cfg.Count " of " cfgWant " after row 2 left")
	lines.Push("seen configured before it ever connected: "
		. (cfgUnseen != "" ? cfgUnseen : "nothing"))
	lines.Push("another fleet was told: "
		. ((otherWhy != "") ? otherWhy : "nothing at all")
		. ", final=" (byeFinal.Has("another fleet")
			? byeFinal["another fleet"] : "no BYE"))
	lines.Push("refusals: bad secret final="
		. (byeFinal.Has("bad secret") ? byeFinal["bad secret"] : "no BYE")
		. ", unknown row final="
		. (byeFinal.Has("unknown row") ? byeFinal["unknown row"] : "no BYE"))
	lines.Push("servers held after one of two was deleted: " srv.Count
		. " at version " srvGen
		. ", main link=" (srvMainLink != "" ? srvMainLink : "never sent"))

	sock_Close(clientA), sock_Close(clientB), sock_Close(clientBad)
	if clientC
		sock_Close(clientC)
	if clientD
		sock_Close(clientD)
	if clientE
		sock_Close(clientE)
	if coordPid
		try ProcessClose(coordPid)
	;it should have exited on its own, having been refused the port. Closed
	;anyway, because a test that leaves a coordinator behind poisons the next
	;run - which is how this very bug was found.
	if rivalPid
		try ProcessClose(rivalPid)
	try FileDelete ROSTER
	try FileDelete SERVERS
	try FileDelete ROSTER ".conflict"

	;the coordinator's own log is the half of the story this script cannot
	;see, so it travels with the verdict rather than being looked up after
	summary := "Fleet self-test on " A_ComputerName ", AutoHotkey " A_AhkVersion "`r`n`r`n"
		. StrReplace(Join(lines), "`n", "`r`n")
		. "`r`ncoordinator pid " (coordPid ? coordPid : "never started")
		. "`r`n`r`n" LOGFILE ":`r`n" logText
	path := A_ScriptDir "\..\settings\fleet_diag.txt"
	try FileDelete path
	try FileAppend summary, path, "UTF-8"
	;headless over SSH: a verdict in a file, an exit code, no window
	if Quiet() {
		FileAppend (allOk ? "PASS" : "FAIL") "`n", "*"
		ExitApp allOk ? 0 : 1
	}
	if allOk {
		MsgBox "Fleet coordinator works.`n`n" Join(lines), "Fleet self-test", 0x40040
		ExitApp
	}
	try A_Clipboard := summary
	MsgBox "Fleet coordinator is broken.`n`n" Join(lines)
		. "`nThe full trace is on the clipboard - paste it straight into chat."
		. "`nIt is also in settings\fleet_diag.txt, which will open now."
		, "Fleet self-test", 0x40010
	try Run 'notepad.exe "' path '"'
	ExitApp
}

;Whatever the coordinator managed to write before it died, which when it
;died early is nothing - and that silence is itself the answer.
FleetLog() {
	global LOGFILE

	if !FileExist(LOGFILE)
		return "(no log at all - the coordinator never got as far as writing one)"
	try return FileRead(LOGFILE, "UTF-8")
	return "(the log exists but could not be read)"
}

;A string of n copies of c, to make a file of a known size.
StrRepeatSelfTest(c, n) {
	return StrReplace(Format("{:" n "}", ""), " ", c)
}

Check(lines, what, ok) {
	lines.Push((ok ? "PASS  " : "FAIL  ") what)
	return ok
}

;True when launched with /quiet, i.e. headless over SSH.
Quiet() {
	return ObjHasValue(A_Args, "/quiet")
}

;Is needle one of the elements of arr?
ObjHasValue(arr, needle) {
	for _, v in arr
		if (v = needle)
			return 1
	return 0
}

Join(arr) {
	local out := ""
	for _, v in arr
		out .= v "`n"
	return out
}
