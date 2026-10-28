GS(1), align(), GS(,1), align(1)
GS(a:=0,b:=0) {
    l:=a=1?[RightKey, LeftKey]:[LeftKey, RightKey]
    w:=b=1?BackKey:FwdKey
    loop 2
        nm_Walk(5.5, l[1]), nm_Walk(1.5, w), nm_Walk(5.5, l[2]), nm_Walk(1.5, w)
    nm_Walk(6, l[1])
}
align(dir?) { ; yes = back, no = right
    m:=IsSet(dir)?[BackKey,FwdKey]:[RightKey, LeftKey]
    nm_Walk(IsSet(dir)?5:7,m[1])
    nm_Walk(IsSet(dir)?2:4,m[2])
}
; made by dully176 with care
