LoopReps:=2 ; default is 2
loop LoopReps {
    nm_Walk(15, RightKey)
    nm_Walk(2, FwdKey)
    nm_Walk(16, LeftKey)
    if !(A_Index=LoopReps)
        nm_Walk(2, FwdKey)
}
nm_Walk(4, LeftKey)
nm_Walk((LoopReps*2)+6, BackKey)

/*
settings

{"Name":"Bamboo","Pattern":"bambalt2","DriftCheck":0,"PatternInvertFB":0,"PatternInvertLR":0,"PatternReps":1,"PatternShift":0,"PatternSize":"M","ReturnType":"Reset","RotateDirection":"None","RotateTimes":1,"SprinklerDist":1,"SprinklerLoc":"Center","UntilMins":9999,"UntilPack":100}

*/