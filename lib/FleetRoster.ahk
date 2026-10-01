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
;	Owner=0
;
;Role is one of main, fuzzy, tad, guid, atk. User is the exact Roblox username,
;needed only to force a kick. Owner marks the account that owns the private
;server, since it is the only one whose /kick does anything.

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
					, user: "", owner: 0 }
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
			case "owner": entry.owner := (v = "1") ? 1 : 0
		}
	}
	return rows
}

;Write it back, rows in order so the file stays readable after an edit.
roster_Save(path, rows) {
	local out := "", keys := [], r

	for r, _ in rows
		keys.Push(r)
	roster_Sort(keys)
	for _, r in keys {
		out .= "[" r "]`r`n"
		out .= "Name=" rows[r].name "`r`n"
		out .= "Role=" rows[r].role "`r`n"
		out .= "User=" rows[r].user "`r`n"
		out .= "Owner=" rows[r].owner "`r`n`r`n"
	}
	try FileDelete path
	try FileAppend out, path, "UTF-8"
	return 1
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

;The account that owns the private server, or 0. Only one row should carry the
;flag; if several do, the lowest wins rather than the answer being undefined.
roster_Owner(rows) {
	local keys := [], r

	for r, _ in rows
		keys.Push(r)
	roster_Sort(keys)
	for _, r in keys
		if rows[r].owner
			return r
	return 0
}
