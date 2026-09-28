#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon

;A loopback check for lib\Socket.ahk. Double-click it: it starts a listener,
;connects to itself, pushes three frames through and reports what came back.
;
;Nothing else in the fleet works if this does not, so it is worth having on its
;own. The three frames are chosen to break the three things that are easy to get
;wrong, rather than to look thorough:
;
;	1. a plain line          does a frame survive at all
;	2. an accented line      UTF-8 across a chunk boundary, the classic corruption
;	3. a very long line      one frame spread over several reads, reassembled
;
;The third is the one that matters. A single small frame would pass even with
;the framing badly broken.

#Include "%A_ScriptDir%\..\lib"
#Include "Socket.ahk"

PORT := 47654
sent := [], echoed := [], finished := 0

;the long frame is deliberately larger than the 4096 byte read buffer, so it
;cannot arrive in one piece
long := ""
Loop 400
	long .= "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

probes := ["HELLO fleet"
	, "ACCENTS " Chr(0xE9) Chr(0xE0) Chr(0xFC) Chr(0xEE) Chr(0xE7) " et un tiret " Chr(0x2014)
	, long]

if !(listener := sock_Listen(PORT, OnServer)) {
	MsgBox "Could not listen on port " PORT ".`n`nEither something else holds it, or Winsock refused - which is the thing this test exists to find out.", "Socket self-test", 0x40010
	ExitApp
}

if !(client := sock_Connect("127.0.0.1", PORT, OnClient)) {
	MsgBox "Could not open a client socket.", "Socket self-test", 0x40010
	ExitApp
}

;a test that hangs is a failed test, so give it a deadline of its own
SetTimer Report, -4000
return

;The listening side. Every frame is echoed back untouched; if the library is
;sound, what returns is exactly what left.
OnServer(s, event, data) {
	if (event = "line")
		sock_SendLine(s, data)
}

;The connecting side.
OnClient(s, event, data) {
	global probes, sent, echoed

	if (event = "connect") {
		;sending before the connection is up would fail with WSAENOTCONN, so the
		;frames go out from here rather than straight after sock_Connect
		if (data != "") {
			echoed.Push("connect failed, Winsock error " data)
			Report()
			return
		}
		for _, probe in probes
			sent.Push(probe), sock_SendLine(s, probe)
	}
	else if (event = "line") {
		echoed.Push(data)
		if (echoed.Length = probes.Length)
			Report()
	}
}

Report(*) {
	global sent, echoed, probes, finished, listener, client
	local lines, i, ok, allOk

	if finished
		return
	finished := 1
	SetTimer Report, 0

	allOk := (echoed.Length = probes.Length)
	lines := []
	Loop probes.Length {
		i := A_Index
		ok := (i <= echoed.Length) && (echoed[i] == probes[i])
		allOk := allOk && ok
		lines.Push((ok ? "PASS  " : "FAIL  ")
			. ["plain line", "accented line", "long line (" StrLen(probes[3]) " chars)"][i])
	}
	if (echoed.Length < probes.Length)
		lines.Push("", "Only " echoed.Length " of " probes.Length " frames came back.")

	sock_Close(client), sock_Close(listener)
	MsgBox (allOk ? "Socket.ahk works.`n`n" : "Socket.ahk is broken.`n`n") . Join(lines)
		, "Socket self-test", allOk ? 0x40040 : 0x40010
	ExitApp
}

Join(arr) {
	local out := ""
	for _, v in arr
		out .= v "`n"
	return out
}
