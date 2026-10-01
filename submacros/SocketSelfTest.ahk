#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon

;A loopback check for lib\Socket.ahk, and a diagnosis when it fails.
;
;	.\submacros\AutoHotkey64.exe /script .\submacros\SocketSelfTest.ahk
;
;Three frames are pushed through, each chosen because it breaks something
;different rather than to look thorough:
;
;	1. a plain line          does a frame survive at all
;	2. an accented line      UTF-8 across a chunk boundary, the classic corruption
;	3. a very long line      one frame spread over several reads, reassembled
;	4. a datagram            the UDP path the coordinator's beacon rides on
;
;It also keeps a running account of what actually happened - every socket
;created, every event delivered, every Winsock error - and prints it when
;something goes wrong. "FAIL" on its own says only that the answer was wrong;
;this says which step never happened, which is the part worth knowing.

#Include "%A_ScriptDir%\..\lib"
#Include "Socket.ahk"

PORT := 47654
sent := [], echoed := [], finished := 0, trace := [], udpSeen := ""

long := ""
Loop 400
	long .= "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

probes := ["HELLO fleet"
	, "ACCENTS " Chr(0xE9) Chr(0xE0) Chr(0xFC) Chr(0xEE) Chr(0xE7) " et un tiret " Chr(0x2014)
	, long]

Note("script hwnd " Format("0x{:X}", A_ScriptHwnd) ", message " Format("0x{:X}", SOCK_MSG))

listener := sock_Listen(PORT, OnServer)
Note("sock_Listen(" PORT ") -> " (listener ? listener : "0") LastError(listener))
if !listener {
	Finish("The listener could not be opened.")
	return
}

client := sock_Connect("127.0.0.1", PORT, OnClient)
Note("sock_Connect(127.0.0.1:" PORT ") -> " (client ? client : "0") LastError(client))
if !client {
	Finish("The client socket could not be opened.")
	return
}

;The UDP half, checked on its own: the coordinator cannot be found without
;it, and it shares nothing with the stream path above.
udpSock := sock_UdpListen(PORT + 1, OnDatagram)
Note("sock_UdpListen(" (PORT + 1) ") -> " (udpSock ? udpSock : "0") LastError(udpSock))
if udpSock
	Note("sock_UdpSend -> " (sock_UdpSend(udpSock, "127.0.0.1", PORT + 1, "BEACON test=1")
		? "accepted" : "refused" LastError(0)))

;a test that hangs is a failed test, so give it a deadline of its own
SetTimer Report, -4000
return

;A datagram carries a fourth argument the stream events do not: where it came
;from. That is the whole reason a beacon works without anyone typing an address.
OnDatagram(s, event, data, from) {
	global udpSeen

	Note("udp: " event " from " from " [" data "]")
	if (event = "datagram")
		udpSeen := data
}

;The listening side. Every frame is echoed back untouched; if the library is
;sound, what returns is exactly what left.
OnServer(s, event, data) {
	Note("server: " event (StrLen(data) ? " (" StrLen(data) " chars)" : ""))
	if (event = "line")
		sock_SendLine(s, data)
}

;The connecting side.
OnClient(s, event, data) {
	global probes, sent, echoed

	Note("client: " event (((event = "connect") && (data != "")) ? " error " data
		: (StrLen(data) ? " (" StrLen(data) " chars)" : "")))
	if (event = "connect") {
		if (data != "") {
			Report()
			return
		}
		;sending before the connection is up would fail with WSAENOTCONN, so the
		;frames go out from here rather than straight after sock_Connect
		for _, probe in probes
			sent.Push(probe), sock_SendLine(s, probe)
		Note("client: sent " probes.Length " frames")
		return
	}
	if (event != "line")
		return
	echoed.Push(data)
	if (echoed.Length = probes.Length)
		Report()
}

Report(*) {
	global sent, echoed, probes, finished, trace, udpSeen
	local lines := [], i, ok, allOk

	if finished
		return
	allOk := (echoed.Length = probes.Length)
	Loop probes.Length {
		i := A_Index
		ok := (i <= echoed.Length) && (echoed[i] == probes[i])
		allOk := allOk && ok
		lines.Push((ok ? "PASS  " : "FAIL  ")
			. ["plain line", "accented line", "long line (" StrLen(probes[3]) " chars)"][i])
	}
	ok := (udpSeen = "BEACON test=1")
	allOk := allOk && ok
	lines.Push((ok ? "PASS  " : "FAIL  ") "datagram, with the sender's address")
	Finish(allOk ? "" : Join(lines))
}

;Print the verdict. On failure the trace goes to a file and to the clipboard
;as well as on screen - a message box cannot be copied out of, and a trace
;nobody can send on is a trace nobody can act on.
Finish(problem) {
	global finished, trace, listener, client, udpSock
	local summary, path

	if finished
		return
	finished := 1
	SetTimer Report, 0
	try sock_Close(client)
	try sock_Close(listener)
	try sock_Close(udpSock)
	if (problem = "") {
		MsgBox "Socket.ahk works.`n`nPASS  plain line`nPASS  accented line`nPASS  long line`nPASS  datagram"
			, "Socket self-test", 0x40040
		ExitApp
	}
	summary := "Socket self-test on " A_ComputerName ", AutoHotkey " A_AhkVersion "`r`n`r`n"
		. StrReplace(problem, "`n", "`r`n") "`r`nWhat actually happened:`r`n"
		. StrReplace(Join(trace), "`n", "`r`n")
	path := A_ScriptDir "\..\settings\socket_diag.txt"
	try FileDelete path
	try FileAppend summary, path, "UTF-8"
	try A_Clipboard := summary
	MsgBox "Socket.ahk is broken.`n`n" problem
		. "`nThe full trace is on the clipboard - paste it straight into chat."
		. "`nIt is also in settings\socket_diag.txt, which will open now."
		, "Socket self-test", 0x40010
	try Run 'notepad.exe "' path '"'
	ExitApp
}

;Winsock keeps its reason in a separate call, and it is the difference between
;"it did not work" and knowing why.
LastError(result) {
	local e

	if result
		return ""
	return (e := DllCall("ws2_32\WSAGetLastError", "Int")) ? "  (Winsock error " e ")" : ""
}

Note(text) {
	global trace
	trace.Push(A_TickCount " ms  " text)
}

Join(arr) {
	local out := ""
	for _, v in arr
		out .= v "`n"
	return out
}
