;CocoPlanterPathV1 - paper planter spot in the coconut field

if (MoveMethod = "walk")
{
	nm_Walk(3, FwdKey)
	nm_Walk(52, LeftKey)
	nm_Walk(3, FwdKey)
	send "{" FwdKey " down}{space down}"
	HyperSleep(300)
	send "{space up}"
	nm_Walk(5, RightKey)
	send "{space down}"
	HyperSleep(300)
	send "{space up}{" FwdKey " up}"
	HyperSleep(500)
	nm_Walk(2, FwdKey)
	nm_Walk(15, RightKey)
	nm_Walk(6, FwdKey, RightKey)
	nm_Walk(7, FwdKey)
	nm_Walk(5, BackKey, LeftKey)
	nm_Walk(23, FwdKey)
	nm_Walk(12, LeftKey)
	nm_Walk(8, LeftKey, FwdKey) ; 1.3
	nm_Walk(10, FwdKey) ; 1.3
	nm_Walk(5, RightKey) ; 1.3
	nm_Walk(25, FwdKey, RightKey) ; 31
	nm_Walk(50, LeftKey)
	nm_Walk(2, RightKey)
	nm_Walk(40, FwdKey)
	send "{" RotRight " 2}"
	nm_Walk(55, FwdKey)
	nm_Walk(10, LeftKey)
	send "{" RotRight " 2}"
	nm_Walk(5.79, FwdKey, RightKey)
	nm_Walk(50, FwdKey)
	send "{space down}"
	Hypersleep(300)
	send "{space up}"
	nm_Walk(6, FwdKey)
	send "{space down}"
	HyperSleep(100)
	send "{space up}"
	nm_Walk(4, FwdKey, RightKey)
	send "{" RotLeft " 4}"
	Sleep 1500
}
else
{
	nm_gotoramp()
	nm_gotocannon()
	send "{e down}"
	HyperSleep(100)
	send "{e up}{" FwdKey " down}"
	HyperSleep(1170)
	send "{space 2}{" FwdKey " up}"
	HyperSleep(6750)
	nm_Walk(70, FwdKey)
	send "{" RotRight " 2}"
	nm_Walk(55, FwdKey)
	nm_Walk(45, BackKey, RightKey)
	nm_Walk(22, FwdKey, RightKey)
	nm_Walk(15, FwdKey)
	nm_Walk(5.5, LeftKey)
	nm_Walk(9, LeftKey, FwdKey)
	nm_Walk(3, FwdKey, RightKey)
	send "{space down}"
	nm_Walk(0.8, FwdKey, RightKey)
	send "{space up}"
	nm_Walk(22.97, FwdKey, RightKey)
	nm_Walk(23.76, RightKey)
	send "{" RotRight " 2}"
	nm_Walk(7.92, RightKey)
	send "{" RotDown " 2}"
	nm_Walk(31.68, RightKey, FwdKey)
	nm_Walk(7.5, LeftKey)
}
;path by jln7_ for CHC
