;@NoInterrupt
dwFDC := 0.2    ; diamond wall FDC
hwFDC := 0.3    ; honey wall FDC
crFDC := 0.3    ; corner FDC
dwAlign := 1.5  ; diamond wall align (because it has the gap)
hwAlign := 1.5    ; honey wall align (lot of drift)

Send("{" RotUp " 4}"), Sleep(50)

dy_Walk(3+hwFDC, RightKey)
dy_Walk(1.5, FwdKey)
dy_Walk(6, LeftKey)
dy_Walk(1.5, FwdKey)
dy_Walk(6+hwFDC+hwAlign, RightKey)

nm_cameraRotation("left", 1), Sleep(50)

dy_Walk(6+dwFDC, BackKey, LeftKey)
dy_Walk(1.5, FwdKey, LeftKey)
dy_Walk(6, FwdKey, RightKey)
dy_Walk(1.5, FwdKey, LeftKey)
dy_Walk(3+dwFDC, BackKey, LeftKey)

nm_cameraRotation("right", 1), Sleep(50)

dy_Walk(3+dwFDC, BackKey)
dy_Walk(1.5, LeftKey)
dy_Walk(6, FwdKey)
dy_Walk(1.5, LeftKey)
dy_Walk(6+dwFDC, BackKey)
if dwAlign > 0
    dy_Walk(dwAlign + 2, BackKey),dy_Walk(dwAlign, FwdKey)

nm_cameraRotation("left", 2), Sleep(50)

dy_Walk(6+hwFDC, BackKey)
dy_Walk(1.5, RightKey)
dy_Walk(6, FwdKey)
dy_Walk(1.5, RightKey)
dy_Walk(3+hwFDC, BackKey)

nm_cameraRotation("right", 2), Sleep(100)

dy_Walk(3, FwdKey, RightKey)
dy_Walk(1.5, FwdKey, LeftKey)
dy_Walk(6, BackKey, LeftKey)
dy_Walk(1.5, FwdKey, LeftKey)
dy_Walk(6, FwdKey, RightKey)

nm_cameraRotation("left", 1), Sleep(50)

dy_Walk(6+crFDC, BackKey)
dy_Walk(1.5, LeftKey)
dy_Walk(6, FwdKey)
dy_Walk(1.5, LeftKey)
dy_Walk(3+crFDC, BackKey)

nm_cameraRotation("right", 1), Sleep(50)

dy_Walk(3+crFDC, BackKey, RightKey)
dy_Walk(1.5, BackKey, LeftKey)
dy_Walk(6, FwdKey, LeftKey)
dy_Walk(1.5, BackKey, LeftKey)
dy_Walk(6+crFDC, BackKey, RightKey)


nm_cameraRotation("left", 2), Sleep(50)

dy_Walk(6, BackKey, RightKey)
dy_Walk(1.5, FwdKey, RightKey)
dy_Walk(6, FwdKey, LeftKey)
dy_Walk(1.5, FwdKey, RightKey)
dy_Walk(3, BackKey, RightKey)

nm_cameraRotation("right", 2), Sleep(50)
Send("{" RotDown " 4}"), Sleep(50)

; dir1 - the small side, dir2 - the big side, dir3 - third direction (angled), mirror - 6 becomes 3 at the start
basicShape(dir1, dir2, dir3, mirror) { 
    return 0
}

dy_Walk(t,d,s:=0) => ((s!=0) ? (nm_Walk(t,d,s),Sleep(30),0):(nm_Walk(t,d),Sleep(30),0))
; Made by Dully176
