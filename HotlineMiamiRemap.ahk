;=============================================================================
;  Hotline Miami Remap
;  Remaps keys in Hotline Miami (and Hotline Miami 2) to other keys or mouse
;  buttons, using AutoHotkey v2.
;
;  Out of the box:
;      E  ->  right mouse button  (throw / pick up weapon)
;
;  Everything else is optional and switched off until you want it, including
;  the WASD / movement group. Press F9 (or use the tray icon) to open the
;  settings window and turn things on, add your own remaps, or change which
;  key does what.
;
;  Hotkeys (both configurable):
;      F8   remapping on / off
;      F9   open settings
;
;  Settings live in HotlineMiamiRemap.ini next to this file, so the whole
;  thing stays portable: copy the folder, keep your setup.
;
;  Requires AutoHotkey v2.0 or newer: https://www.autohotkey.com/
;  Licensed under the GPL-3.0, same as the rest of this repository.
;=============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#MaxThreadsPerHotkey 2
#UseHook true

InstallKeybdHook()
InstallMouseHook()
KeyHistory(0)
ListLines(false)
SetTitleMatchMode(2)
SetKeyDelay(-1, -1)
SetMouseDelay(-1)
SetWorkingDir(A_ScriptDir)
Persistent()
try ProcessSetPriority("High")

;-----------------------------------------------------------------------------
;  Everything the script knows about itself lives here, so no global soup.
;-----------------------------------------------------------------------------
class Cfg {
    static Name      := "Hotline Miami Remap"
    static Ver       := "1.0"
    static File      := A_ScriptDir "\HotlineMiamiRemap.ini"
    static FirstRun  := false

    static Enabled   := true            ; master on / off switch
    static SendMode  := "Input"         ; Input | Event | Play
    static AnyWindow := false           ; true = remap everywhere, not just in game
    static Guard     := true            ; release held keys when the game loses focus
    static Toasts    := true            ; small on screen messages
    static ToggleHk  := "F8"
    static MenuHk    := "F9"

    static Exes      := ["HotlineMiami.exe", "HotlineMiami2.exe"]
    static Titles    := ["Hotline Miami"]

    static Profiles  := Map()           ; name -> array of remaps
    static Active    := "Default"

    static Held      := Map()           ; target key -> how many sources hold it
    static Reg       := []              ; registered in game hotkey names
    static GlobalReg := []              ; registered global hotkey names
    static Win       := ""              ; settings window, if open
    static GameOn    := false           ; was the game focused last time we looked

    static Current() {
        if !Cfg.Profiles.Has(Cfg.Active)
            Cfg.Profiles[Cfg.Active] := []
        return Cfg.Profiles[Cfg.Active]
    }
}

;=============================================================================
;  Start up
;=============================================================================
LoadConfig()
BuildTray()
RegisterGlobal()
RegisterHotkeys()
SetTimer(Watchdog, 300)
if Cfg.FirstRun {
    msg := "Welcome.`n`n"
    msg .= "E is now the throw button (right mouse) while Hotline Miami is in focus.`n`n"
    msg .= "Everything else, including the WASD / movement remaps, is switched off "
    msg .= "until you turn it on. The settings window is opening now, and you can "
    msg .= "always get back to it with " Cfg.MenuHk " or the tray icon."
    MsgBox(msg, Cfg.Name, "Iconi")
    ShowSettings()
}

;=============================================================================
;  Defaults
;=============================================================================
Mapping(from, to, group := "Extras", enabled := false, note := "", mode := "hold", interval := 60, pass := false) {
    m := { From: from, To: to, Group: group, Enabled: enabled, Note: note }
    m.Mode     := mode          ; hold | tap | toggle | turbo
    m.Interval := interval      ; turbo speed in milliseconds
    m.Pass     := pass          ; also send the original key
    m.Down     := false         ; runtime: is the source key held right now
    m.Toggle   := false         ; runtime: toggle mode latched
    m.Timer    := ""            ; runtime: turbo timer
    return m
}

DefaultMappings() {
    list := []

    ; The one everybody comes here for.
    list.Push(Mapping("e", "RButton", "Core", true, "Throw / pick up weapon"))
    list.Push(Mapping("q", "LButton", "Core", false, "Attack with the left mouse button"))

    ; Movement, off by default: tick one box to play with the arrow keys.
    list.Push(Mapping("Up",    "w", "Movement", false, "Arrow keys move instead of WASD"))
    list.Push(Mapping("Left",  "a", "Movement", false, "Arrow keys move instead of WASD"))
    list.Push(Mapping("Down",  "s", "Movement", false, "Arrow keys move instead of WASD"))
    list.Push(Mapping("Right", "d", "Movement", false, "Arrow keys move instead of WASD"))

    ; Handy extras, all off by default.
    list.Push(Mapping("XButton1", "r", "Extras", false, "Mouse button 4 restarts the level", "tap"))
    list.Push(Mapping("XButton2", "Space", "Extras", false, "Mouse button 5 is the look / lock key"))
    list.Push(Mapping("CapsLock", "Shift", "Extras", false, "Caps Lock becomes Shift"))
    list.Push(Mapping("LWin", "None", "Extras", false, "Stop the Windows key from minimising the game"))
    list.Push(Mapping("RAlt", "LButton", "Extras", false, "Rapid attack while held", "turbo", 60))

    return list
}

;=============================================================================
;  Config file
;=============================================================================
SplitList(text, sep := "|") {
    out := []
    for part in StrSplit(text, sep) {
        part := Trim(part)
        if (part != "")
            out.Push(part)
    }
    return out
}

JoinList(list, sep := "|") {
    out := ""
    for item in list
        out .= (out = "" ? "" : sep) item
    return out
}

; Profile names end up as ini section names, so keep them boring.
CleanName(text) {
    text := RegExReplace(Clean(text), "[\[\]=;]", "")
    return Trim(text)
}

Clean(text) {
    text := StrReplace(text, "|", "/")
    text := StrReplace(text, "`r", " ")
    text := StrReplace(text, "`n", " ")
    return Trim(text)
}

LoadConfig() {
    f := Cfg.File
    if !FileExist(f) {
        Cfg.FirstRun := true
        Cfg.Profiles := Map("Default", DefaultMappings())
        Cfg.Active   := "Default"
        SaveConfig()
        return
    }

    Cfg.Enabled   := IniRead(f, "General", "Enabled", "1") = "1"
    Cfg.SendMode  := IniRead(f, "General", "SendMode", "Input")
    Cfg.AnyWindow := IniRead(f, "General", "AnyWindow", "0") = "1"
    Cfg.Guard     := IniRead(f, "General", "StuckKeyGuard", "1") = "1"
    Cfg.Toasts    := IniRead(f, "General", "Notifications", "1") = "1"
    Cfg.ToggleHk  := IniRead(f, "General", "ToggleHotkey", "F8")
    Cfg.MenuHk    := IniRead(f, "General", "SettingsHotkey", "F9")
    Cfg.Exes      := SplitList(IniRead(f, "General", "GameExes", "HotlineMiami.exe|HotlineMiami2.exe"))
    Cfg.Titles    := SplitList(IniRead(f, "General", "GameTitles", "Hotline Miami"))

    Cfg.Profiles := Map()
    for name in SplitList(IniRead(f, "General", "Profiles", "Default")) {
        list  := []
        count := 0
        try count := Integer(IniRead(f, "Profile " name, "Count", "0"))
        loop count {
            m := ParseMapping(IniRead(f, "Profile " name, "M" A_Index, ""))
            if IsObject(m)
                list.Push(m)
        }
        Cfg.Profiles[name] := list
    }
    if (Cfg.Profiles.Count = 0)
        Cfg.Profiles["Default"] := DefaultMappings()

    Cfg.Active := IniRead(f, "General", "ActiveProfile", "Default")
    if !Cfg.Profiles.Has(Cfg.Active) {
        for name in Cfg.Profiles {
            Cfg.Active := name
            break
        }
    }
}

; enabled | from | to | mode | interval | passthrough | group | note
ParseMapping(line) {
    if (Trim(line) = "")
        return ""
    p := StrSplit(line, "|")
    while (p.Length < 8)
        p.Push("")

    from := Trim(p[2])
    if (from = "")
        return ""

    interval := 60
    try interval := Integer(Trim(p[5]))

    group := Trim(p[7]) = "" ? "Extras" : Trim(p[7])
    mode  := Trim(p[4]) = "" ? "hold"   : StrLower(Trim(p[4]))

    return Mapping(from, Trim(p[3]), group, Trim(p[1]) = "1", Trim(p[8]), mode, interval, Trim(p[6]) = "1")
}

DumpMapping(m) {
    out := (m.Enabled ? "1" : "0") "|" m.From "|" m.To "|" m.Mode "|" m.Interval
    out .= "|" (m.Pass ? "1" : "0") "|" Clean(m.Group) "|" Clean(m.Note)
    return out
}

SaveConfig() {
    f := Cfg.File

    ; drop the sections we wrote last time so removed profiles do not linger
    for name in SplitList(IniRead(f, "General", "Profiles", ""))
        try IniDelete(f, "Profile " name)

    IniWrite(Cfg.Enabled   ? 1 : 0, f, "General", "Enabled")
    IniWrite(Cfg.SendMode,          f, "General", "SendMode")
    IniWrite(Cfg.AnyWindow ? 1 : 0, f, "General", "AnyWindow")
    IniWrite(Cfg.Guard     ? 1 : 0, f, "General", "StuckKeyGuard")
    IniWrite(Cfg.Toasts    ? 1 : 0, f, "General", "Notifications")
    IniWrite(Cfg.ToggleHk,          f, "General", "ToggleHotkey")
    IniWrite(Cfg.MenuHk,            f, "General", "SettingsHotkey")
    IniWrite(JoinList(Cfg.Exes),    f, "General", "GameExes")
    IniWrite(JoinList(Cfg.Titles),  f, "General", "GameTitles")
    IniWrite(JoinList(ProfileNames()), f, "General", "Profiles")
    IniWrite(Cfg.Active,            f, "General", "ActiveProfile")

    for name, list in Cfg.Profiles {
        IniWrite(list.Length, f, "Profile " name, "Count")
        for i, m in list
            IniWrite(DumpMapping(m), f, "Profile " name, "M" i)
    }
}

ProfileNames() {
    names := []
    for name in Cfg.Profiles
        names.Push(name)
    return names
}

;=============================================================================
;  Sending keys
;=============================================================================
IsBlocker(key) {
    return (key = "" || StrLower(key) = "none")
}

; {Blind} keeps whatever modifiers the player is really holding intact.
; SendPlay does not take it, so that mode gets the bare key.
SendRaw(keys) {
    switch StrLower(Cfg.SendMode) {
        case "event": SendEvent("{Blind}" keys)
        case "play":  SendPlay(keys)
        default:      SendInput("{Blind}" keys)
    }
}

SendKeyState(key, state) {
    if IsBlocker(key)
        return
    SendRaw("{" key " " state "}")
}

SendTap(key) {
    if IsBlocker(key)
        return
    SendRaw("{" key "}")
}

; Two sources can point at the same target, so hold counts are refcounted:
; the target only goes up once the last source lets go.
TargetDown(key) {
    if IsBlocker(key)
        return
    n := Cfg.Held.Has(key) ? Cfg.Held[key] : 0
    Cfg.Held[key] := n + 1
    if (n = 0)
        SendKeyState(key, "down")
}

TargetUp(key) {
    if (IsBlocker(key) || !Cfg.Held.Has(key))
        return
    n := Cfg.Held[key] - 1
    if (n > 0) {
        Cfg.Held[key] := n
        return
    }
    Cfg.Held.Delete(key)
    SendKeyState(key, "up")
}

StartTurbo(m) {
    StopTurbo(m)
    m.Timer := () => SendTap(m.To)
    SendTap(m.To)
    SetTimer(m.Timer, Max(10, m.Interval))
}

StopTurbo(m) {
    if IsObject(m.Timer) {
        SetTimer(m.Timer, 0)
        m.Timer := ""
    }
}

ReleaseAll() {
    keys := []
    for key in Cfg.Held
        keys.Push(key)
    for key in keys
        SendKeyState(key, "up")
    Cfg.Held.Clear()

    for name, list in Cfg.Profiles {
        for m in list {
            StopTurbo(m)
            m.Down   := false
            m.Toggle := false
        }
    }
}

;=============================================================================
;  The remap itself
;=============================================================================
IsGameActive() {
    if Cfg.AnyWindow
        return true
    for exe in Cfg.Exes {
        if WinActive("ahk_exe " exe)
            return true
    }
    for title in Cfg.Titles {
        if WinActive(title)
            return true
    }
    return false
}

; Used as the #HotIf context: when this is false the key behaves normally,
; so nothing is swallowed outside the game.
GameContext(*) {
    return Cfg.Enabled && IsGameActive()
}

OnSrcDown(m, *) {
    if m.Down                       ; ignore the key repeat storm from holding a key
        return
    m.Down := true
    if m.Pass
        SendKeyState(m.From, "down")

    switch StrLower(m.Mode) {
        case "tap":
            SendTap(m.To)
        case "toggle":
            if m.Toggle {
                m.Toggle := false
                TargetUp(m.To)
            } else {
                m.Toggle := true
                TargetDown(m.To)
            }
        case "turbo":
            StartTurbo(m)
        default:
            TargetDown(m.To)
    }
}

OnSrcUp(m, *) {
    if !m.Down
        return
    m.Down := false
    if m.Pass
        SendKeyState(m.From, "up")

    switch StrLower(m.Mode) {
        case "tap", "toggle":
            return                  ; these two keep going after the key is released
        case "turbo":
            StopTurbo(m)
        default:
            TargetUp(m.To)
    }
}

RegisterHotkeys() {
    UnregisterHotkeys()
    problems := ""

    HotIf(GameContext)
    for m in Cfg.Current() {
        if (!m.Enabled || Trim(m.From) = "")
            continue
        name := "$*" m.From
        try {
            Hotkey(name, OnSrcDown.Bind(m), "On")
            Cfg.Reg.Push(name)
        } catch as err {
            problems .= "`n  " m.From "  (" err.Message ")"
            continue
        }
        try {                       ; wheel "keys" have no release event, that is fine
            Hotkey(name " up", OnSrcUp.Bind(m), "On")
            Cfg.Reg.Push(name " up")
        }
    }
    HotIf()

    UpdateTray()
    if (problems != "")
        MsgBox("These keys could not be registered and were skipped:" problems, Cfg.Name, "Icon!")
}

UnregisterHotkeys() {
    HotIf(GameContext)
    for name in Cfg.Reg
        try Hotkey(name, , "Off")
    HotIf()
    Cfg.Reg := []
    ReleaseAll()
}

RegisterGlobal() {
    HotIf()
    for name in Cfg.GlobalReg
        try Hotkey(name, , "Off")
    Cfg.GlobalReg := []

    if (Trim(Cfg.ToggleHk) != "") {
        try {
            Hotkey(Cfg.ToggleHk, (*) => ToggleEnabled(), "On")
            Cfg.GlobalReg.Push(Cfg.ToggleHk)
        } catch {
            MsgBox("'" Cfg.ToggleHk "' is not a hotkey AutoHotkey understands, so the on / off hotkey is unset.", Cfg.Name, "Icon!")
        }
    }
    if (Trim(Cfg.MenuHk) != "") {
        try {
            Hotkey(Cfg.MenuHk, (*) => ShowSettings(), "On")
            Cfg.GlobalReg.Push(Cfg.MenuHk)
        } catch {
            MsgBox("'" Cfg.MenuHk "' is not a hotkey AutoHotkey understands, so the settings hotkey is unset.", Cfg.Name, "Icon!")
        }
    }
}

ToggleEnabled(*) {
    Cfg.Enabled := !Cfg.Enabled
    if !Cfg.Enabled
        ReleaseAll()
    UpdateTray()
    Toast(Cfg.Enabled ? "Remapping ON" : "Remapping OFF")
    if IsObject(Cfg.Win) {
        try Cfg.Win["Master"].Value := Cfg.Enabled ? 1 : 0
    }
    try IniWrite(Cfg.Enabled ? 1 : 0, Cfg.File, "General", "Enabled")
}

; Runs a few times a second: catches alt tab, the game closing mid press,
; and anything else that could leave a key stuck down.
Watchdog() {
    active := Cfg.Enabled && IsGameActive()
    if (active = Cfg.GameOn)
        return
    Cfg.GameOn := active
    if (!active && Cfg.Guard)
        ReleaseAll()
    UpdateTray()
}

;=============================================================================
;  Tray icon
;=============================================================================
BuildTray() {
    tray := A_TrayMenu
    tray.Delete()
    tray.Add("Settings", (*) => ShowSettings())
    tray.Add("Remapping enabled", (*) => ToggleEnabled())
    tray.Add()
    tray.Add("Open config file", (*) => OpenConfigFile())
    tray.Add("Reload script", (*) => Reload())
    tray.Add()
    tray.Add("Exit", (*) => ExitApp())
    tray.Default := "Settings"
    tray.ClickCount := 1
    UpdateTray()
}

UpdateTray() {
    state := !Cfg.Enabled ? "off" : (IsGameActive() ? "active" : "waiting for the game")
    A_IconTip := Cfg.Name "`nProfile: " Cfg.Active "`nStatus: " state
    try {
        if Cfg.Enabled
            A_TrayMenu.Check("Remapping enabled")
        else
            A_TrayMenu.Uncheck("Remapping enabled")
    }
    try TraySetIcon(A_AhkPath, Cfg.Enabled ? 1 : 2, true)
}

OpenConfigFile() {
    if !FileExist(Cfg.File)
        SaveConfig()
    try Run('notepad.exe "' Cfg.File '"')
}

Toast(text, ms := 1200) {
    if !Cfg.Toasts
        return
    ToolTip(text)
    SetTimer(() => ToolTip(), -ms)
}

;=============================================================================
;  Small helpers shared by the windows
;=============================================================================
ValidKey(key) {
    key := Trim(key)
    if (key = "")
        return false
    if IsBlocker(key)
        return true
    static wheels := "|wheelup|wheeldown|wheelleft|wheelright|"
    if InStr(wheels, "|" StrLower(key) "|")
        return true
    try {
        if (GetKeyVK(key) != 0)
            return true
    }
    try {
        if (GetKeySC(key) != 0)
            return true
    }
    return false
}

PrettyKey(key) {
    static names := Map(
        "LButton", "left mouse", "RButton", "right mouse", "MButton", "middle mouse",
        "XButton1", "mouse 4", "XButton2", "mouse 5",
        "WheelUp", "wheel up", "WheelDown", "wheel down")
    if IsBlocker(key)
        return "nothing (key blocked)"
    return names.Has(key) ? key " (" names[key] ")" : key
}

ModeLabel(m) {
    switch StrLower(m.Mode) {
        case "tap":    return "tap"
        case "toggle": return "toggle"
        case "turbo":  return "turbo " m.Interval "ms"
        default:       return "hold"
    }
}

GroupNames() {
    seen := Map()
    out  := []
    for m in Cfg.Current() {
        if !seen.Has(m.Group) {
            seen[m.Group] := true
            out.Push(m.Group)
        }
    }
    for fixed in ["Core", "Movement", "Extras"] {
        if !seen.Has(fixed) {
            seen[fixed] := true
            out.Push(fixed)
        }
    }
    return out
}

GroupEnabled(group) {
    for m in Cfg.Current() {
        if (m.Group = group && m.Enabled)
            return true
    }
    return false
}

SetGroupEnabled(group, on) {
    for m in Cfg.Current() {
        if (m.Group = group)
            m.Enabled := on
    }
}

StartupLink() {
    return A_Startup "\Hotline Miami Remap.lnk"
}

ApplyNow() {
    RegisterHotkeys()
    SaveConfig()
}

;=============================================================================
;  "Press a key" capture window
;=============================================================================
CaptureKey(owner) {
    result  := ""
    buttons := ["LButton", "RButton", "MButton", "XButton1", "XButton2", "WheelUp", "WheelDown"]

    cg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox +ToolWindow +Owner" owner.Hwnd, "Press a key")
    cg.SetFont("s10", "Segoe UI")
    cg.AddText("w320 Center", "Press any key or mouse button.`n`nEsc cancels.")
    cg.Show("AutoSize")

    ih := InputHook("T15")          ; give up after fifteen seconds rather than hang
    ih.VisibleNonText := false
    ih.KeyOpt("{All}", "E")
    ih.Start()

    HotIf()
    for b in buttons
        try Hotkey("*" b, CaptureBtn, "On")

    ih.Wait()

    for b in buttons
        try Hotkey("*" b, CaptureBtn, "Off")

    if (result = "")
        result := ih.EndKey
    try cg.Destroy()
    try WinActivate("ahk_id " owner.Hwnd)

    return (result = "Escape") ? "" : result

    CaptureBtn(hk, *) {
        result := RegExReplace(hk, "^[*~$#!^+]+")
        ih.Stop()
    }
}

;=============================================================================
;  Edit one remap
;=============================================================================
EditMapping(owner, m) {
    done := 0

    d := Gui("-MaximizeBox -MinimizeBox +Owner" owner.Hwnd, "Remap details")
    d.SetFont("s9", "Segoe UI")
    d.MarginX := 14
    d.MarginY := 12
    owner.Opt("+Disabled")

    d.AddText("xm ym+4 w110 h22 +0x200", "When I press:")
    eFrom := d.AddEdit("x+6 yp w150 h22", m.From)
    d.AddButton("x+6 yp-1 w90 h24", "Capture").OnEvent("Click", CapFrom)

    d.AddText("xm y+10 w110 h22 +0x200", "The game gets:")
    eTo := d.AddEdit("x+6 yp w150 h22", m.To)
    d.AddButton("x+6 yp-1 w90 h24", "Capture").OnEvent("Click", CapTo)
    d.AddText("xm y+6 w380 cGray", "RButton = throw, LButton = attack, None = swallow the key.")

    d.AddText("xm y+12 w110 h22 +0x200", "Mode:")
    ddMode := d.AddDropDownList("x+6 yp-2 w150", ["hold", "tap", "toggle", "turbo"])
    ddMode.Choose(StrLower(m.Mode))
    d.AddText("x+12 yp+4 w70 h22 +0x200", "Turbo ms:")
    eInt := d.AddEdit("x+4 yp-2 w60 h22 Number", m.Interval)

    d.AddText("xm y+12 w110 h22 +0x200", "Group:")
    cbGroup := d.AddComboBox("x+6 yp-2 w150", GroupNames())
    cbGroup.Text := m.Group
    d.AddText("x+12 yp+4 w50 h22 +0x200", "Notes:")
    eNote := d.AddEdit("x+4 yp-2 w180 h22", m.Note)

    cEn := d.AddCheckbox("xm y+14", "Enabled")
    cEn.Value := m.Enabled ? 1 : 0
    cPass := d.AddCheckbox("x+24 yp", "Also send the original key")
    cPass.Value := m.Pass ? 1 : 0

    d.AddButton("xm y+16 w120 h30 Default", "OK").OnEvent("Click", OkClick)
    d.AddButton("x+8 yp w120 h30", "Cancel").OnEvent("Click", (*) => Finish(2))
    d.OnEvent("Close",  (*) => Finish(2))
    d.OnEvent("Escape", (*) => Finish(2))
    d.Show()

    while (done = 0)
        Sleep(40)

    owner.Opt("-Disabled")
    try WinActivate("ahk_id " owner.Hwnd)
    try d.Destroy()                 ; closing the window may have destroyed it already
    return (done = 1)

    CapFrom(*) {
        key := CaptureKey(d)
        if (key != "")
            eFrom.Value := key
    }

    CapTo(*) {
        key := CaptureKey(d)
        if (key != "")
            eTo.Value := key
    }

    OkClick(*) {
        from := Trim(eFrom.Value)
        to   := Trim(eTo.Value)
        if (to = "")
            to := "None"

        if !ValidKey(from) {
            MsgBox("'" from "' is not a key name AutoHotkey knows.`n`nUse the Capture button if you are not sure.", Cfg.Name, "Icon! Owner" d.Hwnd)
            return
        }
        if !ValidKey(to) {
            MsgBox("'" to "' is not a key name AutoHotkey knows.`n`nUse the Capture button, or None to block the key.", Cfg.Name, "Icon! Owner" d.Hwnd)
            return
        }

        interval := 60
        try interval := Integer(eInt.Value)

        m.From     := from
        m.To       := to
        m.Mode     := StrLower(ddMode.Text)
        m.Interval := Max(10, interval)
        m.Group    := Trim(cbGroup.Text) = "" ? "Extras" : Clean(cbGroup.Text)
        m.Note     := Clean(eNote.Value)
        m.Enabled  := cEn.Value ? true : false
        m.Pass     := cPass.Value ? true : false
        Finish(1)
    }

    Finish(code) {
        done := code
    }
}

;=============================================================================
;  Settings window
;=============================================================================
ShowSettings(*) {
    if IsObject(Cfg.Win) {
        try {
            Cfg.Win.Show()
            WinActivate("ahk_id " Cfg.Win.Hwnd)
            return
        }
        Cfg.Win := ""
    }

    g := Gui("-MaximizeBox", Cfg.Name " " Cfg.Ver)
    Cfg.Win := g
    g.SetFont("s9", "Segoe UI")
    g.MarginX := 14
    g.MarginY := 12

    ; ---- profile row --------------------------------------------------------
    g.AddText("xm ym+6 w50 h22 +0x200", "Profile:")
    dd := g.AddDropDownList("x+4 yp w170 vProfile", ProfileNames())
    dd.Choose(Cfg.Active)
    dd.OnEvent("Change", ProfileChanged)
    g.AddButton("x+8 yp-1 w60 h24", "New").OnEvent("Click", NewProfile)
    g.AddButton("x+4 yp w60 h24", "Copy").OnEvent("Click", CopyProfile)
    g.AddButton("x+4 yp w60 h24", "Delete").OnEvent("Click", DeleteProfile)
    master := g.AddCheckbox("x+20 yp+4 vMaster", "Remapping enabled (" Cfg.ToggleHk ")")
    master.Value := Cfg.Enabled ? 1 : 0
    master.OnEvent("Click", MasterClick)

    ; ---- the list of remaps -------------------------------------------------
    lv := g.AddListView("xm y+12 w700 r13 -Multi Grid vList",
        ["On", "When I press", "The game gets", "Mode", "Group", "Notes"])
    lv.OnEvent("DoubleClick", (*) => EditRow())

    g.AddButton("xm y+8 w86 h27", "Add").OnEvent("Click", (*) => AddRow())
    g.AddButton("x+6 yp w86 h27", "Edit").OnEvent("Click", (*) => EditRow())
    g.AddButton("x+6 yp w86 h27", "On / off").OnEvent("Click", (*) => ToggleRow())
    g.AddButton("x+6 yp w86 h27", "Remove").OnEvent("Click", (*) => RemoveRow())
    g.AddButton("x+6 yp w120 h27", "Restore defaults").OnEvent("Click", (*) => RestoreDefaults())
    g.AddText("x+14 yp+6 w160 cGray", "Double click a row to edit")

    ; ---- options ------------------------------------------------------------
    g.AddGroupBox("xm y+14 w700 h190", "Options")

    wasd := g.AddCheckbox("xp+14 yp+26 w650 vWasd", "Enable the movement group (arrow keys move, WASD style). Off by default.")
    wasd.Value := GroupEnabled("Movement") ? 1 : 0
    wasd.OnEvent("Click", WasdClick)

    onlyGame := g.AddCheckbox("xm+14 y+8 w320 vOnlyGame", "Only remap while Hotline Miami is in focus")
    onlyGame.Value := Cfg.AnyWindow ? 0 : 1
    guard := g.AddCheckbox("x+10 yp w320 vGuard", "Release stuck keys automatically")
    guard.Value := Cfg.Guard ? 1 : 0

    toasts := g.AddCheckbox("xm+14 y+8 w320 vToasts", "Show on screen messages")
    toasts.Value := Cfg.Toasts ? 1 : 0
    g.AddButton("x+10 yp-4 w200 h26 vStartup", StartupLabel()).OnEvent("Click", StartupClick)

    g.AddText("xm+14 y+12 w110 h22 +0x200", "Game programs:")
    g.AddEdit("x+6 yp w330 h22 vExes", JoinList(Cfg.Exes, ", "))
    g.AddText("x+14 yp w70 h22 +0x200", "Send using:")
    sendDd := g.AddDropDownList("x+4 yp-2 w90 vSend", ["Input", "Event", "Play"])
    sendDd.Choose(Cfg.SendMode)

    g.AddText("xm+14 y+10 w110 h22 +0x200", "On / off hotkey:")
    g.AddEdit("x+6 yp w100 h22 vToggleHk", Cfg.ToggleHk)
    g.AddText("x+16 yp w100 h22 +0x200", "Settings hotkey:")
    g.AddEdit("x+6 yp w100 h22 vMenuHk", Cfg.MenuHk)

    ; ---- bottom row ---------------------------------------------------------
    g.AddButton("xm y+16 w150 h32 Default", "Apply and save").OnEvent("Click", (*) => ApplyOptions())
    g.AddButton("x+8 yp w110 h32", "Help").OnEvent("Click", (*) => ShowHelp(g))
    g.AddButton("x+8 yp w110 h32", "Close").OnEvent("Click", (*) => CloseSettings())
    g.AddText("x+16 yp+9 w280 cGray", "Remaps apply the moment you change them.")

    g.OnEvent("Close",  (*) => CloseSettings())
    g.OnEvent("Escape", (*) => CloseSettings())

    RefreshList()
    g.Show()
    return

    ; ---- nested handlers ----------------------------------------------------
    RefreshList() {
        lv.Opt("-Redraw")
        lv.Delete()
        for m in Cfg.Current()
            lv.Add("", m.Enabled ? "ON" : "off", PrettyKey(m.From), PrettyKey(m.To), ModeLabel(m), m.Group, m.Note)
        lv.Opt("+Redraw")
        loop 6
            lv.ModifyCol(A_Index, "AutoHdr")
        SyncBoxes()
    }

    SyncBoxes() {
        wasd.Value   := GroupEnabled("Movement") ? 1 : 0
        master.Value := Cfg.Enabled ? 1 : 0
    }

    Selected() {
        row := lv.GetNext()
        if (row = 0) {
            MsgBox("Pick a row in the list first.", Cfg.Name, "Iconi Owner" g.Hwnd)
            return 0
        }
        return row
    }

    AddRow() {
        m := Mapping("", "None", "Extras", true, "")
        if EditMapping(g, m) {
            Cfg.Current().Push(m)
            RefreshList()
            ApplyNow()
        }
    }

    EditRow() {
        row := Selected()
        if (row = 0)
            return
        if EditMapping(g, Cfg.Current()[row]) {
            RefreshList()
            lv.Modify(row, "Select Focus")
            ApplyNow()
        }
    }

    ToggleRow() {
        row := Selected()
        if (row = 0)
            return
        m := Cfg.Current()[row]
        m.Enabled := !m.Enabled
        RefreshList()
        lv.Modify(row, "Select Focus")
        ApplyNow()
    }

    RemoveRow() {
        row := Selected()
        if (row = 0)
            return
        m := Cfg.Current()[row]
        if (MsgBox("Remove the remap for " PrettyKey(m.From) "?", Cfg.Name, "YesNo Icon? Owner" g.Hwnd) != "Yes")
            return
        Cfg.Current().RemoveAt(row)
        RefreshList()
        ApplyNow()
    }

    RestoreDefaults() {
        if (MsgBox("Replace every remap in the profile '" Cfg.Active "' with the defaults?", Cfg.Name, "YesNo Icon? Owner" g.Hwnd) != "Yes")
            return
        UnregisterHotkeys()
        Cfg.Profiles[Cfg.Active] := DefaultMappings()
        RefreshList()
        ApplyNow()
    }

    WasdClick(ctrl, *) {
        SetGroupEnabled("Movement", ctrl.Value ? true : false)
        RefreshList()
        ApplyNow()
        Toast(ctrl.Value ? "Movement remaps ON" : "Movement remaps OFF")
    }

    MasterClick(ctrl, *) {
        if ((ctrl.Value ? true : false) != Cfg.Enabled)
            ToggleEnabled()
    }

    ProfileChanged(ctrl, *) {
        if (ctrl.Text = "" || ctrl.Text = Cfg.Active)
            return
        UnregisterHotkeys()
        Cfg.Active := ctrl.Text
        RefreshList()
        ApplyNow()
        Toast("Profile: " Cfg.Active)
    }

    NewProfile(*) {
        name := AskName("Name for the new profile:")
        if (name = "")
            return
        UnregisterHotkeys()
        Cfg.Profiles[name] := DefaultMappings()
        Cfg.Active := name
        ReloadProfiles()
    }

    CopyProfile(*) {
        name := AskName("Name for the copy of '" Cfg.Active "':")
        if (name = "")
            return
        copy := []
        for m in Cfg.Current()
            copy.Push(Mapping(m.From, m.To, m.Group, m.Enabled, m.Note, m.Mode, m.Interval, m.Pass))
        UnregisterHotkeys()
        Cfg.Profiles[name] := copy
        Cfg.Active := name
        ReloadProfiles()
    }

    DeleteProfile(*) {
        if (Cfg.Profiles.Count <= 1) {
            MsgBox("There has to be at least one profile.", Cfg.Name, "Iconi Owner" g.Hwnd)
            return
        }
        if (MsgBox("Delete the profile '" Cfg.Active "'?", Cfg.Name, "YesNo Icon? Owner" g.Hwnd) != "Yes")
            return
        UnregisterHotkeys()
        Cfg.Profiles.Delete(Cfg.Active)
        for name in Cfg.Profiles {
            Cfg.Active := name
            break
        }
        ReloadProfiles()
    }

    ReloadProfiles() {
        dd.Delete()
        dd.Add(ProfileNames())
        dd.Choose(Cfg.Active)
        RefreshList()
        ApplyNow()
    }

    AskName(prompt) {
        answer := InputBox(prompt, Cfg.Name, "w320 h140")
        if (answer.Result != "OK")
            return ""
        name := CleanName(answer.Value)
        if (name = "")
            return ""
        if Cfg.Profiles.Has(name) {
            MsgBox("A profile called '" name "' already exists.", Cfg.Name, "Icon! Owner" g.Hwnd)
            return ""
        }
        return name
    }

    StartupLabel() {
        return FileExist(StartupLink()) ? "Remove from Windows startup" : "Run at Windows startup"
    }

    StartupClick(ctrl, *) {
        link := StartupLink()
        try {
            if FileExist(link) {
                FileDelete(link)
                Toast("Removed from Windows startup")
            } else {
                target := A_IsCompiled ? A_ScriptFullPath : A_AhkPath
                args   := A_IsCompiled ? "" : '"' A_ScriptFullPath '"'
                FileCreateShortcut(target, link, A_ScriptDir, args, Cfg.Name)
                Toast("Will start with Windows")
            }
        } catch as err {
            MsgBox("Could not change the startup shortcut.`n`n" err.Message, Cfg.Name, "Icon! Owner" g.Hwnd)
        }
        ctrl.Text := StartupLabel()
    }

    ApplyOptions() {
        exes := []
        for part in StrSplit(g["Exes"].Value, ",") {
            part := Trim(part)
            if (part != "")
                exes.Push(part)
        }
        if (exes.Length = 0)
            exes := ["HotlineMiami.exe", "HotlineMiami2.exe"]

        Cfg.Exes      := exes
        Cfg.AnyWindow := g["OnlyGame"].Value ? false : true
        Cfg.Guard     := g["Guard"].Value ? true : false
        Cfg.Toasts    := g["Toasts"].Value ? true : false
        Cfg.SendMode  := g["Send"].Text

        newToggle := Trim(g["ToggleHk"].Value)
        newMenu   := Trim(g["MenuHk"].Value)
        if (newToggle != Cfg.ToggleHk || newMenu != Cfg.MenuHk) {
            Cfg.ToggleHk := newToggle
            Cfg.MenuHk   := newMenu
            RegisterGlobal()
            master.Text := "Remapping enabled (" Cfg.ToggleHk ")"
        }

        ApplyNow()
        Toast("Settings saved")
    }

    CloseSettings() {
        try g.Destroy()
        Cfg.Win := ""
    }
}

ShowHelp(owner := "") {
    lines := []
    lines.Push("Hotline Miami Remap " Cfg.Ver)
    lines.Push("")
    lines.Push("How it works")
    lines.Push("  While a Hotline Miami window is in focus, the keys in the list are")
    lines.Push("  swapped for whatever you put in the second column. Everywhere else")
    lines.Push("  your keyboard behaves normally, so the script can stay running.")
    lines.Push("")
    lines.Push("Modes")
    lines.Push("  hold     the target is held for exactly as long as you hold your key.")
    lines.Push("           This is the one you want for throwing, attacking and moving.")
    lines.Push("  tap      one press, one click, no matter how long you hold the key.")
    lines.Push("  toggle   press once to hold the target down, press again to let go.")
    lines.Push("  turbo    repeats the target while you hold the key, at your interval.")
    lines.Push("")
    lines.Push("Useful key names")
    lines.Push("  Mouse:     LButton, RButton, MButton, XButton1, XButton2,")
    lines.Push("             WheelUp, WheelDown")
    lines.Push("  Movement:  w, a, s, d, Up, Down, Left, Right")
    lines.Push("  Other:     Space, Enter, Tab, Escape, Shift, Ctrl, Alt, CapsLock,")
    lines.Push("             F1 to F12, Numpad0 to Numpad9")
    lines.Push("  None       swallows the key so the game never sees it.")
    lines.Push("")
    lines.Push("Tips")
    lines.Push("  The Capture button records the next key or button you press.")
    lines.Push("  Two remaps can point at the same target without fighting each other.")
    lines.Push("  Profiles keep separate setups side by side, for example one per game.")
    lines.Push("  If a key ever feels stuck, press " Cfg.ToggleHk " twice.")
    lines.Push("  Settings live in HotlineMiamiRemap.ini next to the script.")

    text := ""
    for line in lines
        text .= line "`n"

    if IsObject(owner)
        MsgBox(text, Cfg.Name, "Iconi Owner" owner.Hwnd)
    else
        MsgBox(text, Cfg.Name, "Iconi")
}
