;Passives - reading the row of passive abilities above the hotbar
;
;The guid hop needs to know how far each guid is towards its next Guiding Star:
;the white number on the star's icon, 0 to 249, or, for five minutes after it
;fires, the salmon timer that replaces it. Nothing in Natro reads either.
;
;The row is found by the ring every passive icon is drawn in, not by any one
;icon: the star can sit anywhere in the row and the row changes with what the
;player wears. The game does not scale this part of its interface, so the ring
;is the same 37 pixels across at every window size measured (1300x669 to
;2560x1440), and nothing here resizes anything.
;
;Only the top half of the ring is compared. A three-digit number spills over the
;bottom half, and on the star that is exactly when it matters: from about 220
;up, the full ring no longer matched the star at all. Measured over 46 captures,
;every visible icon is within 52 of the top half and nothing else on the lower
;half of the screen is closer than 82; 66 sits between them.
;
;Digits are matched against examples, not recognised by rule: each glyph is cut
;out, scaled to 12x18 grey levels and given the label of the nearest example in
;glyphs.txt, or none when it is far from all of them or nearly as close to a
;second digit. A refusal is the safe answer - the caller waits for the next
;read - and over the labelled captures no read has come out wrong.
;
;Reimplemented from a prototype checked on the user's captures; the numbers
;below are its measured values. PassiveSelfTest replays the labelled rows in
;tools\passive-rows.

;Distance from one icon's centre to the next, at every window size measured.
ext_passiveStep() {
	return 40
}
;The assets, loaded once per folder: the ring needle, the wiki icons to tell the
;passives apart, and the digit examples.
ext_passiveAssets(dir := "nm_image_assets\passives") {
	static cache := Map()
	if cache.Has(dir)
		return cache[dir]
	a := {ring: Gdip_CreateBitmapFromFile(dir "\ring.png"), icons: Map(), white: [], salmon: []}
	Loop Files dir "\icons\*.png" {
		pBM := Gdip_CreateBitmapFromFile(A_LoopFileFullPath)
		px := ext_passiveLock(pBM)
		a.icons[SubStr(A_LoopFileName, 1, -4)] := ext_passiveDisc(px, 16, 16)
		ext_passiveUnlock(px), Gdip_DisposeImage(pBM)
	}
	if FileExist(dir "\glyphs.txt")
		ext_passiveLoadGlyphs(FileRead(dir "\glyphs.txt"), a)
	return cache[dir] := a
}
;glyphs.txt: one example a line, label, w for white or s for salmon, then the
;216 grey levels.
ext_passiveLoadGlyphs(text, a) {
	Loop Parse text, "`n", "`r" {
		if (A_LoopField = "" || SubStr(A_LoopField, 1, 1) = "#")
			continue
		f := StrSplit(A_LoopField, "`t")
		v := []
		for n in StrSplit(f[3], ",")
			v.Push(Integer(n))
		((f[2] = "s") ? a.salmon : a.white).Push({label: f[1], v: v})
	}
}

;--- pixels -------------------------------------------------------------------

ext_passiveLock(pBM) {
	Gdip_GetImageDimensions(pBM, &w, &h)
	Gdip_LockBits(pBM, 0, 0, w, h, &stride, &scan, &data, 1)
	return {pBM: pBM, w: w, h: h, stride: stride, scan: scan, data: data}
}
ext_passiveUnlock(px) {
	data := px.data
	Gdip_UnlockBits(px.pBM, &data)
}
ext_passiveARGB(px, x, y) {
	return NumGet(px.scan, y * px.stride + x * 4, "UInt")
}
;The cooldown timer's colour, against the grass, flowers and sky behind it.
ext_passiveSalmon(c) {
	r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
	return (r > 140) && (r - g > 55) && (r - b > 55) && (g < 140)
}
;The picture inside an icon's ring, as r, g, b in a flat array: 32x32 from the
;top left at (cx-16, cy-16), inside 0.62 of the radius.
ext_passiveDisc(px, cx, cy) {
	v := []
	loop 32 {
		y := A_Index - 1
		loop 32 {
			x := A_Index - 1
			if ((x - 15.5) ** 2 + (y - 15.5) ** 2 <= 98.4) {
				c := ext_passiveARGB(px, cx - 16 + x, cy - 16 + y)
				v.Push((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF)
			}
		}
	}
	return v
}

;--- the row ------------------------------------------------------------------

;The slots, left to right: {x, y, kind}, kind "icon", "cooldown" for a
;see-through icon with a timer under it, or "unknown" for a hole between two
;icons with no timer. A hole between icons is a slot whatever covers it,
;because passives sit side by side. A cooldown at either end of the row is not
;returned: its ring is too faint to tell from red flowers, and no capture has
;one - the guiding star is found there by remembering where it was instead.
ext_passiveRow(pBM, a, x1 := 0, y1 := 0, x2 := 0, y2 := 0) {
	found := ""
	if (Gdip_ImageSearch(pBM, a.ring, &found, x1, y1, x2, y2, 66, , 1, 0) <= 0)
		return []
	;every position within the tolerance is listed, a few per icon: one centre
	;per cluster
	centres := []
	Loop Parse found, "`n" {
		p := StrSplit(A_LoopField, ",")
		if (p.Length < 2)
			continue
		cx := p[1] + 18, cy := p[2] + 18
		for c in centres
			if (Abs(c.x - cx) < 20 && Abs(c.y - cy) < 20) {
				c.sx += cx, c.sy += cy, c.n++
				continue 2
			}
		centres.Push({x: cx, y: cy, sx: cx, sy: cy, n: 1})
	}
	for c in centres
		c.x := Round(c.sx / c.n), c.y := Round(c.sy / c.n)
	;the row is the line holding most of them
	best := 0, rowY := 0
	for c in centres {
		n := 0
		for d in centres
			n += (Abs(d.y - c.y) <= 2)
		if (n > best)
			best := n, rowY := c.y
	}
	xs := []
	for c in centres
		if (Abs(c.y - rowY) <= 2)
			xs.Push(c.x)
	xs := ext_passiveSorted(xs)
	;one run of icons on the 40 pixel lattice, the longest
	step := ext_passiveStep(), seq := [xs[1]], longest := [xs[1]]
	loop xs.Length - 1 {
		gap := xs[A_Index + 1] - xs[A_Index], k := Round(gap / step)
		if (k >= 1 && Abs(gap - k * step) <= 3)
			seq.Push(xs[A_Index + 1])
		else
			seq := [xs[A_Index + 1]]
		if (seq.Length > longest.Length)
			longest := seq.Clone()
	}
	px := ext_passiveLock(pBM)
	slots := []
	x := longest[1]
	while (x <= longest[longest.Length] + 3) {
		icon := 0
		for v in longest
			if (Abs(v - x) <= 3)
				icon := v
		cx := icon ? icon : x
		;only a hole is asked for a timer: a red icon or red flowers under a
		;visible one put enough salmon-coloured pixels there to pass for one
		kind := icon ? "icon" : ext_passiveTimerUnder(px, cx, rowY) ? "cooldown" : "unknown"
		slots.Push({x: cx, y: rowY, kind: kind})
		x := cx + step
	}
	ext_passiveUnlock(px)
	return slots
}
ext_passiveSorted(arr) {
	out := arr.Clone()
	loop out.Length - 1 {
		i := A_Index + 1
		while (i > 1 && out[i - 1] > out[i]) {
			t := out[i], out[i] := out[i - 1], out[i - 1] := t, i--
		}
	}
	return out
}
;The box under an icon where its number or timer is written.
ext_passiveBox(px, cx, cy) {
	x0 := Max(0, cx - 18), y0 := Max(0, cy + 1)
	return {x0: x0, y0: y0, w: Min(px.w, cx + 24) - x0, h: Min(px.h, cy + 21) - y0}
}
;A timer is written in salmon, a number in white: eight salmon pixels or more
;under the icon - half its radius - is a timer.
ext_passiveTimerUnder(px, cx, cy) {
	b := ext_passiveBox(px, cx, cy), n := 0
	loop b.h {
		y := b.y0 + A_Index - 1
		loop b.w
			n += ext_passiveSalmon(ext_passiveARGB(px, b.x0 + A_Index - 1, y))
	}
	return n >= 8
}

;--- which passive ------------------------------------------------------------

;The wiki icon nearest the picture inside the ring, and how close it and the
;runner-up were. Only meaningful for an icon that is not in cooldown: a
;see-through one is mostly the background.
ext_passiveIcon(px, cx, cy, a) {
	v := ext_passiveDisc(px, cx, cy)
	best := "", d1 := 1e18, d2 := 1e18
	for name, ref in a.icons {
		d := ext_passiveDist(v, ref)
		if (d < d1)
			d2 := d1, d1 := d, best := name
		else if (d < d2)
			d2 := d
	}
	return {name: best, d1: d1, d2: d2}
}
ext_passiveDist(v, w) {
	d := 0
	loop v.Length
		d += (v[A_Index] - w[A_Index]) ** 2
	return d
}

;--- glyphs -------------------------------------------------------------------

;The connected areas of a w x h grid of 0 and 1, eight ways round:
;{x0, y0, x1, y1, n, cells}, cells the 0-based indices of its pixels.
ext_passiveBlobs(m, w, h) {
	seen := Map(), out := []
	loop h {
		y := A_Index - 1
		loop w {
			x := A_Index - 1, i := y * w + x
			if (!m[i + 1] || seen.Has(i))
				continue
			seen[i] := 1, stack := [i], b := {x0: x, y0: y, x1: x, y1: y, n: 0, cells: []}
			while stack.Length {
				j := stack.Pop(), jx := Mod(j, w), jy := j // w
				b.cells.Push(j), b.n++, b.x0 := Min(b.x0, jx), b.x1 := Max(b.x1, jx), b.y0 := Min(b.y0, jy), b.y1 := Max(b.y1, jy)
				loop 3 {
					nx := jx + A_Index - 2
					loop 3 {
						ny := jy + A_Index - 2, k := ny * w + nx
						if (nx >= 0 && nx < w && ny >= 0 && ny < h && m[k + 1] && !seen.Has(k))
							seen[k] := 1, stack.Push(k)
					}
				}
			}
			out.Push(b)
		}
	}
	return out
}
;The bottom line most glyphs stand on, within a pixel.
ext_passiveBase(bl) {
	best := -1, base := 0
	for b in bl {
		n := 0
		for c in bl
			n += (Abs(c.y1 - b.y1) <= 1)
		if (n > best)
			best := n, base := b.y1
	}
	return base
}
;A glyph as 12x18 grey levels: the box of grid g (one value a pixel, row by
;row, w wide) stretched to 0-255, set top centre - or, with th, standing on
;the bottom of a th-tall canvas, so the low lowercase s keeps its place - and
;scaled bilinearly.
ext_passiveVector(g, w, b, th := 0) {
	gw := b.x1 - b.x0 + 1, gh := b.y1 - b.y0 + 1, lo := 255, hi := 0
	loop gh {
		y := b.y0 + A_Index - 1
		loop gw {
			v := g[y * w + b.x0 + A_Index]
			lo := Min(lo, v), hi := Max(hi, v)
		}
	}
	side := Max(gw, Integer((th ? th : gh) * 12 / 18) + 1), ch := Integer(side * 18 / 12) + 1
	ox := (side - gw) // 2, oy := th ? th - gh : 0
	canvas := []
	canvas.Length := side * ch
	loop canvas.Length
		canvas[A_Index] := 0
	loop gh {
		y := A_Index - 1
		loop gw {
			x := A_Index - 1
			if (oy + y >= 0 && oy + y < ch)
				canvas[(oy + y) * side + ox + x + 1] := Round(255 * (g[(b.y0 + y) * w + b.x0 + x + 1] - lo) / Max(1, hi - lo))
		}
	}
	out := []
	loop 18 {
		sy := Min(Max((A_Index - 0.5) * ch / 18 - 0.5, 0), ch - 1), y0 := Floor(sy), y1 := Min(y0 + 1, ch - 1), fy := sy - y0
		loop 12 {
			sx := Min(Max((A_Index - 0.5) * side / 12 - 0.5, 0), side - 1), x0 := Floor(sx), x1 := Min(x0 + 1, side - 1), fx := sx - x0
			top := canvas[y0 * side + x0 + 1] * (1 - fx) + canvas[y0 * side + x1 + 1] * fx
			bot := canvas[y1 * side + x0 + 1] * (1 - fx) + canvas[y1 * side + x1 + 1] * fx
			out.Push(Round(top * (1 - fy) + bot * fy))
		}
	}
	return out
}
;How much of what surrounds a blob is dark: a digit is drawn with a black
;outline all round, where a strip of white background left between a digit and
;a coloured edge is bordered by that colour on one side. dark is a grid of 0
;and 1 like the blob's, with its own top row at y0 of the blob's grid.
ext_passiveOutline(b, dark, w, h) {
	inside := Map(), seen := Map(), n := 0, d := 0
	for j in b.cells
		inside[j] := 1
	for j in b.cells {
		jx := Mod(j, w), jy := j // w
		loop 3 {
			nx := jx + A_Index - 2
			loop 3 {
				ny := jy + A_Index - 2, k := ny * w + nx
				if (nx < 0 || nx >= w || ny < 0 || ny >= h || inside.Has(k) || seen.Has(k))
					continue
				seen[k] := 1, n++, d += dark[k + 1]
			}
		}
	}
	return n ? d / n : 0
}
;The white digits under an icon, left to right, as vectors. Grey is the least
;of the three channels, so only white is bright; a digit is 8 to 16 pixels
;tall. They are cut out a second time inside the band the digits stand in, so
;a digit touching the white of the icon above it comes apart from it instead
;of vanishing with it.
;
;Of what borders a digit, at least 0.45 is its dark outline: measured, every
;digit of 291 labelled numbers is at 0.66 or more, and the two strips of white
;background that were read as a 1 are at 0.26 and 0.28.
ext_passiveWhite(px, cx, cy, minDark := 0.45, &outlines := 0) {
	b := ext_passiveBox(px, cx, cy), w := b.w, h := b.h, g := [], m := [], dk := []
	loop h {
		y := b.y0 + A_Index - 1
		loop w {
			c := ext_passiveARGB(px, b.x0 + A_Index - 1, y)
			v := Min((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF)
			g.Push(v), m.Push(v > 160), dk.Push(Max((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF) < 100)
		}
	}
	cand := []
	for c in ext_passiveBlobs(m, w, h) {
		ch := c.y1 - c.y0 + 1
		if (ch >= 8 && ch <= 16 && c.x1 - c.x0 + 1 <= ch && c.n >= 6)
			cand.Push(c)
	}
	if !cand.Length
		return []
	base := ext_passiveBase(cand), tall := 0
	for c in cand
		if (Abs(c.y1 - base) <= 1)
			tall := Max(tall, c.y1 - c.y0 + 1)
	top := Max(0, base - tall + 1), bandH := base + 1 - top, bm := [], bd := []
	loop bandH {
		y := top + A_Index - 1
		loop w
			bm.Push(m[y * w + A_Index]), bd.Push(dk[y * w + A_Index])
	}
	outlines := []
	digits := []
	for c in ext_passiveBlobs(bm, w, bandH) {
		c.y0 += top, c.y1 += top, ch := c.y1 - c.y0 + 1
		;a digit never touches the side of the box; a bright background cut up
		;by the band does. One starting past 36 is the next icon's number.
		if (ch >= 0.7 * tall && c.x1 - c.x0 + 1 <= ch && c.n >= 6 && c.x0 > 0 && c.x1 < w - 1
			&& Abs(c.y1 - base) <= 1 && c.x0 < 36) {
			c.outline := ext_passiveOutline(c, bd, w, bandH)
			outlines.Push(Round(c.outline, 2))
			if (c.outline >= minDark)
				digits.Push(c)
		}
	}
	out := []
	for c in ext_passiveByX(digits)
		out.Push(ext_passiveVector(g, w, c))
	return out
}
;The salmon timer under an icon: glyphs left to right, each {colon} or {v},
;with the colon kept only between two glyphs and once - a red flower's dot at
;either end is not one. Features are the red channel, where the timer is
;brightest against its own black outline.
ext_passiveSalmonGlyphs(px, cx, cy) {
	b := ext_passiveBox(px, cx, cy), w := b.w, h := b.h, g := [], m := []
	loop h {
		y := b.y0 + A_Index - 1
		loop w {
			c := ext_passiveARGB(px, b.x0 + A_Index - 1, y)
			g.Push((c >> 16) & 0xFF), m.Push(ext_passiveSalmon(c))
		}
	}
	bl := []
	for c in ext_passiveBlobs(m, w, h)
		if (c.x0 > 0 && c.x1 < w - 1)
			bl.Push(c)
	tall := []
	for c in bl {
		ch := c.y1 - c.y0 + 1
		if (ch >= 8 && ch <= 16 && c.n >= 6)
			tall.Push(c)
	}
	if !tall.Length
		return []
	base := ext_passiveBase(tall), th := 0
	for c in tall
		if (Abs(c.y1 - base) <= 1)
			th := Max(th, c.y1 - c.y0 + 1)
	raw := []
	for c in ext_passiveByX(bl) {
		ch := c.y1 - c.y0 + 1
		if (Abs(c.y1 - base) <= 1 && ch >= 0.55 * th && c.x1 - c.x0 + 1 <= ch + 1)
			raw.Push({b: c, v: ext_passiveVector(g, w, c, th)})
		else if (ch <= 0.35 * th && base - th < c.y0 && c.y1 < base && c.n <= 12)
			raw.Push({b: c, colon: 1})
	}
	out := [], colon := 0
	for i, r in raw {
		if !r.HasProp("colon") {
			out.Push(r)
			continue
		}
		before := 0, after := 0
		for j, o in raw
			if !o.HasProp("colon")
				before |= (j < i && o.b.x1 < r.b.x0), after |= (j > i && o.b.x0 > r.b.x1)
		if (before && after && !colon)
			out.Push(r), colon := 1
	}
	return out
}
ext_passiveByX(bl) {
	out := bl.Clone()
	loop out.Length - 1 {
		i := A_Index + 1
		while (i > 1 && out[i - 1].x0 > out[i].x0) {
			t := out[i], out[i] := out[i - 1], out[i - 1] := t, i--
		}
	}
	return out
}
;The label of the nearest example, or "" when it is further than reject from
;all of them or not clearly nearer than the best example of any other label.
ext_passiveLabel(v, refs, reject) {
	best := Map()
	for r in refs {
		;only each label's nearest example counts, so an example already
		;further than that one is dropped a row at a time - the same answer,
		;several times faster
		lim := best.Has(r.label) ? best[r.label] : 1e18, w := r.v, d := 0, i := 0
		loop 18 {
			loop 12
				i++, t := v[i] - w[i], d += t * t
			if (d >= lim)
				break
		}
		if (d < lim)
			best[r.label] := d
	}
	d1 := 1e18, d2 := 1e18, lab := ""
	for l, d in best
		if (d < d1)
			d2 := d1, d1 := d, lab := l
		else if (d < d2)
			d2 := d
	return (d1 > reject || d1 > 0.6 * d2) ? "" : lab
}
;The number under an icon, or "" when there is none or any digit is unsure.
ext_passiveNumber(px, cx, cy, a) {
	s := ""
	for v in ext_passiveWhite(px, cx, cy) {
		if ((l := ext_passiveLabel(v, a.white, 900000)) = "")
			return ""
		s .= l
	}
	return (s = "") ? "" : Integer(s)
}
;The timer under an icon as text - "4:17" or "58s" - or "" when unsure. White
;digits are the same font and stand in for salmon ones that are missing.
ext_passiveTimerText(px, cx, cy, a) {
	static refs := 0, from := 0
	if (from != a)
		refs := a.salmon.Clone(), refs.Push(a.white*), from := a
	s := ""
	for r in ext_passiveSalmonGlyphs(px, cx, cy) {
		if r.HasProp("colon") {
			s .= ":"
			continue
		}
		if ((l := ext_passiveLabel(r.v, refs, 1200000)) = "")
			return ""
		s .= l
	}
	return s
}
;Seconds from a timer's text, or "" when it has neither the m:ss nor the Ns
;shape - which catches most misreads before they become a number.
ext_passiveSeconds(text) {
	if RegExMatch(text, "^(\d+):(\d\d)$", &m)
		return m[1] * 60 + m[2]
	if RegExMatch(text, "^(\d+)s$", &m)
		return Integer(m[1])
	return ""
}

;--- the guiding star ---------------------------------------------------------

;The guiding star's state: {state, value, x, y}. state is "charge" with the
;token count, "cooldown" with the seconds left, or "unseen"; value is "" when
;the digits could not be read. mem holds where the star was last seen and is
;updated: an icon in cooldown is mostly background and cannot be told apart by
;its picture, so the star's cooldown is read where the star last was.
ext_passiveGuidingStar(pBM, a, mem, x1 := 0, y1 := 0, x2 := 0, y2 := 0) {
	slots := ext_passiveRow(pBM, a, x1, y1, x2, y2)
	px := ext_passiveLock(pBM)
	out := {state: "unseen", value: "", x: 0, y: 0}
	for s in slots {
		if (s.kind != "icon")
			continue
		if (ext_passiveIcon(px, s.x, s.y, a).name = "GuidingStarIcon") {
			mem.x := s.x, mem.y := s.y
			out := {state: "charge", value: ext_passiveNumber(px, s.x, s.y, a), x: s.x, y: s.y}
			break
		}
	}
	if (out.state = "unseen" && mem.HasProp("x") && mem.x > 0 && mem.x < px.w && mem.y < px.h) {
		for s in slots
			if (Abs(s.x - mem.x) <= 3 && Abs(s.y - mem.y) <= 3)
				mem.x := s.x, mem.y := s.y
		if ext_passiveTimerUnder(px, mem.x, mem.y)
			out := {state: "cooldown", value: ext_passiveSeconds(ext_passiveTimerText(px, mem.x, mem.y, a)), x: mem.x, y: mem.y}
	}
	ext_passiveUnlock(px)
	return out
}
