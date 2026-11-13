;Notices - the game's text the macro reads, after Roblox's new font
;
;Placing a planter is confirmed by the message the game shows: "already in
;the ..." when one is there, "3 Planters" when no more can go out, "standing"
;when the player is not in a field. Natro found them as pictures of those
;words, and the new font broke all three: a paper planter was placed, the
;game said so, and the macro, not seeing it, threw it again for ever.
;
;The pictures are tried first - cheap, and right if the old font ever comes
;back - then the lower right quarter is read once with Windows OCR for all
;three messages.

;Which notice is showing: "3planters", "already", "standing", or "".
ext_planterNotice() {
	global windowX, windowY, windowWidth, windowHeight
	local pBM, kind

	if (nm_imgSearch("3Planters.png", 30, "lowright")[1] = 0)
		return "3planters"
	if (nm_imgSearch("planteralready.png", 30, "lowright")[1] = 0)
		return "already"
	if (nm_imgSearch("standing.png", 30, "lowright")[1] = 0)
		return "standing"
	GetRobloxClientPos()
	if (windowWidth <= 0)
		return ""
	;the right quarter of the lower half, where the notices stack
	pBM := Gdip_BitmapFromScreen(windowX + windowWidth * 3 // 4 "|" windowY + windowHeight // 2
		. "|" windowWidth - windowWidth * 3 // 4 "|" windowHeight - windowHeight // 2)
	kind := ext_planterNoticeIn(pBM)
	Gdip_DisposeImage(pBM)
	return kind
}
;The same, read from a bitmap with OCR: white on red, so read once as it is
;and, if nothing is found, once with the colours inverted.
ext_planterNoticeIn(pBM) {
	local invert, result, lines, line, word, text, kind

	for invert in [0, 1] {
		if !(result := nm_OCR_FromBitmap(pBM, 2, invert))
			return ""
		lines := []
		for line in result.Lines {
			text := ""
			for word in line.Words
				text .= word.Text
			lines.Push(nm_OCR_Norm(text))
		}
		if ((kind := ext_planterNoticeKind(lines)) != "")
			return kind
	}
	return ""
}
;Which notice a set of OCR lines holds, each line lower case letters only.
;
;"3 Planters" loses its digit to the normalising, so "planters" is asked for
;exactly: with a letter of slack, "planteris" in "Paper Planter is already in
;the ..." would pass for it, and a placed planter would be taken for a full
;set - the macro then lowers its planter count. Asked first, as the pictures
;were. "already in the" may be two letters off, "standing" one.
ext_planterNoticeKind(lines) {
	local n

	for n in lines
		if InStr(n, "planters")
			return "3planters"
	for n in lines
		if (nm_OCR_PhraseDistance("alreadyinthe", n) <= 2)
			return "already"
	for n in lines
		if (nm_OCR_PhraseDistance("standing", n) <= 1)
			return "standing"
	return ""
}

;The Blender's window, read the same way. Natro told its states apart by
;pictures of the word "End" on the green and on the red button and of
;"Cancel"; the new font broke all three. A batch that was done went unclaimed,
;the macro went on to look for the next item in a window still showing the
;old craft, and gave up with the window open, in front of everything the macro
;looked for afterwards.
;
;Returns {button, cancel, open}: button is "done" (the green End Crafting, a
;batch to claim), "busy" (the red one, still crafting) or ""; cancel, whether
;the amount picker's Cancel is up; open, whether the window is there at all.
ext_blenderRead(pBM) {
	local invert, result, lines, line, word, text, seen, r, argb

	for invert in [0, 1] {
		if !(result := nm_OCR_FromBitmap(pBM, 2, invert))
			return {button: "", cancel: 0, open: 0}
		lines := []
		for line in result.Lines {
			text := ""
			for word in line.Words
				text .= word.Text
			r := nm_OCR_WordsRect(line.Words)
			lines.Push({text: nm_OCR_Norm(text), x: r.x, y: r.y, w: r.w, h: r.h})
		}
		seen := ext_blenderReadLines(lines)
		if seen.open
			break
	}
	if IsObject(seen.endAt) {
		;the button is told by its colour, just left of its words: the bar above
		;it is the same green, so a fixed point could land on either
		r := seen.endAt
		argb := Gdip_GetPixel(pBM, Max(0, r.x - 6), r.y + r.h // 2)
		seen.button := ext_blenderButtonColour(argb)
	}
	return seen
}
;What a set of OCR lines says about the window, each {text, x, y, w, h} with
;the text lower case letters only. "endcrafting" may be two letters off,
;"cancel" one; "blender", in the title, says the window is up.
ext_blenderReadLines(lines) {
	local seen := {button: "", cancel: 0, open: 0, endAt: 0}, n

	for n in lines {
		if (!IsObject(seen.endAt) && (nm_OCR_PhraseDistance("endcrafting", n.text) <= 2))
			seen.endAt := n, seen.open := 1
		if (nm_OCR_PhraseDistance("cancel", n.text) <= 1)
			seen.cancel := 1, seen.open := 1
		if (nm_OCR_PhraseDistance("blender", n.text) <= 1)
			seen.open := 1
	}
	return seen
}
;Green (claim) or red (busy), from one ARGB pixel; "" for anything else.
ext_blenderButtonColour(argb) {
	local r := (argb >> 16) & 0xFF, g := (argb >> 8) & 0xFF, b := argb & 0xFF

	if ((g > r + 60) && (g > b + 60))
		return "done"
	if ((r > g + 60) && (r > b + 60))
		return "busy"
	return ""
}
