LinesReps:=4 ; default is 4
nm_Walk(17, LeftKey)
nm_Walk(11, BackKey)
nm_Walk(1, FwdKey)
nm_Walk(3.5, Rightkey)
nm_Walk(14, BackKey), Sleep(100)
loop LinesReps {
    nm_Walk(13-((A_Index=1)?1:0), Rightkey)
    nm_Walk(2.25, FwdKey)
    nm_Walk(13, LeftKey)
    if !(A_Index = LinesReps)
        nm_Walk(2.25, FwdKey)
}
