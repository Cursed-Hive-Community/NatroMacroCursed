/**
 *  @Description Kettle - A simple pattern for Pine.
 *  @author Dully176
 *  @version 0.1.0
 *  @date 9/6/2025
 *  @Settings {"Name":"Pine Tree","Pattern":"Kettle","DriftCheck":0,"PatternInvertFB":0,"PatternInvertLR":0,"PatternReps":1,"PatternShift":1,"PatternSize":"M","ReturnType":"Walk","RotateDirection":"Right","RotateTimes":4,"SprinklerDist":7,"SprinklerLoc":"Upper Left","UntilMins":10,"UntilPack":95}
**/
#Warn All, Off
; ===== User Settings =====
cornerFDC := 0.3
diaMaskOffset := 1.5
diaMaskDriftComp := 2
honeyBeeOffset := 1.5
honeyBeeDriftComp := 2
digiStops := false
/*
cornerFDC - Correction for movement towards the corner.
DriftComp - Extra distance when walking towards the wall (diaMask/honeyBee).
Offset    - How far to walk away from the wall.
diaMask   - Wall where diamond mask is located.
honeyBee  - Wall where honey bee is located.
digiStops - (true/false) stops over digi tokens if true.
*/
; ===== ADVANCED, EDIT AT YOUR OWN RISK =====
loops := 2    ; Keep this two.
l := digiStops? 6 : 6.25    ; Long walk. (usually forward/backward)
s := l/4    ; Short walk. (usually left/right)
h := l/2    ; Half of long walk. (usually start/end)
; ANYTHING UNDER HERE, CHANGE AT YOUR OWN RISK.
try nm_CameraRotation("up",0)
catch
    toggle(true)
else
    toggle(false)
(digiStops?(cornerFDC:=0.3,diaMaskOffset:=1.5,honeyBeeOffset:=1,diaMaskDriftComp:=2,honeyBeeDriftComp:=4):0), cam("up",4,45)
loop loops
    walkSeq([[h,LeftKey],[s,FwdKey],[l,RightKey],[s,FwdKey],[l,LeftKey]]),cam("left",1),dy_Walk(l,BackKey,LeftKey),(diaMaskOffset>0)&&(dy_Walk(diaMaskOffset+diaMaskDriftComp,BackKey,LeftKey),dy_Walk(diaMaskOffset,FwdKey,RightKey),(A_Index!=loops?ds(700):0)),walkSeq([[s,BackKey,RightKey],[l,FwdKey,RightKey],[s,BackKey,RightKey],[h,BackKey,LeftKey]]),cam("right",1),walkSeq([[h,BackKey],[s,RightKey],[l,FwdKey],[s,RightKey]]),(honeyBeeOffset>0)&&(dy_Walk(honeyBeeOffset+honeyBeeDriftComp,RightKey),dy_Walk(honeyBeeOffset,LeftKey),(A_Index=loops?ds(600):0)),dy_Walk(l,BackKey),cam("left",2),walkSeq([[l,FwdKey],[s,RightKey],[l,BackKey],[s,RightKey],[h,FwdKey]]),cam("right",2),dy_Walk(h,FwdKey,LeftKey),(A_Index!=loops?ds(850):0),walkSeq([[s,FwdKey,RightKey],[l,BackKey,RightKey],[s,FwdKey,RightKey],[l,FwdKey,LeftKey]]),cam("left",1),walkSeq([[l,LeftKey],[s+cornerFDC,BackKey],[l,Rightkey],[s+cornerFDC,BackKey],[h,LeftKey]]),cam("right",1),walkSeq([[h,BackKey,LeftKey],[s,BackKey,RightKey],[l,FwdKey,RightKey],[s,BackKey,RightKey],[l,BackKey,LeftKey]]),cam("left",2),walkSeq([[l,FwdKey,RightKey],[s,BackKey,RightKey],[l,BackKey,LeftKey],[s,BackKey,RightKey]]),(A_Index=loops?ds(700):0),dy_Walk(h,FwdKey,RightKey),cam("right",2)
cam("down",4,45)
cam(dir,t:=1,ms:=35) {
    try
        nm_cameraRotation(dir,t),Sleep(ms)
    catch
        Send("{" Rot%dir% " " t "}"),Sleep(ms)
}
dy_Walk(t,d,s:=0)=>(s?nm_Walk(t,d,s):nm_Walk(t,d),Sleep(20))
ds(ms)=>(digiStops?(Send("{o 5}"),Sleep(ms)):0)
walkSeq(arr) {
    for , x in arr
        dy_Walk(x*)
}
toggle(state) {
legacy := false
    if (legacy = state) || !FileExist(filePath := A_WorkingDir "\patterns\Kettle.ahk")
        return
    f := FileOpen(filePath, "r"), contents := f.Read(), f.Close(), new := RegExReplace(contents, "(?m)^\s*legacy\s*:=\s*" (state? "false":"true") "\b.*$", "legacy := " (state? "true":"false"), , 1), (new = contents && !RegExMatch(contents, "(?m)^\s*legacy\s*:=")) ? (new := "legacy := " (state? "true":"false") "`r`n" new) : "", new := RegExReplace(new, "(?m)^\s*;@No" "Interrupt\s*\r?\n?", ""), (state) ? new := ";@No" "Interrupt`r`n" new : "", new := RegExReplace(new, "`r?`n{3,}", "`r`n`r`n"), ((new != contents) ? (f := FileOpen(filePath, "w"), f.Write(new), f.Close()) : ""), legacy := state
}
/*
If you're interested in seeing the actual pattern itself (without the weird format)
send me a DM and I'll send you the file. I made it like this as a challenge for myself.
And also, enjoy the pattern - Dully176
*/
