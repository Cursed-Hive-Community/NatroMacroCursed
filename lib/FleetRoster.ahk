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
;
;The [fleet] section at the top carries the version this configuration is on
;and the row that wrote it. Those two are what tell a newer copy from an older
;one, and the file's own timestamp cannot: a replica is written when it
;arrives, so a machine holding a stale copy has a newer timestamp on it than
;the machine holding the current one. Without a version, a macro that
;reconnected late and became coordinator would serve its stale copy and every
;up-to-date macro would write it over their good one.
;
;	[fleet]
;	Version=7
;	By=1
;	Bench=0
;
;Bench marks a configuration the test bench produced, and it exists because of
;a path nobody would notice until it had happened: point a real macro at the
;bench, and the macro replicates the bench's configuration into its own files.
;Point it back at the real fleet, and it hands that configuration up - and if
;its version happens to be the higher one, the real coordinator takes it. A
;test tool would have replaced a real roster. So a marked configuration loses
;to an unmarked one whatever its version, everywhere, and the mark travels on
;the wire with it.
;
;Role is one of main, fuzzy, tad, guid, atk. User is the exact Roblox username,
;needed only to force a kick.
;
;Who owns a private server is not here. It was one flag on one row, and one
;flag cannot say that two servers have two different owners - it lives on the
;server now, in fleet_servers.ini.
;
;Machine is not edited and is not what the panel displays - a macro says where
;it is running every time it connects, and that is the live truth. It is here
;only so a second setup of the same account can be recognised as the same
;account and given its old row back instead of a new one.

;Every role the fleet knows, in the order the panel offers them.
;
;	main   leads: it farms to its own plan and the fleet follows it
;	fuzzy  improves the field it stands in, so it stands where the main is
;	tad    the same, by a different bee
;	guid   carries the guiding star, which is a job of its own
;	atk    kills Mondo Chick. It leaves for Mountain Top a minute before the
;	       hour so that it is standing on the spawn when the chick appears,
;	       and the main arrives at the same place at the same moment - the
;	       whole point being to put the chick down between them as fast as
;	       it can be done
;
;Only main, fuzzy and tad change what a macro does today. guid and atk are
;offered so that the roster can describe the whole fleet before the work that
;acts on them exists - the guiding star queue for one, and the Mondo departure
;in extensions\interrupts.ahk for the other, which says there why it waits.
roster_Roles() {
	return ["main", "fuzzy", "tad", "guid", "atk"]
}

;Does an account of this role follow the main into the field it farms?
;
;Fuzzy and tad, and nothing else. Both of them improve the field they are
;standing in, so standing where the main stands is the whole of the job.
;
;A guid and an atk are not idle, and an atk's work is in fact alongside the
;main - on the Mondo spawn at the top of the hour. But neither of them trails
;the main around the fields it farms, which is all this question is about: a
;rendezvous at a fixed time and place is a different kind of order from "stand
;wherever the main is standing", and it needs no field to be forwarded at all.
;
;Here rather than in the two places that ask, because this was written out
;twice - once in the coordinator and once in the macro - and the window that
;offered the setting ended up calling them all "residents", which reads as
;every account that is not the main. A rule with one name cannot drift from
;the label on the switch that controls it.
roster_Follows(role) {
	return (role = "fuzzy") || (role = "tad")
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
			;a section that is not a number is not a row - the version lives in
			;[fleet]. Checked rather than converted, because Integer() throws on
			;anything that is not a number, and a configuration file is exactly
			;the place where somebody's typo would otherwise stop the whole
			;roster from loading.
			section := fleet_SectionNumber(line)
			if (section > 0)
				rows[section] := { row: section, name: "row " section, role: "guid"
					, user: "", machine: "" }
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
		}
	}
	return rows
}

;Write it back, rows in order so the file stays readable after an edit. The
;header line is there so the file is never zero bytes long - see
;fleet_WriteWhole, which does the writing, for why that matters.
;
;version and by are not optional in spirit, whatever the defaults say: every
;writer knows which version it is producing, and a file written without one
;loses to every other copy in the fleet.
roster_Save(path, rows, version := 1, by := 0, bench := 0) {
	local out := ";the fleet roster - written by the macro, safe to read by hand`r`n`r`n"
		. fleet_MetaSection(version, by, bench)
	local keys := [], r

	for r, _ in rows
		keys.Push(r)
	roster_Sort(keys)
	for _, r in keys {
		out .= "[" r "]`r`n"
		out .= "Name=" rows[r].name "`r`n"
		out .= "Role=" rows[r].role "`r`n"
		out .= "User=" rows[r].user "`r`n"
		out .= "Machine=" rows[r].machine "`r`n`r`n"
	}
	return fleet_WriteWhole(path, out)
}

;The [fleet] section every configuration file opens with.
fleet_MetaSection(version, by, bench := 0) {
	return "[fleet]`r`nVersion=" version "`r`nBy=" by
		. "`r`nBench=" (bench ? 1 : 0) "`r`n`r`n"
}

;Which row a section heading names, or 0 when it does not name one.
fleet_SectionNumber(line) {
	local name := Trim(SubStr(line, 2, StrLen(line) - 2))

	return fleet_IsNumber(name) ? Integer(name) : 0
}

;Is this text a plain integer? Asked before converting, because Integer()
;throws on anything else and these files can be edited by hand.
fleet_IsNumber(v) {
	return (v != "") && RegExMatch(v, "^-?\d+$")
}

;An integer from whatever a file said, including nothing at all.
fleet_Num(v) {
	return fleet_IsNumber(v) ? Integer(v) : 0
}

;Was this configuration made by the test bench? Absent means no, so every file
;and every frame written before the mark existed reads as a real one.
fleet_IsBench(cfg) {
	return (cfg.HasOwnProp("bench") && cfg.bench) ? 1 : 0
}

;The version a configuration file is on, and the row that wrote it.
;
;Read separately from the entries so that every caller of roster_Load and
;servers_Load carries on working unchanged. These files are a few hundred bytes
;and read once per change, so reading one twice costs nothing worth saving.
fleet_ConfigVersion(path) {
	local line, at, k, v, out := { version: 0, by: 0, bench: 0 }, inMeta := 0

	if !FileExist(path)
		return out
	Loop Parse FileRead(path, "UTF-8"), "`n", "`r" {
		line := Trim(A_LoopField)
		if ((line = "") || (SubStr(line, 1, 1) = ";"))
			continue
		if (SubStr(line, 1, 1) = "[") {
			inMeta := (Trim(line, "[]") = "fleet")
			continue
		}
		if (!inMeta || !(at := InStr(line, "=")))
			continue
		k := StrLower(Trim(SubStr(line, 1, at - 1)))
		v := Trim(SubStr(line, at + 1))
		if (k = "version")
			out.version := fleet_Num(v)
		else if (k = "by")
			out.by := fleet_Num(v)
		else if (k = "bench")
			out.bench := fleet_Num(v) ? 1 : 0
	}
	return out
}

;Should configuration a replace configuration b?
;
;A configuration the test bench produced loses to one it did not, whatever the
;versions say - see the note on Bench at the top of this file. That rule comes
;first because it is the only one protecting a real fleet from a tool, and a
;version cannot carry the distinction: the bench is free to invent any number
;it likes, and being able to is half of what it is for.
;
;Otherwise a higher version always wins. Equal versions written by different rows is the
;one case a version cannot settle - both sides of a network split were edited
;separately - and the lowest row wins it. Lowest rather than highest for no
;deeper reason than that it is the same rule the coordinator election uses, and
;two rules that disagree are one rule too many. What matters is that it is
;decided the same way on every machine without anybody sending a message about
;it, and that the copy that loses is kept rather than thrown away.
fleet_ConfigBeats(a, b) {
	if (fleet_IsBench(a) != fleet_IsBench(b))
		return !fleet_IsBench(a)
	if (a.version != b.version)
		return (a.version > b.version)
	if (a.by = b.by)
		return 0
	;by=0 means nobody said, which cannot be allowed to win a tie
	if !a.by
		return 0
	return (!b.by || (a.by < b.by))
}

;Replace a whole shared configuration file in one step.
;
;Both files here - the roster and the servers - are written by two processes and
;read by both on a one second timer: the coordinator writes when a macro binds
;or leaves, and the editor in a macro's settings window writes when somebody
;changes something. A delete followed by an append leaves a moment when the
;file is missing or half written, and a reader landing in that moment sees a
;fleet with nobody in it; on the coordinator's side that used to mean striking
;every account off at once.
;
;So: a temporary file, then a move over the target. A reader sees either the
;old file whole or the new one whole, and never the gap.
fleet_WriteWhole(path, text) {
	local tmp := path ".tmp"

	try FileDelete tmp
	try FileAppend text, tmp, "UTF-8"
	;an empty file is the one case a move cannot be told apart from a failure,
	;which is why every caller writes a header line
	if !FileExist(tmp)
		return 0
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
