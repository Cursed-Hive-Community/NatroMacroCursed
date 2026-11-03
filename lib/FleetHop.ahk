;The guid hop - who sits in the main server, beat by beat
;
;A guiding star gives every player in the field it lands on 1.25 times their
;pollen, but it only lands on a field the main farms - a "blue field" - by
;luck, and it is gone the moment the account that fired it leaves. There are
;more guids than seats. So guids charge their 250 tokens in a reserve server,
;stop at a threshold so the star is not wasted there, and take a seat in the
;main only to fire. One that lands on a blue field stays for the star's ten
;minutes; one that lands anywhere else goes back at once to charge again.
;
;The rules, all the user's:
;
;- never moved: the main; a tad or fuzzy, except to make room for the atk at
;  Mondo; a guid whose star is running on a blue field;
;- the atk sits in the main for Mondo and no longer: it says so itself, by the
;  extensions' own timer (ext_mondoDueAt - from :59, until its Mondo is done or
;  :14). It takes a free seat, else a tad's
;  (the first in roster order), else a fuzzy's, else a guid's with no star
;  running. It beats a guid that is ready at the same time. After Mondo it
;  leaves, and whoever gave up a seat has it back before any waiting guid;
;- a guid waiting for a seat: one stopped at the threshold first, the longest
;  waiting of them first; then the others by most tokens;
;- a stopped guid waiting takes the seat of a seated guid that is still
;  charging - below the threshold, no star - which goes back to charge.
;
;fleet_HopPlan is the whole of it, and it reads nothing but its arguments, so
;ExtensionSelfTest checks it against a table of situations.

;The fields a guiding star can land on: Natro's fieldnamelist and its
;guiding_star_<field> notice images, the same seventeen.
fleet_HopFields() {
	return ["Bamboo", "Blue Flower", "Cactus", "Clover", "Coconut", "Dandelion", "Mountain Top"
		, "Mushroom", "Pepper", "Pine Tree", "Pineapple", "Pumpkin", "Rose", "Spider"
		, "Strawberry", "Stump", "Sunflower"]
}
;A field's name compared without case or spaces: the notice images name them
;PineTree, the windows Pine Tree.
fleet_HopKey(name) {
	return StrLower(StrReplace(name, " "))
}
;The blue fields as stored on the main server, Pine Tree|Rose, as a set.
fleet_HopBlue(text) {
	local m := Map(), f

	for _, f in StrSplit(text, "|")
		if (Trim(f) != "")
			m[fleet_HopKey(Trim(f))] := 1
	return m
}

;Where an account is, or is on its way to.
fleet_HopWhere(p, state) {
	return state.pending.Has(p.row) ? state.pending[p.row].to : p.server
}

;The moves to make now: an array of {row, to, why}, to being "main" or
;"reserve".
;
;peers: row -> {row, role, online, present, server, charge, guidingField,
;guidingUntil, waitSince}. server is main, reserve, or "" for a server that is
;none of the fleet's - a main link changed by hand, a public fallback - which
;counts as out of the main like the reserve. online says it can be given an order. present says
;it is to be counted where it last was, which the caller keeps true for a while
;after a macro goes quiet - its Roblox may well still be in the server. charge
;is -1 when it has not been read.
;
;opt: {now, capacity, threshold, blue (fleet_HopBlue), mondo}. mondo is whether
;the atk says it wants its seat now.
;
;state is kept by the caller between beats and updated here: pending, row ->
;{to, at}, the moves ordered and not yet seen done; yielded, the rows that gave
;their seat to the atk.
fleet_HopPlan(peers, opt, state) {
	local orders := [], rows := [], row, p, occupied := 0, free, atk := 0, victim, w, s

	;a move is done once the account reports the server it was sent to, and
	;given up after three minutes - a join that never happened must not hold a
	;seat for ever
	for row, pend in state.pending.Clone()
		if (!peers.Has(row) || peers[row].server = pend.to || opt.now - pend.at > 180)
			state.pending.Delete(row)
	for row, p in peers {
		rows.Push(row)
		if (p.present && fleet_HopWhere(p, state) = "main")
			occupied++
		if (p.role = "atk" && p.online)
			atk := p
	}
	free := opt.capacity - occupied

	move(p, to, why) {
		orders.Push({row: p.row, to: to, why: why})
		state.pending[p.row] := {to: to, at: opt.now}
		free += (to = "main") ? -1 : 1
	}
	inMain(p) => fleet_HopWhere(p, state) = "main"
	;a guid that may give up its seat: in the main and no star running at all.
	;Its own names are declared local: a nested function that assigns a name
	;the outer one uses is assigning the outer one's, and r is the loop variable
	;of every loop below.
	free_guid(allowStopped) {
		local best := 0, q, k, i
		for k, i in rows {
			q := peers[i]
			if (q.role != "guid" || !q.online || !inMain(q) || q.guidingUntil > opt.now)
				continue
			if (!allowStopped && q.charge >= opt.threshold)
				continue
			if (!best || q.charge < best.charge)
				best := q
		}
		return best
	}
	first(role) {
		local k, i
		for k, i in rows
			if (peers[i].role = role && peers[i].online && inMain(peers[i]))
				return peers[i]
		return 0
	}

	;the main is never moved out, and is always let back in
	for _, r in rows
		if (peers[r].role = "main" && peers[r].online && !inMain(peers[r]))
			move(peers[r], "main", "the main belongs in the main")
	;a star that landed anywhere but a blue field is no use to the fleet
	for _, r in rows {
		p := peers[r]
		if (p.role = "guid" && p.online && inMain(p) && p.guidingUntil > opt.now
			&& !opt.blue.Has(fleet_HopKey(p.guidingField)))
			move(p, "reserve", "its star landed on " p.guidingField ", not a blue field")
	}
	;the atk, around Mondo
	if (atk && opt.mondo && !inMain(atk)) {
		if (free <= 0) {
			victim := first("tad")
			if !victim
				victim := first("fuzzy")
			if !victim
				victim := free_guid(1)
			if victim {
				move(victim, "reserve", "making room for the atk at Mondo")
				state.yielded[victim.row] := 1
			}
		}
		if (free > 0)
			move(atk, "main", "Mondo")
	} else if (atk && !opt.mondo && inMain(atk))
		move(atk, "reserve", "Mondo is over")
	;residents back first: whoever gave a seat to the atk once Mondo is over, and
	;at any time a tad or fuzzy that is out for another reason - a restart into
	;the reserve
	for _, r in rows {
		p := peers[r]
		if ((p.role != "tad" && p.role != "fuzzy") || !p.online || inMain(p))
			continue
		if (opt.mondo && state.yielded.Has(r))
			continue
		if (free <= 0 && (s := free_guid(1)))
			move(s, "reserve", "a resident needs its seat back")
		if (free > 0) {
			move(p, "main", state.yielded.Has(r) ? "back after Mondo" : "residents sit in the main")
			;a Map throws on deleting a key it does not have, and a resident
			;out for any other reason - a restart into the reserve - is not in it
			if state.yielded.Has(r)
				state.yielded.Delete(r)
		}
	}
	;the guids waiting, best first
	waiting := []
	for _, r in rows {
		p := peers[r]
		if (p.role = "guid" && p.online && !inMain(p))
			waiting.Push(p)
	}
	waiting := fleet_HopQueue(waiting, opt.threshold)
	for _, w in waiting {
		if (free <= 0 && w.charge >= opt.threshold && (s := free_guid(0)))
			move(s, "reserve", "swapped for a guid ready to fire")
		if (free <= 0)
			break
		move(w, "main", (w.charge >= opt.threshold) ? "ready to fire" : "a seat is free to charge in")
	}
	return orders
}
;Guids waiting for a seat, best first: stopped at the threshold, longest
;waiting first - without that, two guids at the same count would pass each
;other for ever - then by most tokens, and unread charges last.
fleet_HopQueue(list, threshold) {
	local out := list.Clone(), i, t
	better(a, b) {
		local sa := a.charge >= threshold, sb := b.charge >= threshold
		if (sa != sb)
			return sa
		if sa
			return a.waitSince < b.waitSince
		return a.charge > b.charge
	}
	loop out.Length - 1 {
		i := A_Index + 1
		while (i > 1 && better(out[i], out[i - 1])) {
			t := out[i], out[i] := out[i - 1], out[i - 1] := t, i--
		}
	}
	return out
}
