;The state Natro Fleet keeps while a macro runs.
;
;Included at the point in natro_macro.ahk where these lines used to be, so
;they still run in the same order as the rest of its start-up. They live in
;a file of their own so that FleetUiDump.ahk can build the fleet's windows
;against the same state the macro has, rather than a copy that drifts: the
;copy it used to carry had already lost four of these names.
;
;Configuration is not here. FleetCheck, FleetRow and the rest are read from
;nm_config.ini by nm_importConfig.
;the fleet as this macro currently sees it. All of it is rebuilt from the
;coordinator on connect, so none of it is saved.
ext_fleetSock := 0, ext_fleetTerm := 0, ext_fleetCoordRow := 0
;the row the coordinator takes orders on behalf of, and the row a handover
;order named - see ext_fleetOnTakeOver. Both learnt from the fleet, never set
;here: a macro that decided its own mandate would be deciding it had the say.
ext_fleetMandate := 0, ext_fleetTakeOverTo := 0
;address -> when it last said it belongs to another fleet. Bounded by the
;number of addresses a macro ever tries, which is three.
ext_fleetOtherFleet := Map()
ext_fleetCoordSeen := 0, ext_fleetBackoff := 0, ext_fleetTrying := ""
ext_fleetPeers := Map()
;where the last beacon came from, and the socket that listens for them.
;Discovered rather than configured, which is the point: an address typed in
;is wrong as soon as a router hands out a new lease.
ext_fleetFoundAt := "", ext_fleetBeaconSock := 0, ext_fleetTryAt := 0
;field-following: the field we last told the fleet we are farming, and the
;field a resident has been told to follow the main into
ext_fleetMyField := "", ext_fleetFollowField := ""
;this account's role as the fleet last said it, and the log lines waiting to be
;written - see ext_fleetSetRole and ext_fleetNote
ext_fleetMyRole := "", ext_fleetNotes := []
;where a coordinator on a higher term was heard, tried first - see ext_fleetSwitch
ext_fleetPrefer := ""
;an address typed in the join window, kept only once the fleet lets us in
ext_fleetBindTyped := ""
;why the fleet turned this macro away, when it did. A refusal is final, so it
;is kept rather than retried - see the BYE case in extensions\fleet.ahk
ext_fleetRefused := ""
;the fleet's configuration as the coordinator last described it - the roster as
;configured, and the servers - each with the generation that copy is on, how
;many entries that generation promised, and which generation has been written
;to disk. Thrown away and rebuilt whenever the generation changes, which is how
;a deleted entry stops being drawn; written out once whole, which is how a macro
;that has to take over already holds a configuration. See ext_fleetReplicate.
ext_fleetServers := Map(), ext_fleetServerVer := { version: -1, by: -1 }
ext_fleetServerWant := 0
ext_fleetRoster := Map(), ext_fleetRosterVer := { version: -1, by: -1 }
ext_fleetRosterWant := 0
;what is actually on this machine's disk, which is not always what the
;coordinator has just said. A replica is never allowed to go backwards, so
;these are compared against before anything is written - see ext_fleetReplicate.
ext_fleetRosterDisk := { version: 0, by: 0 }
ext_fleetServerDisk := { version: 0, by: 0 }
;the coordinator process this macro started, so it can be ended again. Nothing
;else would ever end it - see ext_fleetEndCoord.
ext_fleetCoordPid := 0
;this guid's guiding star charge as background.ahk last read it, -1 for
;unknown - see ext_fleetSayCharge
ext_fleetMyCharge := -1
;the server link the fleet has sent this account to, for the next reconnect -
;see ext_fleetOnMove
ext_fleetJoinLink := ""
;the last fault worth telling somebody about, and the row and secret handed
;over by a bind that is waiting for a timer to finish it off
ext_fleetLastProblem := "", ext_fleetBoundWith := ""
;which divergence has already been reported, so a disagreement is said once
;rather than on every frame of every beat - see ext_fleetSayDivergent
ext_fleetSaidDivergent := ""
;which configuration this macro has already offered to the coordinator. Every
;row of a configuration arrives as its own frame, and without this each of them
;would provoke a hand-up of the whole thing.
ext_fleetHandedUp := ""
;the server editor: the list it is working on, which slot is selected, the
;accounts its owner dropdown offers in the order it lists them, and the stamp
;that says whether the list has changed under the window
FleetServers := Map(), FleetServersPath := "", FleetServerSlot := 0
FleetServerOwnerRows := [], FleetServerStamp := ""
;which account each seat card currently shows. The cards are made once and
;repainted, so a click has to be answered from here rather than from a handler
;bound to a row that has since moved.
ext_fleetSeatRow := Map()
;what the fleet has been doing, newest first, as the coordinator reports it
ext_fleetEvents := []
;binding: the open fleets heard on the network, and the one conversation
;that joins one. None of it survives a restart, because binding happens once
;and what it produces - a row and a secret - is what gets saved.
ext_fleetOpen := Map(), ext_fleetBindSock := 0, ext_fleetBindWith := ""
ext_fleetBindResult := "", ext_fleetBindOpenUntil := 0
;which account the roster editor is editing, and the order its list is in
FleetEditRow := 0, FleetRosterOrder := []
