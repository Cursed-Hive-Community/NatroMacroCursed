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
;Kind is main or reserve, and exactly one entry is the main. Owner is a roster
;row number, 0 when nobody has said. Slot numbers are stable and never reused,
;so a control that points at one keeps pointing at the same server after
;another is deleted.

;Read the servers.
;
;A missing file is not an empty list - a fleet has a main server before anybody
;has pasted a link into it, so it is one unfilled main. That also keeps the
;broadcast non-empty, which matters: the generation number that makes a
;deletion converge travels on the entries themselves.
servers_Load(path) {
	local list := Map(), slot, line, at, k, v, entry

	slot := 0
	if FileExist(path) {
		Loop Parse FileRead(path, "UTF-8"), "`n", "`r" {
			line := Trim(A_LoopField)
			if ((line = "") || (SubStr(line, 1, 1) = ";"))
				continue
			if (SubStr(line, 1, 1) = "[") {
				slot := Integer(Trim(SubStr(line, 2, StrLen(line) - 2)))
				if (slot > 0)
					list[slot] := { slot: slot, name: "server " slot, link: ""
						, owner: 0, kind: "reserve" }
				continue
			}
			if (!slot || !list.Has(slot) || !(at := InStr(line, "=")))
				continue
			k := StrLower(Trim(SubStr(line, 1, at - 1)))
			v := Trim(SubStr(line, at + 1))
			entry := list[slot]
			switch k {
				case "name":  entry.name := v
				case "link":  entry.link := v
				case "owner": entry.owner := Integer(v != "" ? v : 0)
				case "kind":  entry.kind := (StrLower(v) = "main") ? "main" : "reserve"
			}
		}
	}
	if !list.Count
		list[1] := { slot: 1, name: "Main", link: "", owner: 0, kind: "main" }
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
servers_Save(path, list) {
	local out := ";the fleet's servers - written by the macro, safe to read by hand`r`n`r`n"
	local keys := [], s

	for s, _ in list
		keys.Push(s)
	roster_Sort(keys)
	for _, s in keys {
		out .= "[" s "]`r`n"
		out .= "Name=" list[s].name "`r`n"
		out .= "Link=" list[s].link "`r`n"
		out .= "Owner=" list[s].owner "`r`n"
		out .= "Kind=" list[s].kind "`r`n`r`n"
	}
	return fleet_WriteWhole(path, out)
}
