LinesReps:=3 ; default is 2
loop LinesReps {
    nm_Walk(1.5, FwdKey)
    nm_Walk(15, LeftKey)
    nm_Walk(1.5, FwdKey)
    nm_Walk(15, RightKey)
}
nm_Walk(7, RightKey)
nm_Walk(20, BackKey)