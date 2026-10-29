;The Fleet wire protocol - one frame per line
;
;A frame is a verb followed by named fields:
;
;	HELLO row=2 name=fuzzy%201 secret=hunter2
;
;Fields are unordered, and a reader ignores any it does not recognise. That is
;deliberate: it lets one side of the fleet be updated before the other without
;the older side choking on a field it has never heard of.
;
;Three characters are percent-encoded in values, and only three: the space that
;separates fields, the percent that does the encoding, and the newline that ends
;a frame. Everything else - accents included - travels as plain UTF-8, which the
;socket layer already carries correctly.

;Encode one value for the wire.
fleet_Escape(v) {
	v := StrReplace(v, "%", "%25")
	v := StrReplace(v, " ", "%20")
	v := StrReplace(v, "`r", "%0D")
	v := StrReplace(v, "`n", "%0A")
	return v
}
;And back. Percent last, so an escaped percent cannot be re-read as an escape.
fleet_Unescape(v) {
	v := StrReplace(v, "%20", " ")
	v := StrReplace(v, "%0D", "`r")
	v := StrReplace(v, "%0A", "`n")
	v := StrReplace(v, "%25", "%")
	return v
}

;Build a frame. fields is a Map of name to value; an empty Map is fine.
fleet_Frame(verb, fields := "") {
	local line := verb, k, v

	if IsObject(fields)
		for k, v in fields
			line .= " " k "=" fleet_Escape(v)
	return line
}

;Take a frame apart. Returns an object with .verb and .fields, or 0 if the line
;is not a frame at all. A field without an equals sign is skipped rather than
;treated as an error - see the note about unknown fields above.
fleet_Parse(line) {
	local parts, out, first := 1, at, k, v

	line := Trim(line)
	if (line = "")
		return 0
	out := { verb: "", fields: Map() }
	out.fields.CaseSense := 0
	for _, part in StrSplit(line, " ") {
		if (part = "")
			continue
		if first {
			out.verb := StrUpper(part), first := 0
			continue
		}
		if !(at := InStr(part, "="))
			continue
		k := SubStr(part, 1, at - 1)
		v := fleet_Unescape(SubStr(part, at + 1))
		out.fields[k] := v
	}
	return (out.verb = "") ? 0 : out
}

;Read a field, with a default for the ones that were not sent.
fleet_Field(frame, name, default := "") {
	return (IsObject(frame) && frame.fields.Has(name)) ? frame.fields[name] : default
}

;A short, stable fingerprint of the shared secret.
;
;The discovery beacon has to say which fleet it belongs to, and it goes out to
;every machine on the network in clear - so it carries this rather than the
;secret itself. It is not a security measure and does not pretend to be: the
;secret is still checked properly over TCP when a macro says HELLO. This only
;stops two fleets sharing a network from trying to join each other.
;
;FNV-1a, because it is four lines and the only property needed is that the same
;secret always gives the same answer.
fleet_Fingerprint(secret) {
	local h := 2166136261

	Loop Parse secret {
		h := (h ^ (Ord(A_LoopField) & 0xFF)) & 0xFFFFFFFF
		h := (h * 16777619) & 0xFFFFFFFF
	}
	return Format("{:08x}", h)
}

;A secret nobody has to type.
;
;The coordinator makes one the first time it runs and hands it out during
;binding, so the shared word is never carried from machine to machine by a
;person. The alphabet leaves out the characters that get misread when someone
;does end up reading it aloud - no l against 1, no O against 0.
fleet_NewSecret() {
	static alphabet := "abcdefghjkmnpqrstuvwxyz23456789"
	local out := ""

	Loop 10
		out .= SubStr(alphabet, Random(1, StrLen(alphabet)), 1)
	return out
}

;What a macro does with a beacon of its own fleet, given the term it carries,
;the highest term this macro has obeyed, and whether it is connected.
;
;"ignore" a lower term: that coordinator has been replaced and has not noticed,
;and a macro that latched onto it would obey stale orders while the fleet ran
;elsewhere - P3, the split brain. "switch" to a higher one while connected: the
;fleet has moved on and this macro is talking to the past. "note" otherwise,
;which records where the fleet is. A beacon with no term comes from an older
;coordinator and is not held against it, and a macro that has obeyed nobody
;yet has nothing to compare.
fleet_BeaconVerdict(beaconTerm, myTerm, connected) {
	if (!beaconTerm || !myTerm)
		return "note"
	if (beaconTerm < myTerm)
		return "ignore"
	return ((beaconTerm > myTerm) && connected) ? "switch" : "note"
}

;Turn the durations a ROSTER frame carries back into times on this machine's
;clock: "left" of a guiding star into "until", "age" of the last word into
;"seen". A frame from an older coordinator carries only the absolute times,
;and those are left as they came.
;
;The times used to travel as they were, read on one machine's clock and
;counted down against another's: two minutes of drift between PCs made a
;countdown two minutes wrong, and ten made "last heard from" meaningless.
fleet_LocalTimes(fields, now) {
	if (fields.Has("left") && (fields["left"] != ""))
		fields["until"] := (Integer(fields["left"]) > 0) ? now + Integer(fields["left"]) : 0
	if (fields.Has("age") && (fields["age"] != ""))
		fields["seen"] := now - Integer(fields["age"])
	return fields
}
