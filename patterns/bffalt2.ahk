LinesReps:=4 ; default is 4
nm_Walk(3.5, RightKey)
nm_Walk(11, FwdKey), Sleep(100)
loop LinesReps {
    nm_Walk(14, RightKey)
    nm_Walk(2.5, BackKey)
    nm_Walk(13, LeftKey)
    if !(A_Index = LinesReps)
        nm_Walk(2.5, BackKey)
}
nm_Walk(17, LeftKey)
nm_Walk(10, FwdKey)

/*
settings

{"Name":"Blue Flower","Pattern":"bffalt2","DriftCheck":0,"PatternInvertFB":0,"PatternInvertLR":0,"PatternReps":1,"PatternShift":0,"PatternSize":"M","ReturnType":"Reset","RotateDirection":"Right","RotateTimes":4,"SprinklerDist":1,"SprinklerLoc":"Center","UntilMins":9999,"UntilPack":100}

*/