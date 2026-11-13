/***********************************************************
* Set_GUI_Offset.ahk - set the GUI offset by hand
* For PCs where the automatic detection keeps failing (e.g. no OCR language installed).
* Run it with Natro STOPPED: drag this file onto submacros\AutoHotkey64.exe.
* It saves the offset for your current Roblox window size; Natro uses it whenever detection fails.
* Run it again if you change the window size.
***********************************************************/
#Requires AutoHotkey v2.0
#SingleInstance Force
#Include "%A_ScriptDir%\..\lib"
#Include "Gdip_All.ahk"
#Include "Gdip_ImageSearch.ahk"
#Include "Roblox.ahk"

CoordMode "Mouse", "Screen"
pToken := Gdip_Startup()
title := "Set GUI Offset"

if !(hwnd := GetRobloxHWND())
{
	MsgBox "Roblox window not found. Open Bee Swarm Simulator and run this again.", title, 0x40010
	ExitApp
}
MsgBox "Open Bee Swarm Simulator so the Honey and Pollen bars are visible at the top.`n`nAfter clicking OK, move your mouse over the MIDDLE of the word `"Pollen`" in the top bar (not the number) and press F8.`n`nNothing will be clicked. Press Esc to cancel.", title, 0x40040
ActivateRoblox()
ToolTip "Hover over the middle of the word `"Pollen`" and press F8 (Esc to cancel)"
KeyWait "F8", "D"
ToolTip
MouseGetPos , &my
GetRobloxClientPos(hwnd)
offset := Round(my - windowY - 18.5)
if (offset < -20 || offset > 200)
{
	MsgBox "That position doesn't look like the top bar (offset " offset "). Run this again and hover over the word `"Pollen`".", title, 0x40030
	ExitApp
}
nm_OCR_SaveOffset(offset, windowWidth, windowHeight)
MsgBox "Saved GUI offset " offset " for a " windowWidth "x" windowHeight " Roblox window.`n`nNatro will use it whenever automatic detection fails at this window size.", title, 0x40040
ExitApp

Esc::ExitApp
