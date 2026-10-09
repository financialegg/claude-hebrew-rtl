#Requires AutoHotkey v2.0
#SingleInstance Force

; =============================================================================
;  RTL Helper for Claude Desktop - unofficial community tool, not Anthropic
;
;  Makes Hebrew render right-to-left in the Claude Desktop message box by
;  seeding one invisible RIGHT-TO-LEFT EMBEDDING character (U+202B) at the
;  start of the message. The character is built with Chr(0x202B), so this
;  source file intentionally contains no invisible characters - every byte
;  is visible on screen.
;
;  Scope and privacy:
;    - Aims all typing exclusively at Claude's main window (process
;      Claude.exe, top-level Chromium window class), never at its native
;      dialogs, and the automatic paths act only when the active keyboard
;      layout is Hebrew. Every seed re-checks its conditions at the moment
;      it fires.
;    - No network, no file I/O, no logging, no clipboard access. Exactly
;      two Windows API calls exist in this script (GetWindowThreadProcessId
;      and GetKeyboardLayout), both for keyboard-layout detection.
;    - "KeyHistory 0" and "ListLines 0" below disable AutoHotkey's built-in
;      key-event history and line history, so neither keystrokes nor
;      execution traces are retained, even in memory.
;    - Start it as a normal user. Never elevated.
;
;  Hotkeys:
;    Ctrl+Alt+J        insert the RTL character at the caret (manual
;                      recovery; Claude only; works even when seeding is
;                      toggled off or the layout is English)
;    Ctrl+Alt+Shift+R  toggle automatic seeding on/off (global)
;
;  First-keystroke seeding (v1.3): earlier versions planted the mark in the
;  EMPTY input right after a send, a click or a return to Claude. Claude then
;  saw a non-empty draft and showed its send button instead of the stop
;  button while a reply was running. Now those events only arm the helper;
;  the mark goes in when the first character of the next message is typed.
;  While armed, an input hook holds back that one character and re-sends it
;  right behind the mark, so nothing is lost or reordered; every other key
;  (Enter, arrows, Backspace, shortcuts) passes straight through. The hook
;  runs only while Claude's main window is active, the layout is Hebrew and
;  the draft is not seeded yet, and stops after that one character.
; =============================================================================

KeyHistory 0
ListLines 0

SEED := Chr(0x202B)                  ; U+202B RIGHT-TO-LEFT EMBEDDING
TOGGLE_LABEL := "Claude RTL seeding"
CLAUDE := "ahk_exe Claude.exe"       ; the app this helper serves
MAIN_CLASS := "Chrome_WidgetWin_1"   ; its main window (not native dialogs)

global rtlOn := true
global winSeeded := Map()            ; hwnd, is its current draft seeded?
global winTitle := Map()             ; hwnd, last seen window title
global claudeGone := 0               ; watcher ticks with no Claude present
global seedDeadline := 0             ; latest tick a deferred seed may wait for
global prevActive := 0               ; last Claude window seen as active
global lastRearmAt := 0              ; tick of the last click/deletion re-arm

; Holds back text keys only (VisibleText is false by default); every
; non-text key passes through untouched. Started and stopped by Rearm().
; The script's own Send/SendText would be caught by this hook too, so every
; seeding path stops it before typing (see Rearm and FirstChar).
global firstKey := InputHook("L0")
firstKey.VisibleNonText := true
firstKey.BackspaceIsUndo := false    ; otherwise the hook swallows Backspace
firstKey.KeyOpt("{Enter}{NumpadEnter}{Tab}{Esc}", "I")  ; no text: pass through
firstKey.OnChar := FirstChar

A_IconTip := "Claude RTL: on"
A_TrayMenu.Add(TOGGLE_LABEL, (*) => ToggleRtl())
A_TrayMenu.Check(TOGGLE_LABEL)
SetTimer(WatchClaude, 300)

; ---- state checks -----------------------------------------------------------

IsHebrewLayout() {
    hwnd := WinActive("A")
    if !hwnd
        return false
    tid := DllCall("GetWindowThreadProcessId", "ptr", hwnd, "ptr", 0, "uint")
    return (DllCall("GetKeyboardLayout", "uint", tid, "ptr") & 0xFFFF) = 0x040D  ; he-IL
}

; The hwnd of Claude's active MAIN window, or 0. Native dialogs (class
; #32770, e.g. the file picker) are excluded, so a seed is never typed
; into a file-name field.
ClaudeMainActive() {
    hwnd := WinActive(CLAUDE)
    if !hwnd
        return 0
    try cls := WinGetClass(hwnd)
    catch
        return 0
    return (cls = MAIN_CLASS) ? hwnd : 0
}

; ---- first-keystroke seeding ------------------------------------------------

; Runs the input hook exactly while it is needed: Claude's main window is
; active, seeding is on, the layout is Hebrew and the draft has no mark yet.
Rearm() {
    hwnd := ClaudeMainActive()
    want := rtlOn && hwnd && !winSeeded.Get(hwnd, false) && IsHebrewLayout()
    if (want && !firstKey.InProgress)
        firstKey.Start()
    else if (!want && firstKey.InProgress)
        firstKey.Stop()
}

; The first character of a message: put the mark in front of it. Characters
; typed while this ran were held back too; each gets its own call, queued
; behind this one (Critical keeps them from interrupting each other), and
; is re-sent in order without a second mark. A held character is always
; re-sent, so a keystroke is never lost even if conditions changed.
FirstChar(ih, ch) {
    Critical
    global winSeeded
    hwnd := ClaudeMainActive()
    ih.Stop()                        ; before typing, or it catches our own text
    if (hwnd && rtlOn && !winSeeded.Get(hwnd, false) && IsHebrewLayout()) {
        winSeeded[hwnd] := true
        SendText(SEED ch)
    } else {
        SendText(ch)
        Rearm()                      ; restarts only if still wanted
    }
}

; Mark the active draft as needing a seed, and arm the hook at once (the
; watcher would also do it, but up to 300ms later).
Unseed() {
    global winSeeded
    hwnd := ClaudeMainActive()
    if hwnd
        winSeeded[hwnd] := false
    Rearm()
}

; ---- seeding a draft that already has text ----------------------------------

; Seed at the start of the message, waiting out any typing burst first
; (so the Ctrl+Home / Ctrl+End dance never interleaves with keystrokes).
; Used after a paste, where the draft is already non-empty.
SeedLineStart() {
    global winSeeded
    if !rtlOn
        return
    hwnd := ClaudeMainActive()
    if !hwnd
        return
    if winSeeded.Get(hwnd, false)
        return                       ; already seeded - never double up
    if !IsHebrewLayout()
        return
    ; Wait for a gap in typing so the Home/End navigation cannot interleave
    ; with real keystrokes - but never wait forever.
    if (A_TimeIdlePhysical < 250 && A_TickCount < seedDeadline) {
        SetTimer(SeedLineStart, -200)
        return
    }
    winSeeded[hwnd] := true
    Rearm()                          ; stops the hook before we type
    Send("^{Home}")
    SendText(SEED)
    Send("^{End}")
}

; Seed the fresh line created by Shift+Enter. Every line break starts a new
; bidi paragraph, so without this the second line and onward render LTR
; again. Each key press schedules its own one-shot timer, so a rapid
; second Shift+Enter is never dropped and the hotkey thread never blocks.
; {Home} and {End} bracket the new line, keeping the mark at its start.
ArmNewLineSeed() {
    SetTimer(() => SeedNewLine(), -60)  ; a fresh timer per press, on purpose
}

SeedNewLine() {
    if (!rtlOn || !ClaudeMainActive() || !IsHebrewLayout())
        return
    firstKey.Stop()                  ; never catch our own mark
    Send("{Home}")
    SendText(SEED)
    Send("{End}")
    Rearm()
}

AfterPaste() {
    global seedDeadline
    hwnd := ClaudeMainActive()
    if (!hwnd || winSeeded.Get(hwnd, false))
        return
    seedDeadline := A_TickCount + 1500
    SetTimer(SeedLineStart, -250)
}

; ---- window / layout watcher ------------------------------------------------

; Ticks every 300ms. Treats a newly opened window, a title change and a
; return to Claude from elsewhere as "the input may have been replaced"
; and re-arms the first-keystroke seed. It never types anything itself,
; so an empty input stays empty. Rearm() also follows layout switches.
WatchClaude() {
    global winSeeded, winTitle, claudeGone, prevActive
    DetectHiddenWindows True         ; Claude minimized to the tray is alive
    if !WinExist(CLAUDE) {
        if (++claudeGone = 10) {     ; ~3s with no Claude: forget old windows
            winSeeded.Clear()        ; (also guards against hwnd reuse)
            winTitle.Clear()
        }
        Rearm()
        return
    }
    claudeGone := 0
    dead := []                       ; drop entries whose window is gone, so
    for h, seen in winSeeded         ; a recycled hwnd can't inherit state
        if !WinExist(CLAUDE " ahk_id " h)
            dead.Push(h)
    for h in dead {
        winSeeded.Delete(h)
        if winTitle.Has(h)              ; Delete throws on a missing key, and
            winTitle.Delete(h)          ; a window can be seeded before the
    }                                   ; watcher ever recorded its title
    hwnd := ClaudeMainActive()
    if !hwnd {
        prevActive := 0              ; focus left Claude - arm the next return
        Rearm()
        return
    }
    try title := WinGetTitle(hwnd)
    catch
        title := ""
    if (winTitle.Get(hwnd, "") != title) {
        winTitle[hwnd] := title
        winSeeded[hwnd] := false
    }
    if (hwnd != prevActive) {        ; back from elsewhere: the input was very
        prevActive := hwnd           ; likely replaced by a mouse action the
        winSeeded[hwnd] := false     ; script cannot see
    }
    Rearm()
}

; ---- toggle -----------------------------------------------------------------

ToggleRtl() {
    global rtlOn := !rtlOn
    A_IconTip := "Claude RTL: " (rtlOn ? "on" : "off")
    if rtlOn {
        A_TrayMenu.Check(TOGGLE_LABEL)
    } else {
        A_TrayMenu.Uncheck(TOGGLE_LABEL)
        SetTimer(SeedLineStart, 0)   ; cancel anything pending
    }
    Rearm()
    ToolTip("Claude RTL " (rtlOn ? "ON" : "OFF"))
    SetTimer(ClearToolTip, -1200)    ; named, so rapid toggles reset one timer
}

ClearToolTip() {
    ToolTip()
}

^!+r::ToggleRtl()                    ; global on purpose - usable anywhere

; ---- Claude-scoped hotkeys --------------------------------------------------
; All pass-through hotkeys use ~: the real keystroke always reaches Claude
; first, so a script fault can never block sending a message.

#HotIf WinActive(CLAUDE)

~Enter::        Unseed()             ; message sent: the input is empty again
~NumpadEnter::  Unseed()
~+Enter::       ArmNewLineSeed()
~+NumpadEnter:: ArmNewLineSeed()
~^n::           Unseed()             ; new chat
~^v::           AfterPaste()
^!j::           ManualSeed()
~Backspace::    RearmLimited()       ; deletion may have removed the mark
~Delete::       RearmLimited()
~LButton::      RearmLimited()       ; a click may have sent or switched chat

#HotIf

ManualSeed() {
    global winSeeded
    hwnd := ClaudeMainActive()
    if !hwnd
        return                       ; never type into dialogs, even manually
    winSeeded[hwnd] := true          ; user handled it - no automatic follow-up
    Rearm()                          ; stops the hook before we type
    SendText(SEED)
}

; The script cannot read the draft, so after a deletion or a click it
; cannot know whether the mark is gone or the input was emptied. It re-arms
; instead: the next typed character gets a mark in front of it. Where the
; draft is intact, that mark lands mid-text, where it is invisible and inert
; (the text is already inside an embedding). At most once per 3 seconds, so
; ordinary typo fixes do not scatter marks through a long draft.
RearmLimited() {
    global lastRearmAt
    if (A_TickCount - lastRearmAt < 3000)
        return
    lastRearmAt := A_TickCount
    Unseed()
}
