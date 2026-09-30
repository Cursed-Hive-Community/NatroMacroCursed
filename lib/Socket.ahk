;Winsock for AutoHotkey v2 - the little that a line protocol needs
;
;AutoHotkey has no sockets, so this wraps ws2_32 through DllCall. It stays
;deliberately small: one listener, any number of connections, and text frames
;ended by a newline. Anything richer belongs to whoever is using it.
;
;Nothing here blocks, and that single decision shapes the whole file. A blocking
;recv would freeze a script that is also busy playing a game, so instead
;WSAAsyncSelect asks Windows to post a window message whenever a socket becomes
;readable, accepts a caller, finishes connecting or closes. There is no read
;loop anywhere - only handlers reacting to those messages.
;
;The caller supplies one callback per socket and is told about four things:
;
;	"accept"   a caller connected; the second argument is the new socket
;	"datagram" a UDP message arrived; this one alone carries a fourth
;	           argument, the address it came from
;	"connect"  an outgoing connection succeeded, or failed if it carries an error
;	"line"     a complete frame arrived, newline already stripped
;	"close"    the other end went away
;
;Usage:
;	sock_Listen(7777, handler)          ;handler(sock, event, data)
;	sock_Connect("192.168.1.9", 7777, handler)
;	sock_SendLine(sock, "HELLO main")
;	sock_Close(sock)

;The window message sockets report on. 0x8001 sits in the WM_APP range, clear of
;the 0x555x messages Natro already passes between its own processes.
SOCK_MSG := 0x8001

;WSAAsyncSelect event bits, under the names Winsock gives them
SOCK_FD_READ := 1, SOCK_FD_WRITE := 2, SOCK_FD_ACCEPT := 8
	, SOCK_FD_CONNECT := 16, SOCK_FD_CLOSE := 32

;the two Winsock errors worth telling apart from a real failure
SOCK_EWOULDBLOCK := 10035

;Per socket state, keyed by handle. Each entry holds the caller's callback, the
;bytes received that do not yet make up a whole line, and the bytes queued for
;sending that the socket would not take.
sock_state := Map()

;Winsock has to be started once per process, and the dispatcher hooked up with
;it. Repeat calls are free.
sock_Startup() {
	static done := 0
	local data

	if done
		return 1
	data := Buffer(408, 0)
	if (DllCall("ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", data, "Int") != 0)
		return 0
	OnMessage(SOCK_MSG, sock_Dispatch)
	done := 1
	return 1
}

;Fill a sockaddr_in: sixteen bytes of family, port in network order, address,
;and padding. An empty host means "listen on every interface".
sock_Address(host, port) {
	local addr := Buffer(16, 0)

	NumPut("UShort", 2, addr, 0)                                   ;AF_INET
	NumPut("UShort", ((port & 0xFF) << 8) | ((port >> 8) & 0xFF), addr, 2)
	if (host = "")
		NumPut("UInt", 0, addr, 4)                                 ;INADDR_ANY
	else if (DllCall("ws2_32\InetPtonW", "Int", 2, "WStr", host, "Ptr", addr.Ptr + 4, "Int") != 1)
		return 0
	return addr
}

;A fresh entry in the table. The receive buffer grows on demand; the send buffer
;only ever holds what one socket refused to take in one go, which is little.
sock_Track(s, callback, udp := 0) {
	global sock_state

	sock_state[s] := { callback: callback, udp: udp
		, inBuf: Buffer(4096, 0), inLen: 0
		, outBuf: Buffer(4096, 0), outLen: 0, outPos: 0 }
	return sock_state[s]
}

;Open a listening socket. Returns its handle, or 0.
sock_Listen(port, callback) {
	global sock_state
	local s, addr, opt

	if !sock_Startup()
		return 0
	if ((s := DllCall("ws2_32\socket", "Int", 2, "Int", 1, "Int", 6, "Ptr")) = -1)
		return 0
	;without SO_REUSEADDR, restarting inside the TIME_WAIT window cannot rebind -
	;which is exactly what a coordinator handing over and coming back does
	opt := Buffer(4, 0), NumPut("Int", 1, opt)
	DllCall("ws2_32\setsockopt", "Ptr", s, "Int", 0xFFFF, "Int", 4, "Ptr", opt, "Int", 4)
	if (!(addr := sock_Address("", port))
		|| (DllCall("ws2_32\bind", "Ptr", s, "Ptr", addr, "Int", 16, "Int") != 0)
		|| (DllCall("ws2_32\listen", "Ptr", s, "Int", 16, "Int") != 0)) {
		DllCall("ws2_32\closesocket", "Ptr", s)
		return 0
	}
	sock_Track(s, callback)
	DllCall("ws2_32\WSAAsyncSelect", "Ptr", s, "Ptr", A_ScriptHwnd, "UInt", SOCK_MSG
		, "Int", SOCK_FD_ACCEPT | SOCK_FD_CLOSE, "Int")
	return s
}

;Start an outgoing connection. It returns immediately: WSAAsyncSelect has
;already put the socket in non-blocking mode, so connect reports WSAEWOULDBLOCK
;and the real outcome arrives later as a "connect" event.
sock_Connect(host, port, callback) {
	local s, addr

	if !sock_Startup()
		return 0
	if !(addr := sock_Address(host, port))
		return 0
	if ((s := DllCall("ws2_32\socket", "Int", 2, "Int", 1, "Int", 6, "Ptr")) = -1)
		return 0
	sock_Track(s, callback)
	DllCall("ws2_32\WSAAsyncSelect", "Ptr", s, "Ptr", A_ScriptHwnd, "UInt", SOCK_MSG
		, "Int", SOCK_FD_CONNECT | SOCK_FD_READ | SOCK_FD_WRITE | SOCK_FD_CLOSE, "Int")
	DllCall("ws2_32\connect", "Ptr", s, "Ptr", addr, "Int", 16, "Int")
	return s
}

;Queue one frame and push what the socket will take.
sock_SendLine(s, text) {
	global sock_state
	local st, line, need, grown

	if !sock_state.Has(s)
		return 0
	st := sock_state[s]
	line := text "`n"
	;StrPut counts the null terminator in both the size it reports and the length
	;it accepts, so the buffer has to hold it - but it is not part of the frame,
	;and the next line written will simply overwrite it.
	need := StrPut(line, "UTF-8")
	;the queue is kept as bytes rather than as a string, because a partial send
	;can stop in the middle of a UTF-8 character, and half a character is not
	;something a string can hold
	if (st.outLen + need > st.outBuf.Size) {
		grown := Buffer(Max(st.outBuf.Size * 2, st.outLen + need), 0)
		DllCall("RtlMoveMemory", "Ptr", grown, "Ptr", st.outBuf, "Ptr", st.outLen)
		st.outBuf := grown
	}
	StrPut(line, st.outBuf.Ptr + st.outLen, need, "UTF-8")
	st.outLen += need - 1
	return sock_Flush(s)
}

;Push the queue. A socket that cannot take it all says WSAEWOULDBLOCK; the rest
;waits for the FD_WRITE that follows rather than being dropped.
sock_Flush(s) {
	global sock_state
	local st, sent

	if !sock_state.Has(s)
		return 0
	st := sock_state[s]
	while (st.outPos < st.outLen) {
		sent := DllCall("ws2_32\send", "Ptr", s, "Ptr", st.outBuf.Ptr + st.outPos
			, "Int", st.outLen - st.outPos, "Int", 0, "Int")
		if (sent <= 0)
			return (DllCall("ws2_32\WSAGetLastError", "Int") = SOCK_EWOULDBLOCK) ? 1 : 0
		st.outPos += sent
	}
	st.outLen := 0, st.outPos := 0
	return 1
}

;Close a socket and forget it. Safe to call twice.
sock_Close(s) {
	global sock_state

	if !sock_state.Has(s)
		return 0
	DllCall("ws2_32\WSAAsyncSelect", "Ptr", s, "Ptr", A_ScriptHwnd, "UInt", SOCK_MSG, "Int", 0, "Int")
	DllCall("ws2_32\closesocket", "Ptr", s)
	sock_state.Delete(s)
	return 1
}

;Everything Windows has to say about every socket arrives here. wParam is the
;socket; lParam packs the event in its low word and any error in its high.
sock_Dispatch(wParam, lParam, *) {
	global sock_state
	local s := wParam, event := lParam & 0xFFFF, err := (lParam >> 16) & 0xFFFF
	local st, peer

	if !sock_state.Has(s)
		return 0
	st := sock_state[s]

	if (event = SOCK_FD_ACCEPT) {
		if ((peer := DllCall("ws2_32\accept", "Ptr", s, "Ptr", 0, "Ptr", 0, "Ptr")) = -1)
			return 0
		;a new connection inherits the listener's callback: one handler for the
		;whole service is what a caller actually wants
		sock_Track(peer, st.callback)
		DllCall("ws2_32\WSAAsyncSelect", "Ptr", peer, "Ptr", A_ScriptHwnd, "UInt", SOCK_MSG
			, "Int", SOCK_FD_READ | SOCK_FD_WRITE | SOCK_FD_CLOSE, "Int")
		st.callback.Call(peer, "accept", "")
	}
	else if (event = SOCK_FD_CONNECT)
		st.callback.Call(s, "connect", err ? err : "")
	else if (event = SOCK_FD_READ) {
		;a datagram is whole or nothing, so it skips the line reassembly a
		;stream needs. Written as an if rather than a ternary: a statement
		;that opens with an expression and a question mark is read by
		;AutoHotkey as a function call, not as a choice between two.
		if st.udp
			sock_UdpReceive(s)
		else
			sock_Receive(s)
	}
	else if (event = SOCK_FD_WRITE)
		sock_Flush(s)
	else if (event = SOCK_FD_CLOSE) {
		;drain first: bytes sent just before the close are still worth having
		sock_Receive(s)
		st.callback.Call(s, "close", "")
		sock_Close(s)
	}
	return 0
}

;Read whatever is waiting, then hand over every complete line.
;
;Bytes arrive in whatever chunks the network feels like, and a UTF-8 character
;can straddle two of them. So the raw bytes are accumulated and only whole lines
;are decoded - decoding each read as it landed would mangle any accented
;character unlucky enough to fall on a boundary.
sock_Receive(s) {
	global sock_state
	local st, chunk, n, grown, at, line

	if !sock_state.Has(s)
		return 0
	st := sock_state[s]
	chunk := Buffer(4096, 0)
	Loop {
		n := DllCall("ws2_32\recv", "Ptr", s, "Ptr", chunk, "Int", chunk.Size, "Int", 0, "Int")
		if (n <= 0)
			break
		if (st.inLen + n > st.inBuf.Size) {
			grown := Buffer(Max(st.inBuf.Size * 2, st.inLen + n), 0)
			DllCall("RtlMoveMemory", "Ptr", grown, "Ptr", st.inBuf, "Ptr", st.inLen)
			st.inBuf := grown
		}
		DllCall("RtlMoveMemory", "Ptr", st.inBuf.Ptr + st.inLen, "Ptr", chunk, "Ptr", n)
		st.inLen += n
		if (n < chunk.Size)
			break
	}
	while ((at := sock_FindNewline(st.inBuf, st.inLen)) >= 0) {
		line := sock_Decode(st.inBuf, at)
		sock_Consume(st, at + 1)
		line := Trim(line, "`r")
		if (line != "")
			st.callback.Call(s, "line", line)
	}
	return 1
}

;Offset of the first newline in the first len bytes, or -1.
sock_FindNewline(buf, len) {
	local i := 0

	while (i < len) {
		if (NumGet(buf, i, "UChar") = 10)
			return i
		i++
	}
	return -1
}

;Decode the first len bytes as UTF-8. The copy exists only to hold the null
;terminator StrGet wants, without disturbing the buffer still being filled.
sock_Decode(buf, len) {
	local tmp

	if (len <= 0)
		return ""
	tmp := Buffer(len + 1, 0)
	DllCall("RtlMoveMemory", "Ptr", tmp, "Ptr", buf, "Ptr", len)
	return StrGet(tmp, "UTF-8")
}

;Drop the first n bytes, sliding whatever follows to the front.
sock_Consume(st, n) {
	if (n >= st.inLen) {
		st.inLen := 0
		return
	}
	DllCall("RtlMoveMemory", "Ptr", st.inBuf, "Ptr", st.inBuf.Ptr + n, "Ptr", st.inLen - n)
	st.inLen -= n
}
;UDP, so a macro can find the coordinator without being told where it is.
;
;An address typed into a panel is wrong the moment the router hands out a new
;lease - which is exactly what happens after a machine crashes and comes back.
;So the coordinator shouts its whereabouts onto the local network every couple
;of seconds, and the macros listen. Nothing needs configuring, and a coordinator
;that has moved is found again within one beacon.
;
;Datagrams are not a stream: one send is one receive, whole or not at all. That
;is why none of the line reassembly above applies here, and why the callback is
;handed the message complete along with the address it came from.

;Listen for beacons on a port. Several macros on one machine all want the same
;port, which is what SO_REUSEADDR is for; SO_BROADCAST is what lets the same
;socket send one.
sock_UdpListen(port, callback) {
	local s, addr, opt

	if !sock_Startup()
		return 0
	if ((s := DllCall("ws2_32\socket", "Int", 2, "Int", 2, "Int", 17, "Ptr")) = -1)
		return 0
	opt := Buffer(4, 0), NumPut("Int", 1, opt)
	DllCall("ws2_32\setsockopt", "Ptr", s, "Int", 0xFFFF, "Int", 4, "Ptr", opt, "Int", 4)
	DllCall("ws2_32\setsockopt", "Ptr", s, "Int", 0xFFFF, "Int", 0x20, "Ptr", opt, "Int", 4)
	if (!(addr := sock_Address("", port))
		|| (DllCall("ws2_32\bind", "Ptr", s, "Ptr", addr, "Int", 16, "Int") != 0)) {
		DllCall("ws2_32\closesocket", "Ptr", s)
		return 0
	}
	sock_Track(s, callback, 1)
	DllCall("ws2_32\WSAAsyncSelect", "Ptr", s, "Ptr", A_ScriptHwnd, "UInt", SOCK_MSG
		, "Int", SOCK_FD_READ, "Int")
	return s
}

;Send one datagram. Host 255.255.255.255 reaches every machine on this subnet,
;which is the whole point of the beacon.
sock_UdpSend(s, host, port, text) {
	local addr, buf, need

	if !(addr := sock_Address(host, port))
		return 0
	need := StrPut(text, "UTF-8")
	buf := Buffer(need, 0)
	StrPut(text, buf, need, "UTF-8")
	return (DllCall("ws2_32\sendto", "Ptr", s, "Ptr", buf, "Int", need - 1, "Int", 0
		, "Ptr", addr, "Int", 16, "Int") > 0)
}

;Take in whatever has arrived. recvfrom fills a sockaddr_in with the sender, and
;bytes 4 to 7 of it are the address - which is the only reason any of this
;exists, since the message itself never says where it came from.
sock_UdpReceive(s) {
	global sock_state
	local st, chunk, from, fromLen, n, ip

	if !sock_state.Has(s)
		return 0
	st := sock_state[s]
	chunk := Buffer(2048, 0), from := Buffer(16, 0), fromLen := Buffer(4, 0)
	Loop {
		NumPut("Int", 16, fromLen)
		n := DllCall("ws2_32\recvfrom", "Ptr", s, "Ptr", chunk, "Int", chunk.Size - 1
			, "Int", 0, "Ptr", from, "Ptr", fromLen, "Int")
		if (n <= 0)
			break
		NumPut("UChar", 0, chunk, n)
		ip := NumGet(from, 4, "UChar") "." NumGet(from, 5, "UChar")
			. "." NumGet(from, 6, "UChar") "." NumGet(from, 7, "UChar")
		st.callback.Call(s, "datagram", Trim(StrGet(chunk, "UTF-8"), " `t`r`n"), ip)
	}
	return 1
}
