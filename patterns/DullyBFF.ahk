; config
patternWidth:=2
patternHeight:=6
patternReps:=5
; towards corner
nm_Walk(5, RightKey),nm_Walk(12, BackKey)
; away from corner
nm_Walk(1.5*Sqrt(2), FwdKey, LeftKey),nm_Walk(5.5, FwdKey),Sleep(100)
; pattern
loop patternReps {
    loop patternWidth {
        nm_Walk(1.5, LeftKey)
        nm_Walk(patternHeight, FwdKey)
        nm_Walk(1, LeftKey)
        nm_Walk(patternHeight, BackKey)
    }
    nm_Walk(1.5, LeftKey),nm_Walk(patternHeight, FwdKey)
    loop patternWidth {
        nm_Walk(1.5, RightKey)
        nm_Walk(patternHeight, BackKey)
        nm_Walk(1, RightKey)
        nm_Walk(patternHeight, FwdKey)
    }
    nm_Walk(1.5, RightKey),nm_Walk(patternHeight, BackKey)
}
; made by dully176 with care
