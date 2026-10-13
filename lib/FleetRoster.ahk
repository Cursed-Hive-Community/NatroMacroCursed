;The fleet roster - who exists, and what each account is for.
;
;This is the one thing configured centrally rather than on every machine. A
;macro carries a single local setting, its row number; everything else about it
;lives here and reaches it through the coordinator's ROSTER frames. Seven macros
;otherwise mean seven places to keep in step, and they never stay in step.
;
;It is an ini because Natro's settings already are, and because a file you can
;open and read when something is wrong is worth more than a format that is
;pleasant to parse:
;
;	[2]
;	Name=fuzzy 1
;	Role=fuzzy
;	User=SomeRobloxName
;	Machine=LAPTOP-TIROU
;	Owner=0
;
;Role is one of main, fuzzy, tad, guid, atk. User is the exact Roblox username,
;needed only to force a kick. Owner marks the account that owns the private
;server, since it is the only one whose /kick does anything.
;
;Machine is not edited and is not what the panel displays - a macro says where
;it is running every time it connects, and that is the live truth. It is here
;only so a second setup of the same account can be recognised as the same
;account and given its old row back instead of a new one.

;Every role the fleet knows, in the order the panel offers them.
roster_Roles() {
	return ["main", "fuzzy", "tad", "guid", "atk"]
}

;Read the roster. Returns a Map of row number to its entry, empty if the file is
;not there yet - a fleet with nobody in it is a legitimate starting state, not an
;error to report.
roster_Load(path) {
	local rows := Map(), section, body, line, at, k, v, entry

	if !FileExist(path)
		return rows
	section := 0
	Loop Parse FileRead(path, "UTF-8"), "`n", "`r" {
		line := Trim(A_LoopField)
		if ((line = "") || (SubStr(line, 1, 1) = ";"))
			continue
		if (SubStr(line, 1, 1) = "[") {
			section := Integer(Trim(SubStr(line, 2, StrLen(line) - 2)))
			if (section > 0)
				rows[section] := { row: section, name: "row " section, role: "guid"
					, user: "", machine: "", owner: 0 }
			continue
		}
		if (!section || !rows.Has(section) || !(at := InStr(line, "=")))
			continue
		k := StrLower(Trim(SubStr(line, 1, at - 1)))
		v := Trim(SubStr(line, at + 1))
		entry := rows[section]
		switch k {
			case "name":  entry.name := v
			case "role":  entry.role := StrLower(v)
			case "user":  entry.user := v
			case "machine": entry.machine := v
			case "owner": entry.owner := (v = "1") ? 1 : 0
		}
	}
	return rows
}

;Write it back, rows in order so the file stays readable after an edit.
;
;Through a temporary file and a move, rather than a delete and an append. Two
;processes write this one file - the coordinator when a macro binds or leaves,
;and the roster editor in any macro's settings window - and both of them are
;read on a one second timer. A delete followed by an append leaves a moment
;when the file is missing or half written, and a reader landing in that moment
;sees a fleet with nobody in it; on the coordinator's side that used to mean
;striking every account off at once.
;
;The header line is there so the file is never zero bytes long, which is the
;one case a move cannot be told apart from a failure.
roster_Save(path, rows) {
	local out := ";the fleet roster - written by the macro, safe to read by hand`r`n`r`n"
	local keys := [], r, tmp := path ".tmp"

	for r, _ in rows
		keys.Push(r)
	roster_Sort(keys)
	for _, r in keys {
		out .= "[" r "]`r`n"
		out .= "Name=" rows[r].name "`r`n"
		out .= "Role=" rows[r].role "`r`n"
		out .= "User=" rows[r].user "`r`n"
		out .= "Machine=" rows[r].machine "`r`n"
		out .= "Owner=" rows[r].owner "`r`n`r`n"
	}
	try FileDelete tmp
	try FileAppend out, tmp, "UTF-8"
	if !FileExist(tmp)
		return 0
	;overwrite, so the swap is one rename and a reader sees either the old file
	;whole or the new one whole
	try FileMove tmp, path, 1
	return !FileExist(tmp)
}

;Row numbers ascending. Small arrays, so the simplest sort that is obviously
;correct beats a clever one.
roster_Sort(keys) {
	local i, j, tmp

	i := 2
	while (i <= keys.Length) {
		tmp := keys[i], j := i - 1
		while ((j >= 1) && (keys[j] > tmp))
			keys[j + 1] := keys[j], j--
		keys[j + 1] := tmp
		i++
	}
	return keys
}
