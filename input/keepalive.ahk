#Requires AutoHotkey v2.0
#SingleInstance Ignore

; Starts the Claude RTL input helper (claude-rtl.ahk, next to this file) when it is not running, then exits.
; A scheduled task runs this at sign-in and every minute, so the helper comes back after a Claude update,
; a sign-out or any other stop. If claude-rtl.ahk is missing it does nothing and says nothing.
helper := A_ScriptDir "\claude-rtl.ahk"
if !FileExist(helper)
    ExitApp
for p in ComObjGet("winmgmts:").ExecQuery("SELECT CommandLine FROM Win32_Process WHERE Name LIKE 'AutoHotkey%'")
    if InStr(p.CommandLine, helper)
        ExitApp
Run('"' A_AhkPath '" "' helper '"')
