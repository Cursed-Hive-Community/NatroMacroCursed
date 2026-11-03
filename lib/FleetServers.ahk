;The fleet's servers - where the accounts actually sit
;
;A fleet runs on one main private server and as many reserves as the setup
;needs: somewhere to park an account that has to leave the main, somewhere to
;stage a guiding star, somewhere to put a macro that is between jobs.
;
;Each one carries the account that owns it, because only the owner's /kick does
;anything - so "who can clear this server" is a fact about the server, not
;about the account. It used to be one flag on one roster row, which could not
;say that two servers have two different owners, and that is why the flag is
;gone.
;
;Shared through the coordinator like the roster, and for the same reason: an
;owner that disagreed between machines would mean a kick sent from the one
;account whose kick does nothing.
;
;	[1]
;	Name=Main
;	Link=https://www.roblox.com/games/1537690962?privateServerLinkCode=000
;	Owner=2
;	Kind=main
;
;The [fleet] section carries the version and the row that wrote it, exactly as
;the roster's does and for the same reason - see FleetRoster.ahk.
;
;Kind is main or reserve, and exactly one entry is the main. Owner is a roster
;row number, 0 when nobody has said. Slot numbers are stable and never reused,
;so a control that points at one keeps pointing at the same server after
;another is deleted.

;What a server is, said once.
;
;A server travels through the file, two kinds of frame each way and two windows,
;and each of those used to list its fields by hand - seven lists, so a field
;added to one was a field silently dropped by another. They are all built from
;these now.
servers_Keys() {
	return ["name", "link", "owner", "kind"]
}
servers_Blank(slot, kind := "reserve") {
	return { slot: slot, name: "server " slot, link: "", owner: 0, kind: kind }
}
;One field from text - a line of the file or a field of a frame.
servers_Set(e, k, v) {
	switch StrLower(k) {
		case "name":  e.name := v
		case "link":  e.link := v
		case "owner": e.owner := fleet_Num(v)
		case "kind":  e.kind := (StrLower(v) = "main") ? "main" : "reserve"
	}
	return e
}
;A server from a frame's fields. One an older build sent without some field
;keeps that field's default.
servers_FromFields(slot, fields) {
	local e := servers_Blank(slot), k

	for _, k in servers_Keys()
		if fields.Has(k)
			servers_Set(e, k, fields[k])
	return e
}
;A server as a frame: verb SERVER from the coordinator, SETSERVER up to it, with
;the version of the list it belongs to and how many entries that version has.
servers_Frame(verb, e, ver, n) {
	local m := Map("v", ver.version, "by", ver.by, "bench", fleet_IsBench(ver), "n", n
		, "slot", e.slot), k

	for _, k in servers_Keys()
		m[k] := e.%k%
	return fleet_Frame(verb, m)
}

;Read the servers.
;
;A missing file is not an empty list - a fleet has a main server before anybody
;has pasted a link into it, so it is one unfilled main. That also keeps the
;broadcast non-empty, which matters: the generation number that makes a
;deletion converge travels on the entries themselves.
servers_Load(path) {
	local list := Map(), slot, line, at

	slot := 0
	if FileExist(path) {
		Loop Parse FileRead(path, "UTF-8"), "`n", "`r" {
			line := Trim(A_LoopField)
			if ((line = "") || (SubStr(line, 1, 1) = ";"))
				continue
			if (SubStr(line, 1, 1) = "[") {
				;[fleet] is the version, not a server - and a hand-edited file
				;must not be able to stop the list from loading at all
				slot := fleet_SectionNumber(line)
				if (slot > 0)
					list[slot] := servers_Blank(slot)
				continue
			}
			if (!slot || !list.Has(slot) || !(at := InStr(line, "=")))
				continue
			servers_Set(list[slot], Trim(SubStr(line, 1, at - 1)), Trim(SubStr(line, at + 1)))
		}
	}
	if !list.Count
		list[1] := servers_Blank(1, "main"), list[1].name := "Main"
	servers_FixMain(list)
	return list
}

;Exactly one main, whatever the file said.
;
;Self-healing rather than an error: the file can be edited by hand, and a fleet
;with two mains or none is a fleet that cannot answer "where is everybody
;supposed to be". The lowest slot takes the job, which is stable - it does not
;change on the next load.
servers_FixMain(list) {
	local keys := [], s, seen := 0

	for s, _ in list
		keys.Push(s)
	roster_Sort(keys)
	for _, s in keys {
		if (list[s].kind != "main")
			continue
		if seen
			list[s].kind := "reserve"
		seen := s
	}
	if !seen
		list[keys[1]].kind := "main"
	return list
}

;The main server, or 0 if the list is empty - which servers_Load never returns.
servers_Main(list) {
	local s, e

	for s, e in list
		if (e.kind = "main")
			return e
	return 0
}

;How many reserves there are, which is the number the settings window shows.
servers_Reserves(list) {
	local s, e, n := 0

	for s, e in list
		if (e.kind != "main")
			n++
	return n
}

;The next free slot. Never reused, so a control that remembers a slot number
;cannot come to mean a different server than the one it was pointed at.
servers_NextSlot(list) {
	local s, best := 0

	for s, _ in list
		if (s > best)
			best := s
	return best + 1
}

;Write it back, slots in order. Through the same whole-file write the roster
;uses, because this file has the same two writers and the same readers on a
;timer - see fleet_WriteWhole.
servers_Save(path, list, version := 1, by := 0, bench := 0) {
	local out := ";the fleet's servers - written by the macro, safe to read by hand`r`n`r`n"
		. fleet_MetaSection(version, by, bench)
	local keys := [], s

	for s, _ in list
		keys.Push(s)
	roster_Sort(keys)
	for _, s in keys {
		out .= "[" s "]`r`n"
		for _, k in servers_Keys()
			out .= StrTitle(k) "=" list[s].%k% "`r`n"
		out .= "`r`n"
	}
	return fleet_WriteWhole(path, out)
}
