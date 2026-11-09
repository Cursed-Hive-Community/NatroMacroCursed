;Notices - the game's messages in the lower right, after Roblox's new font
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
