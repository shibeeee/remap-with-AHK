;=============================================================================
;  Remap
;  A small, general purpose key remapper for Windows, built on AutoHotkey v2.
;
;  Remaps live in profiles: plain text files in the "profiles" folder, each
;  one scoped to the programs you choose. A profile is either global or
;  limited to a list of programs, and it only does anything while one of
;  those programs is the window you are tabbed into. Several profiles can be
;  on at once; the profile scoped to the program you are in wins over a
;  global one when they both claim the same key.
;
;  Quick start
;      1. Install AutoHotkey v2 from https://www.autohotkey.com/
;      2. Double click this file. A tray icon appears.
;      3. Press F9 for the window, F8 to switch remapping on and off.
;
;  Profile format (see any file in the profiles folder)
;      [profile]
;      name        = Hotline Miami
;      description = Throw and pick up with E instead of right click.
;      enabled     = yes
;      match       = HotlineMiami.exe        ; blank = every program
;
;      [keys]
;      e = RButton, block        ; press E, the program receives right mouse
;
;  Binding options: hold (default), tap, toggle, turbo 60, pass, block, off.
;  A target of "none" swallows the key. Without "pass" the key you press is
;  cancelled, so the program never sees it.
;
;  Requires AutoHotkey v2.0 or newer. Licensed under the GPL-3.0.
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
;  All state lives here, so there are no loose globals to trip over.
;-----------------------------------------------------------------------------
class App {
    static Name       := "Remap"
    static Ver        := "2.0"
    static ProfileDir := A_ScriptDir "\profiles"
    static IniFile    := A_ScriptDir "\Remap.ini"
    static FirstRun   := false

    static Enabled    := true       ; master switch
    static SendMode   := "Input"    ; Input | Event | Play
    static Guard      := true       ; let go of keys that get stuck
    static Toasts     := true       ; small on screen messages
    static ToggleHk   := "F8"
    static MenuHk     := "F9"

    static Profiles   := []         ; every profile found in the folder
    static Routes     := Map()      ; source key -> candidate bindings, best first
    static HkKey      := Map()      ; hotkey name -> source key
    static Reg        := []         ; registered remap hotkeys
    static GlobalReg  := []         ; registered F8 / F9 style hotkeys

    static Held       := Map()      ; target key -> how many sources hold it
    static Down       := Map()      ; source key -> the binding holding it
    static Win        := ""         ; main window, when open
    static Status     := ""         ; last status line, to avoid pointless redraws
}

;=============================================================================
;  Start up
;=============================================================================
LoadSettings()
EnsureProfileFolder()
LoadProfiles()
BuildTray()
RegisterGlobal()
ApplyRoutes()
SetTimer(Watchdog, 300)
if App.FirstRun {
    msg := "Remap is running.`n`n"
    msg .= "Profiles in the profiles folder decide what gets remapped and where. "
    msg .= "The Hotline Miami one is on: press E in the game and it receives a "
    msg .= "right click, so you can throw without the trackpad.`n`n"
    msg .= "The window is opening now. " App.MenuHk " brings it back, "
    msg .= App.ToggleHk " switches everything on and off."
    MsgBox(msg, App.Name, "Iconi")
    ShowMain()
}

;=============================================================================
;  Settings file
;=============================================================================
LoadSettings() {
    f := App.IniFile
    if !FileExist(f) {
        App.FirstRun := true
        SaveSettings()
        return
    }
    App.Enabled  := IniRead(f, "Remap", "Enabled", "1") = "1"
    App.SendMode := IniRead(f, "Remap", "SendMode", "Input")
    App.Guard    := IniRead(f, "Remap", "ReleaseStuckKeys", "1") = "1"
    App.Toasts   := IniRead(f, "Remap", "Notifications", "1") = "1"
    App.ToggleHk := IniRead(f, "Remap", "ToggleHotkey", "F8")
    App.MenuHk   := IniRead(f, "Remap", "WindowHotkey", "F9")
}

SaveSettings() {
    f := App.IniFile
    IniWrite(App.Enabled ? 1 : 0, f, "Remap", "Enabled")
    IniWrite(App.SendMode,        f, "Remap", "SendMode")
    IniWrite(App.Guard   ? 1 : 0, f, "Remap", "ReleaseStuckKeys")
    IniWrite(App.Toasts  ? 1 : 0, f, "Remap", "Notifications")
    IniWrite(App.ToggleHk,        f, "Remap", "ToggleHotkey")
    IniWrite(App.MenuHk,          f, "Remap", "WindowHotkey")
}

;=============================================================================
;  Profiles
;=============================================================================
NewProfile(name := "New profile") {
    p := { File: "", Name: name }
    p.Desc    := ""
    p.Enabled := false
    p.Match   := []         ; empty means every program
    p.Keys    := []
    return p
}

NewBinding(from := "", to := "none") {
    b := { From: from, To: to }
    b.Mode     := "hold"    ; hold | tap | toggle | turbo
    b.Interval := 60        ; turbo speed, milliseconds
    b.Pass     := false     ; also send the key you pressed
    b.Enabled  := true
    b.Note     := ""
    b.Owner    := ""        ; the profile it belongs to
    b.Toggle   := false     ; runtime: toggle mode latched
    b.Timer    := ""        ; runtime: turbo timer
    return b
}

EnsureProfileFolder() {
    if DirExist(App.ProfileDir)
        return
    try {
        DirCreate(App.ProfileDir)
        for name, text in StarterProfiles()
            FileAppend(text, App.ProfileDir "\" name, "UTF-8-RAW")
    } catch as err {
        MsgBox("Could not create the profiles folder.`n`n" err.Message, App.Name, "Icon!")
    }
}

LoadProfiles() {
    App.Profiles := []
    names := ""
    try {
        loop files, App.ProfileDir "\*.ini"
            names .= A_LoopFileName "`n"
    }
    names := Trim(names, "`n")
    if (names = "")
        return
    for name in StrSplit(Sort(names), "`n") {
        if (Trim(name) = "")
            continue
        p := ParseProfile(App.ProfileDir "\" name)
        if IsObject(p)
            App.Profiles.Push(p)
    }
}

ParseProfile(path) {
    text := ""
    try text := FileRead(path, "UTF-8")
    catch {
        return ""
    }

    p := NewProfile(RegExReplace(FileName(path), "\.ini$", ""))
    p.File  := path
    section := ""

    for line in StrSplit(text, "`n", "`r") {
        line := Trim(line)
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue
        if (SubStr(line, 1, 1) = "[") {
            section := StrLower(Trim(line, "[]" . " "))
            continue
        }
        eq := InStr(line, "=")
        if (eq = 0)
            continue

        key  := Trim(SubStr(line, 1, eq - 1))
        rest := Trim(SubStr(line, eq + 1))
        note := ""
        semi := InStr(rest, ";")
        if (semi > 0) {
            note := Trim(SubStr(rest, semi + 1))
            rest := Trim(SubStr(rest, 1, semi - 1))
        }

        if (section = "profile") {
            switch StrLower(key) {
                case "name":
                    if (rest != "")
                        p.Name := rest
                case "description", "desc":
                    p.Desc := rest
                case "enabled", "on":
                    p.Enabled := IsYes(rest)
                case "match", "programs", "processes", "apps":
                    p.Match := SplitCsv(rest)
            }
            continue
        }
        if (section = "keys") {
            b := ParseBinding(key, rest, note)
            if IsObject(b) {
                b.Owner := p
                p.Keys.Push(b)
            }
        }
    }
    return p
}

; "RButton, turbo 60, pass, off" -> a binding
ParseBinding(from, value, note) {
    if (Trim(from) = "")
        return ""
    parts := StrSplit(value, ",")
    b := NewBinding(Trim(from), Trim(parts.Has(1) ? parts[1] : "none"))
    b.Note := note
    if (b.To = "")
        b.To := "none"

    i := 2
    while (i <= parts.Length) {
        opt := StrLower(Trim(parts[i]))
        i += 1
        if (opt = "")
            continue
        if (SubStr(opt, 1, 5) = "turbo") {
            b.Mode := "turbo"
            ms := Trim(SubStr(opt, 6))
            if (ms != "") {
                try b.Interval := Max(10, Integer(ms))
            }
            continue
        }
        switch opt {
            case "hold", "tap", "toggle": b.Mode := opt
            case "pass", "passthrough":   b.Pass := true
            case "block", "cancel":       b.Pass := false
            case "off", "disabled":       b.Enabled := false
            case "on", "enabled":         b.Enabled := true
        }
    }
    return b
}

SaveProfile(p) {
    if (p.File = "")
        p.File := App.ProfileDir "\" SafeFileName(p.Name) ".ini"

    width := 4
    for b in p.Keys
        width := Max(width, StrLen(b.From))

    out := "; " p.Name "`r`n"
    if (p.Desc != "")
        out .= "; " p.Desc "`r`n"
    out .= "; Written by Remap. Anything after a semicolon is a note.`r`n`r`n"
    out .= "[profile]`r`n"
    out .= "name        = " p.Name "`r`n"
    out .= "description = " p.Desc "`r`n"
    out .= "enabled     = " (p.Enabled ? "yes" : "no") "`r`n"
    out .= "match       = " JoinList(p.Match, ", ") "`r`n`r`n"
    out .= "[keys]`r`n"

    for b in p.Keys {
        if (Trim(b.From) = "")
            continue
        line := Pad(b.From, width) " = " b.To
        if (b.Mode = "turbo")
            line .= ", turbo " b.Interval
        else if (b.Mode != "hold")
            line .= ", " b.Mode
        if b.Pass
            line .= ", pass"
        if !b.Enabled
            line .= ", off"
        if (b.Note != "")
            line .= "   ; " b.Note
        out .= line "`r`n"
    }

    try {
        if FileExist(p.File)
            FileDelete(p.File)
        FileAppend(out, p.File, "UTF-8-RAW")
        return true
    } catch as err {
        MsgBox("Could not save '" p.Name "'.`n`n" err.Message, App.Name, "Icon!")
        return false
    }
}

SaveAll() {
    for p in App.Profiles
        SaveProfile(p)
}

;=============================================================================
;  Routing: which binding wins for a given key, right now
;=============================================================================
BuildRoutes() {
    App.Routes := Map()
    ordered := []
    ; A profile aimed at particular programs beats a global one.
    for p in App.Profiles {
        if (p.Enabled && p.Match.Length > 0)
            ordered.Push(p)
    }
    for p in App.Profiles {
        if (p.Enabled && p.Match.Length = 0)
            ordered.Push(p)
    }
    for p in ordered {
        for b in p.Keys {
            if (!b.Enabled || Trim(b.From) = "")
                continue
            k := StrLower(b.From)
            if !App.Routes.Has(k)
                App.Routes[k] := []
            App.Routes[k].Push(b)
        }
    }
}

WindowMatches(p) {
    if (p.Match.Length = 0)
        return true
    for pat in p.Match {
        pat := Trim(pat)
        if (pat = "")
            continue
        if (SubStr(pat, 1, 4) = "ahk_") {
            if WinActive(pat)
                return true
        } else if (StrLower(SubStr(pat, -4)) = ".exe") {
            if WinActive("ahk_exe " pat)
                return true
        } else if WinActive(pat) {
            return true
        }
    }
    return false
}

BindingApplies(b) {
    if !App.Enabled
        return false
    if !IsObject(b.Owner)
        return false
    if !b.Owner.Enabled
        return false
    return WindowMatches(b.Owner)
}

Resolve(key) {
    k := StrLower(key)
    if !App.Routes.Has(k)
        return ""
    for b in App.Routes[k] {
        if BindingApplies(b)
            return b
    }
    return ""
}

; The hotkey context: false means the key is left completely alone.
RouteContext(hk) {
    if !App.HkKey.Has(hk)
        return false
    return IsObject(Resolve(App.HkKey[hk]))
}

ApplyRoutes() {
    UnregisterAll()
    BuildRoutes()
    problems := ""

    HotIf(RouteContext)
    for key, list in App.Routes {
        name := "$*" key
        try {
            Hotkey(name, OnKeyDown.Bind(key), "On")
            App.Reg.Push(name)
            App.HkKey[name] := key
        } catch as err {
            problems .= "`n  " key "  (" err.Message ")"
            continue
        }
        if IsOneShot(key)
            continue
        try {
            Hotkey(name " up", OnKeyUp.Bind(key), "On")
            App.Reg.Push(name " up")
            App.HkKey[name " up"] := key
        }
    }
    HotIf()

    UpdateTray()
    if (problems != "")
        MsgBox("These keys could not be registered and were skipped:" problems, App.Name, "Icon!")
}

UnregisterAll() {
    HotIf(RouteContext)
    for name in App.Reg
        try Hotkey(name, , "Off")
    HotIf()
    App.Reg := []
    App.HkKey := Map()
    ReleaseAll()
}

RegisterGlobal() {
    HotIf()
    for name in App.GlobalReg
        try Hotkey(name, , "Off")
    App.GlobalReg := []

    if (Trim(App.ToggleHk) != "") {
        try {
            Hotkey(App.ToggleHk, (*) => ToggleEnabled(), "On")
            App.GlobalReg.Push(App.ToggleHk)
        } catch {
            MsgBox("'" App.ToggleHk "' is not a hotkey AutoHotkey understands, so the on / off hotkey is unset.", App.Name, "Icon!")
        }
    }
    if (Trim(App.MenuHk) != "") {
        try {
            Hotkey(App.MenuHk, (*) => ShowMain(), "On")
            App.GlobalReg.Push(App.MenuHk)
        } catch {
            MsgBox("'" App.MenuHk "' is not a hotkey AutoHotkey understands, so the window hotkey is unset.", App.Name, "Icon!")
        }
    }
}

;=============================================================================
;  What happens when a mapped key is pressed
;=============================================================================
; A wheel notch has no release event, so it can never be "held".
IsOneShot(key) {
    static wheels := "|wheelup|wheeldown|wheelleft|wheelright|"
    return InStr(wheels, "|" StrLower(Trim(key)) "|") > 0
}

OnKeyDown(key, *) {
    k := StrLower(key)
    if App.Down.Has(k)              ; Windows repeats key down while it is held
        return
    b := Resolve(k)
    if !IsObject(b)
        return

    if IsOneShot(k) {
        if b.Pass
            SendTap(b.From)
        SendTap(b.To)
        return
    }

    App.Down[k] := b
    if b.Pass
        SendKeyState(b.From, "down")

    switch b.Mode {
        case "tap":
            SendTap(b.To)
        case "toggle":
            if b.Toggle {
                b.Toggle := false
                TargetUp(b.To)
            } else {
                b.Toggle := true
                TargetDown(b.To)
            }
        case "turbo":
            StartTurbo(b)
        default:
            TargetDown(b.To)
    }
}

OnKeyUp(key, *) {
    ReleaseSource(StrLower(key))
}

ReleaseSource(k) {
    if !App.Down.Has(k)
        return
    b := App.Down[k]
    App.Down.Delete(k)
    if b.Pass
        SendKeyState(b.From, "up")

    switch b.Mode {
        case "tap", "toggle":
            return                  ; these two carry on after the key is let go
        case "turbo":
            StopTurbo(b)
        default:
            TargetUp(b.To)
    }
}

ReleaseAll() {
    for k in MapKeys(App.Down)
        ReleaseSource(k)
    for t in MapKeys(App.Held)
        SendKeyState(t, "up")
    App.Held.Clear()
    App.Down.Clear()
    for p in App.Profiles {
        for b in p.Keys {
            StopTurbo(b)
            b.Toggle := false
        }
    }
}

; Catches anything that could leave a key stuck: tabbing away mid press,
; a program closing while you hold a key, a release event going missing.
Watchdog() {
    if (App.Guard && App.Down.Count > 0) {
        for k in MapKeys(App.Down) {
            if !App.Down.Has(k)
                continue
            stillHeld := true
            try stillHeld := GetKeyState(k, "P")
            if (!stillHeld || !BindingApplies(App.Down[k]))
                ReleaseSource(k)
        }
    }
    UpdateTray()
}

ToggleEnabled(*) {
    App.Enabled := !App.Enabled
    if !App.Enabled
        ReleaseAll()
    UpdateTray()
    Toast(App.Enabled ? "Remapping on" : "Remapping off")
    if IsObject(App.Win)
        try App.Win["Master"].Value := App.Enabled ? 1 : 0
    try IniWrite(App.Enabled ? 1 : 0, App.IniFile, "Remap", "Enabled")
}

;=============================================================================
;  Sending keys
;=============================================================================
IsNone(key) {
    return (Trim(key) = "" || StrLower(Trim(key)) = "none")
}

; {Blind} leaves the modifiers you are really holding alone.
; SendPlay does not take it, so that mode gets the bare key.
SendRaw(keys) {
    switch StrLower(App.SendMode) {
        case "event": SendEvent("{Blind}" keys)
        case "play":  SendPlay(keys)
        default:      SendInput("{Blind}" keys)
    }
}

SendKeyState(key, state) {
    if IsNone(key)
        return
    SendRaw("{" Trim(key) " " state "}")
}

SendTap(key) {
    if IsNone(key)
        return
    SendRaw("{" Trim(key) "}")
}

; Two keys can point at the same target, so targets are counted: the target
; only comes back up once the last source has let go.
TargetDown(key) {
    if IsNone(key)
        return
    key := Trim(key)
    n := App.Held.Has(key) ? App.Held[key] : 0
    App.Held[key] := n + 1
    if (n = 0)
        SendKeyState(key, "down")
}

TargetUp(key) {
    if IsNone(key)
        return
    key := Trim(key)
    if !App.Held.Has(key)
        return
    n := App.Held[key] - 1
    if (n > 0) {
        App.Held[key] := n
        return
    }
    App.Held.Delete(key)
    SendKeyState(key, "up")
}

StartTurbo(b) {
    StopTurbo(b)
    b.Timer := () => SendTap(b.To)
    SendTap(b.To)
    SetTimer(b.Timer, Max(10, b.Interval))
}

StopTurbo(b) {
    if IsObject(b.Timer) {
        SetTimer(b.Timer, 0)
        b.Timer := ""
    }
}

;=============================================================================
;  Odds and ends
;=============================================================================
MapKeys(m) {
    out := []
    for k in m
        out.Push(k)
    return out
}

SplitCsv(text) {
    out := []
    for part in StrSplit(text, ",") {
        part := Trim(part)
        if (part != "")
            out.Push(part)
    }
    return out
}

JoinList(list, sep := ", ") {
    out := ""
    for item in list
        out .= (out = "" ? "" : sep) item
    return out
}

Pad(text, width) {
    while (StrLen(text) < width)
        text .= " "
    return text
}

IsYes(text) {
    text := StrLower(Trim(text))
    return (text = "1" || text = "yes" || text = "true" || text = "on")
}

FileName(path) {
    SplitPath(path, &name)
    return name
}

SafeFileName(name) {
    name := RegExReplace(Trim(name), "[\\/:*?""<>|]", "-")
    name := RegExReplace(name, "\s+", "-")
    return (name = "") ? "profile" : StrLower(name)
}

CleanText(text) {
    text := StrReplace(text, ";", ",")
    text := StrReplace(text, "`r", " ")
    text := StrReplace(text, "`n", " ")
    return Trim(text)
}

ValidKey(key) {
    key := Trim(key)
    if (key = "")
        return false
    if IsNone(key)
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
        "lbutton", "left mouse", "rbutton", "right mouse", "mbutton", "middle mouse",
        "xbutton1", "mouse 4", "xbutton2", "mouse 5",
        "wheelup", "wheel up", "wheeldown", "wheel down")
    key := Trim(key)
    if IsNone(key)
        return "nothing, the key is swallowed"
    k := StrLower(key)
    return names.Has(k) ? key " (" names[k] ")" : key
}

ModeLabel(b) {
    switch b.Mode {
        case "tap":    return "tap"
        case "toggle": return "toggle"
        case "turbo":  return "turbo " b.Interval "ms"
        default:       return "hold"
    }
}

ScopeLabel(p) {
    return (p.Match.Length = 0) ? "every program" : JoinList(p.Match, ", ")
}

FindProfile(name) {
    for p in App.Profiles {
        if (p.Name = name)
            return p
    }
    return ""
}

ActiveProfileNames() {
    out := ""
    for p in App.Profiles {
        if (p.Enabled && WindowMatches(p))
            out .= (out = "" ? "" : ", ") p.Name
    }
    return out
}

StartupLink() {
    return A_Startup "\Remap.lnk"
}

ApplyAndSave() {
    SaveAll()
    ApplyRoutes()
}

;=============================================================================
;  Tray
;=============================================================================
BuildTray() {
    tray := A_TrayMenu
    tray.Delete()
    tray.Add("Open Remap", (*) => ShowMain())
    tray.Add("Remapping enabled", (*) => ToggleEnabled())
    tray.Add()
    tray.Add("Profiles folder", (*) => OpenProfileFolder())
    tray.Add("Reload profiles", (*) => ReloadFromDisk())
    tray.Add()
    tray.Add("Exit", (*) => ExitApp())
    tray.Default := "Open Remap"
    tray.ClickCount := 1
    UpdateTray()
}

UpdateTray() {
    if !App.Enabled
        line := "off"
    else {
        names := ActiveProfileNames()
        line := (names = "") ? "waiting" : "active: " names
    }
    if (line = App.Status)
        return
    App.Status := line

    A_IconTip := App.Name "`n" line
    try {
        if App.Enabled
            A_TrayMenu.Check("Remapping enabled")
        else
            A_TrayMenu.Uncheck("Remapping enabled")
    }
    try TraySetIcon(A_AhkPath, App.Enabled ? 1 : 2, true)
    if IsObject(App.Win)
        try App.Win["Status"].Text := "Status: " line
}

OpenProfileFolder() {
    EnsureProfileFolder()
    try Run('explorer.exe "' App.ProfileDir '"')
}

ReloadFromDisk() {
    UnregisterAll()
    LoadProfiles()
    ApplyRoutes()
    Toast("Profiles reloaded")
    if IsObject(App.Win) {
        try App.Win.Destroy()
        App.Win := ""
        ShowMain()
    }
}

Toast(text, ms := 1200) {
    if !App.Toasts
        return
    ToolTip(text)
    SetTimer(() => ToolTip(), -ms)
}

;=============================================================================
;  Main window
;=============================================================================
ShowMain(*) {
    if IsObject(App.Win) {
        try {
            App.Win.Show()
            WinActivate("ahk_id " App.Win.Hwnd)
            return
        }
        App.Win := ""
    }

    busy := false               ; stops our own list updates looking like clicks

    g := Gui("-MaximizeBox", App.Name " " App.Ver)
    App.Win := g
    g.MarginX := 14
    g.MarginY := 12
    g.SetFont("s11 Bold", "Segoe UI")
    g.AddText("xm ym w300 h26 +0x200", App.Name)
    g.SetFont("s9 Norm", "Segoe UI")
    master := g.AddCheckbox("x670 yp+4 w220 h22 vMaster", "Remapping enabled (" App.ToggleHk ")")
    master.Value := App.Enabled ? 1 : 0
    master.OnEvent("Click", MasterClick)

    g.SetFont("s9 Bold", "Segoe UI")
    g.AddText("xm y+8 w330 h20", "Profiles")
    g.AddText("x358 yp w540 h20 vKeysTitle", "Keys")
    g.SetFont("s9 Norm", "Segoe UI")

    plv := g.AddListView("xm y+4 w330 r14 Checked -Multi vProfiles", ["Profile", "Where"])
    plv.OnEvent("ItemCheck", ProfileChecked)
    plv.OnEvent("ItemSelect", ProfileSelected)
    plv.OnEvent("DoubleClick", (*) => ProfileDetails())

    klv := g.AddListView("x358 yp w540 r14 -Multi vKeys",
        ["When I press", "The app receives", "Mode", "Note"])
    klv.OnEvent("DoubleClick", (*) => EditKey())

    g.AddButton("xm y+8 w78 h27", "New").OnEvent("Click", (*) => AddProfile())
    g.AddButton("x+6 yp w78 h27", "Copy").OnEvent("Click", (*) => CopyProfile())
    g.AddButton("x+6 yp w78 h27", "Delete").OnEvent("Click", (*) => DeleteProfile())
    g.AddButton("x+6 yp w78 h27", "Reload").OnEvent("Click", (*) => ReloadFromDisk())

    g.AddButton("x358 yp w86 h27", "Add key").OnEvent("Click", (*) => AddKey())
    g.AddButton("x+6 yp w86 h27", "Edit").OnEvent("Click", (*) => EditKey())
    g.AddButton("x+6 yp w86 h27", "Remove").OnEvent("Click", (*) => RemoveKey())
    g.AddButton("x+6 yp w86 h27", "On / off").OnEvent("Click", (*) => ToggleKey())

    g.AddText("xm y+14 w110 h24 +0x200", "Applies to:")
    g.AddText("x+4 yp w560 h24 +0x200 vScope", "")
    g.AddButton("x+6 yp-2 w160 h28", "Choose programs").OnEvent("Click", (*) => ChooseScope())

    g.AddText("xm y+10 w884 h20 vHint cGray", "")

    g.AddButton("xm y+12 w110 h30", "Options").OnEvent("Click", (*) => ShowOptions(g))
    g.AddButton("x+8 yp w90 h30", "Help").OnEvent("Click", (*) => ShowHelp(g))
    g.AddButton("x+8 yp w90 h30 Default", "Close").OnEvent("Click", (*) => CloseMain())
    g.AddText("x+16 yp+8 w540 h20 vStatus cGray", "")

    g.OnEvent("Close",  (*) => CloseMain())
    g.OnEvent("Escape", (*) => CloseMain())

    RefreshProfiles(1)
    App.Status := ""            ; force the status line to redraw
    UpdateTray()
    g.Show()
    return

    ;--------------------------------------------------------------------
    RefreshProfiles(select := 0) {
        busy := true
        row := (select > 0) ? select : plv.GetNext()
        plv.Opt("-Redraw")
        plv.Delete()
        for p in App.Profiles
            plv.Add(p.Enabled ? "Check" : "", p.Name, ScopeLabel(p))
        plv.Opt("+Redraw")
        plv.ModifyCol(1, 150)
        plv.ModifyCol(2, 150)
        if (App.Profiles.Length > 0) {
            if (row < 1 || row > App.Profiles.Length)
                row := 1
            plv.Modify(row, "Select Focus")
        }
        busy := false
        RefreshKeys()
    }

    Current() {
        row := plv.GetNext()
        if (row < 1 || row > App.Profiles.Length)
            return ""
        return App.Profiles[row]
    }

    RefreshKeys() {
        p := Current()
        klv.Opt("-Redraw")
        klv.Delete()
        if IsObject(p) {
            g["KeysTitle"].Text := "Keys in " p.Name
            g["Scope"].Text := ScopeLabel(p)
            for b in p.Keys
                klv.Add("", PrettyKey(b.From), PrettyKey(b.To), b.Enabled ? ModeLabel(b) : "off", NoteFor(b, p))
        } else {
            g["KeysTitle"].Text := "Keys"
            g["Scope"].Text := "no profile selected"
        }
        klv.Opt("+Redraw")
        klv.ModifyCol(1, 140)
        klv.ModifyCol(2, 170)
        klv.ModifyCol(3, 80)
        klv.ModifyCol(4, 130)
        g["Hint"].Text := HintFor(p)
    }

    ; Flags a key that a higher priority profile has already claimed.
    NoteFor(b, p) {
        note := b.Note
        if (!b.Enabled || !p.Enabled)
            return note
        k := StrLower(b.From)
        if !App.Routes.Has(k)
            return note
        top := App.Routes[k][1]
        if (ObjPtr(top) = ObjPtr(b))
            return note
        tag := "beaten by " top.Owner.Name
        return (note = "") ? tag : tag ", " note
    }

    HintFor(p) {
        if !IsObject(p)
            return "Add a profile to get started."
        if !p.Enabled
            return "This profile is off. Tick it in the list to switch it on."
        if (p.Match.Length = 0)
            return "Works in every program. Choose programs to narrow it down."
        return "Only works while one of these is the window you are tabbed into: " ScopeLabel(p)
    }

    ;--------------------------------------------------------------------
    MasterClick(ctrl, *) {
        if ((ctrl.Value ? true : false) != App.Enabled)
            ToggleEnabled()
    }

    ProfileChecked(ctrl, item, checked) {
        if busy
            return
        if (item < 1 || item > App.Profiles.Length)
            return
        p := App.Profiles[item]
        p.Enabled := checked ? true : false
        SaveProfile(p)
        ApplyRoutes()
        RefreshKeys()
        Toast(p.Name . (p.Enabled ? " on" : " off"))
    }

    ProfileSelected(ctrl, item, selected) {
        if (busy || !selected)
            return
        RefreshKeys()
    }

    ;--------------------------------------------------------------------
    AddProfile() {
        answer := InputBox("Name for the new profile:", App.Name, "w340 h140")
        if (answer.Result != "OK")
            return
        name := CleanText(answer.Value)
        if (name = "")
            return
        p := NewProfile(name)
        p.Desc := "Made in " App.Name "."
        if !SaveProfile(p)
            return
        App.Profiles.Push(p)
        RefreshProfiles(App.Profiles.Length)
        ApplyRoutes()
    }

    CopyProfile() {
        p := Current()
        if !IsObject(p)
            return
        answer := InputBox("Name for the copy of '" p.Name "':", App.Name, "w340 h140")
        if (answer.Result != "OK")
            return
        name := CleanText(answer.Value)
        if (name = "")
            return
        copy := NewProfile(name)
        copy.Desc    := p.Desc
        copy.Enabled := false
        for m in p.Match
            copy.Match.Push(m)
        for b in p.Keys {
            nb := NewBinding(b.From, b.To)
            nb.Mode     := b.Mode
            nb.Interval := b.Interval
            nb.Pass     := b.Pass
            nb.Enabled  := b.Enabled
            nb.Note     := b.Note
            nb.Owner    := copy
            copy.Keys.Push(nb)
        }
        if !SaveProfile(copy)
            return
        App.Profiles.Push(copy)
        RefreshProfiles(App.Profiles.Length)
        ApplyRoutes()
    }

    DeleteProfile() {
        p := Current()
        if !IsObject(p)
            return
        if (MsgBox("Delete the profile '" p.Name "'?`n`nIts file is deleted too.", App.Name, "YesNo Icon? Owner" g.Hwnd) != "Yes")
            return
        row := plv.GetNext()
        try {
            if (p.File != "" && FileExist(p.File))
                FileDelete(p.File)
        } catch as err {
            MsgBox("Could not delete the file.`n`n" err.Message, App.Name, "Icon! Owner" g.Hwnd)
            return
        }
        App.Profiles.RemoveAt(row)
        RefreshProfiles(Min(row, App.Profiles.Length))
        ApplyRoutes()
    }

    ProfileDetails() {
        p := Current()
        if !IsObject(p)
            return
        was := p.Name
        if !EditProfile(g, p)
            return
        if (p.Name != was) {        ; keep the file name in step with the profile
            old := p.File
            p.File := ""
            if (SaveProfile(p) && old != "" && old != p.File)
                try FileDelete(old)
        } else {
            SaveProfile(p)
        }
        ApplyRoutes()
        RefreshProfiles(plv.GetNext())
    }

    ChooseScope() {
        p := Current()
        if !IsObject(p)
            return
        picked := ChoosePrograms(g, p.Match)
        if !IsObject(picked)
            return
        p.Match := picked
        SaveProfile(p)
        ApplyRoutes()
        RefreshProfiles(plv.GetNext())
    }

    ;--------------------------------------------------------------------
    SelectedKey() {
        p := Current()
        if !IsObject(p)
            return 0
        row := klv.GetNext()
        if (row < 1 || row > p.Keys.Length) {
            MsgBox("Pick a key in the list on the right first.", App.Name, "Iconi Owner" g.Hwnd)
            return 0
        }
        return row
    }

    AddKey() {
        p := Current()
        if !IsObject(p) {
            MsgBox("Pick a profile on the left first.", App.Name, "Iconi Owner" g.Hwnd)
            return
        }
        b := NewBinding()
        b.Owner := p
        if EditBinding(g, b) {
            p.Keys.Push(b)
            SaveProfile(p)
            ApplyRoutes()
            RefreshKeys()
            klv.Modify(p.Keys.Length, "Select Focus")
        }
    }

    EditKey() {
        row := SelectedKey()
        if (row = 0)
            return
        p := Current()
        if EditBinding(g, p.Keys[row]) {
            SaveProfile(p)
            ApplyRoutes()
            RefreshKeys()
            klv.Modify(row, "Select Focus")
        }
    }

    RemoveKey() {
        row := SelectedKey()
        if (row = 0)
            return
        p := Current()
        b := p.Keys[row]
        if (MsgBox("Remove " PrettyKey(b.From) " from '" p.Name "'?", App.Name, "YesNo Icon? Owner" g.Hwnd) != "Yes")
            return
        p.Keys.RemoveAt(row)
        SaveProfile(p)
        ApplyRoutes()
        RefreshKeys()
    }

    ToggleKey() {
        row := SelectedKey()
        if (row = 0)
            return
        p := Current()
        p.Keys[row].Enabled := !p.Keys[row].Enabled
        SaveProfile(p)
        ApplyRoutes()
        RefreshKeys()
        klv.Modify(row, "Select Focus")
    }

    CloseMain() {
        try g.Destroy()
        App.Win := ""
    }
}

;=============================================================================
;  Profile details
;=============================================================================
EditProfile(owner, p) {
    done := 0

    d := Gui("-MaximizeBox -MinimizeBox +Owner" owner.Hwnd, "Profile")
    d.SetFont("s9", "Segoe UI")
    d.MarginX := 14
    d.MarginY := 12
    owner.Opt("+Disabled")

    d.AddText("xm ym+4 w110 h22 +0x200", "Name:")
    eName := d.AddEdit("x+6 yp w330 h22", p.Name)

    d.AddText("xm y+10 w110 h22 +0x200", "Description:")
    eDesc := d.AddEdit("x+6 yp w330 h22", p.Desc)

    d.AddText("xm y+10 w110 h22 +0x200", "Programs:")
    ePrograms := d.AddEdit("x+6 yp w330 h22", JoinList(p.Match, ", "))
    d.AddButton("xm y+8 w160 h26", "Choose programs").OnEvent("Click", Choose)
    d.AddText("x+10 yp+4 w280 cGray", "Blank means every program.")

    cEn := d.AddCheckbox("xm y+14", "Profile is on")
    cEn.Value := p.Enabled ? 1 : 0

    d.AddButton("xm y+16 w120 h30 Default", "OK").OnEvent("Click", OkClick)
    d.AddButton("x+8 yp w120 h30", "Cancel").OnEvent("Click", (*) => Finish(2))
    d.OnEvent("Close",  (*) => Finish(2))
    d.OnEvent("Escape", (*) => Finish(2))
    d.Show()

    while (done = 0)
        Sleep(40)

    owner.Opt("-Disabled")
    try WinActivate("ahk_id " owner.Hwnd)
    try d.Destroy()
    return (done = 1)

    Choose(*) {
        picked := ChoosePrograms(d, SplitCsv(ePrograms.Value))
        if IsObject(picked)
            ePrograms.Value := JoinList(picked, ", ")
    }

    OkClick(*) {
        name := CleanText(eName.Value)
        if (name = "") {
            MsgBox("A profile needs a name.", App.Name, "Icon! Owner" d.Hwnd)
            return
        }
        p.Name    := name
        p.Desc    := CleanText(eDesc.Value)
        p.Match   := SplitCsv(ePrograms.Value)
        p.Enabled := cEn.Value ? true : false
        Finish(1)
    }

    Finish(code) {
        done := code
    }
}

;=============================================================================
;  Program picker
;=============================================================================
; Takes the list a profile has now, gives back a new list, or "" on cancel.
ChoosePrograms(owner, current) {
    done   := 0
    busy   := false
    listed := Map()

    d := Gui("-MaximizeBox -MinimizeBox +Owner" owner.Hwnd, "Choose programs")
    d.SetFont("s9", "Segoe UI")
    d.MarginX := 14
    d.MarginY := 12
    owner.Opt("+Disabled")

    d.AddText("xm ym w560 cGray", "Tick the programs this profile should work in. Leave the box empty for every program.")
    lv := d.AddListView("xm y+8 w560 r14 Checked -Multi", ["Program", "A window it has open"])
    lv.OnEvent("ItemCheck", (*) => SyncText())

    d.AddText("xm y+10 w110 h22 +0x200", "Programs:")
    ed := d.AddEdit("x+6 yp w444 h22", JoinList(current, ", "))

    d.AddButton("xm y+10 w150 h27", "Pick a window").OnEvent("Click", Pick)
    d.AddButton("x+6 yp w110 h27", "Refresh").OnEvent("Click", (*) => Fill())
    d.AddButton("x+6 yp w110 h27", "Everywhere").OnEvent("Click", (*) => Everywhere())
    d.AddButton("x368 y+10 w100 h27 Default", "OK").OnEvent("Click", (*) => Finish(1))
    d.AddButton("x+6 yp w100 h27", "Cancel").OnEvent("Click", (*) => Finish(2))
    d.OnEvent("Close",  (*) => Finish(2))
    d.OnEvent("Escape", (*) => Finish(2))

    Fill()
    d.Show()

    while (done = 0)
        Sleep(40)

    result := (done = 1) ? SplitCsv(ed.Value) : ""
    owner.Opt("-Disabled")
    try WinActivate("ahk_id " owner.Hwnd)
    try d.Destroy()
    return result

    ; Every program that has a visible window right now, one row each.
    Fill() {
        busy  := true
        seen  := Map()
        rows  := []
        own   := ""
        try own := WinGetProcessName("ahk_id " A_ScriptHwnd)
        for hwnd in WinGetList() {
            title := ""
            exe   := ""
            try title := WinGetTitle("ahk_id " hwnd)
            try exe   := WinGetProcessName("ahk_id " hwnd)
            if (exe = "" || title = "" || exe = own)
                continue
            k := StrLower(exe)
            if seen.Has(k)
                continue
            seen[k] := true
            rows.Push([exe, title])
        }
        listed := seen

        wanted := Map()
        for item in SplitCsv(ed.Value)
            wanted[StrLower(item)] := true

        lv.Opt("-Redraw")
        lv.Delete()
        for row in rows
            lv.Add(wanted.Has(StrLower(row[1])) ? "Check" : "", row[1], row[2])
        lv.Opt("+Redraw")
        lv.ModifyCol(1, 180)
        lv.ModifyCol(2, 340)
        busy := false
    }

    ; Ticks drive the text box, and anything typed by hand is kept.
    SyncText() {
        if busy
            return
        manual := []
        for item in SplitCsv(ed.Value) {
            if !listed.Has(StrLower(item))
                manual.Push(item)
        }
        out := []
        row := 0
        loop {
            row := lv.GetNext(row, "Checked")
            if (row = 0)
                break
            out.Push(lv.GetText(row, 1))
        }
        for item in manual
            out.Push(item)
        ed.Value := JoinList(out, ", ")
    }

    Everywhere(*) {
        ed.Value := ""
        Fill()
    }

    Pick(*) {
        exe := PickWindow(d)
        if (exe = "")
            return
        items := SplitCsv(ed.Value)
        for item in items {
            if (StrLower(item) = StrLower(exe))
                return
        }
        items.Push(exe)
        ed.Value := JoinList(items, ", ")
        Fill()
    }

    Finish(code) {
        done := code
    }
}

; Click a window to find out what program it belongs to.
PickWindow(owner) {
    picked := ""
    done   := false

    tip := Gui("+AlwaysOnTop +ToolWindow -MinimizeBox -MaximizeBox +Owner" owner.Hwnd, "Pick a window")
    tip.SetFont("s10", "Segoe UI")
    tip.AddText("w320 Center", "Click the window you want to target.`n`nEsc cancels.")
    tip.Show("AutoSize")

    HotIf()
    try Hotkey("*LButton", OnPick, "On")
    try Hotkey("*Escape", OnStop, "On")

    while !done
        Sleep(30)

    try Hotkey("*LButton", OnPick, "Off")
    try Hotkey("*Escape", OnStop, "Off")
    try tip.Destroy()
    try WinActivate("ahk_id " owner.Hwnd)

    own := ""
    try own := WinGetProcessName("ahk_id " A_ScriptHwnd)
    if (picked != "" && StrLower(picked) = StrLower(own))
        picked := ""
    return picked

    OnPick(*) {
        hwnd := 0
        MouseGetPos( , , &hwnd)
        try picked := WinGetProcessName("ahk_id " hwnd)
        done := true
    }

    OnStop(*) {
        done := true
    }
}

;=============================================================================
;  One remap
;=============================================================================
EditBinding(owner, b) {
    done := 0

    d := Gui("-MaximizeBox -MinimizeBox +Owner" owner.Hwnd, "Remap")
    d.SetFont("s9", "Segoe UI")
    d.MarginX := 14
    d.MarginY := 12
    owner.Opt("+Disabled")

    d.AddText("xm ym+4 w120 h22 +0x200", "When I press:")
    eFrom := d.AddEdit("x+6 yp w150 h22", b.From)
    d.AddButton("x+6 yp-1 w90 h24", "Capture").OnEvent("Click", CapFrom)

    d.AddText("xm y+10 w120 h22 +0x200", "The app receives:")
    eTo := d.AddEdit("x+6 yp w150 h22", b.To)
    d.AddButton("x+6 yp-1 w90 h24", "Capture").OnEvent("Click", CapTo)
    d.AddText("xm y+6 w380 cGray", "RButton is right click, LButton is left click, none swallows the key.")

    d.AddText("xm y+12 w120 h22 +0x200", "Mode:")
    ddMode := d.AddDropDownList("x+6 yp-2 w150", ["hold", "tap", "toggle", "turbo"])
    ddMode.Choose(b.Mode)
    d.AddText("x+12 yp+4 w70 h22 +0x200", "Turbo ms:")
    eInt := d.AddEdit("x+4 yp-2 w60 h22 Number", b.Interval)

    d.AddText("xm y+12 w120 h22 +0x200", "Note:")
    eNote := d.AddEdit("x+6 yp w300 h22", b.Note)

    cEn := d.AddCheckbox("xm y+14 w160", "This remap is on")
    cEn.Value := b.Enabled ? 1 : 0
    cPass := d.AddCheckbox("x+10 yp w260", "Also send the key I pressed")
    cPass.Value := b.Pass ? 1 : 0
    d.AddText("xm y+6 w420 cGray", "Leave that unticked and the key you press is cancelled, so the program never sees it.")

    d.AddButton("xm y+16 w120 h30 Default", "OK").OnEvent("Click", OkClick)
    d.AddButton("x+8 yp w120 h30", "Cancel").OnEvent("Click", (*) => Finish(2))
    d.OnEvent("Close",  (*) => Finish(2))
    d.OnEvent("Escape", (*) => Finish(2))
    d.Show()

    while (done = 0)
        Sleep(40)

    owner.Opt("-Disabled")
    try WinActivate("ahk_id " owner.Hwnd)
    try d.Destroy()
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
            to := "none"
        if !ValidKey(from) {
            MsgBox("'" from "' is not a key name AutoHotkey knows.`n`nUse Capture if you are not sure.", App.Name, "Icon! Owner" d.Hwnd)
            return
        }
        if !ValidKey(to) {
            MsgBox("'" to "' is not a key name AutoHotkey knows.`n`nUse Capture, or none to swallow the key.", App.Name, "Icon! Owner" d.Hwnd)
            return
        }
        interval := 60
        try interval := Integer(eInt.Value)

        b.From     := from
        b.To       := to
        b.Mode     := StrLower(ddMode.Text)
        b.Interval := Max(10, interval)
        b.Note     := CleanText(eNote.Value)
        b.Enabled  := cEn.Value ? true : false
        b.Pass     := cPass.Value ? true : false
        Finish(1)
    }

    Finish(code) {
        done := code
    }
}

;=============================================================================
;  Press a key
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
;  Options
;=============================================================================
ShowOptions(owner) {
    done := 0

    d := Gui("-MaximizeBox -MinimizeBox +Owner" owner.Hwnd, "Options")
    d.SetFont("s9", "Segoe UI")
    d.MarginX := 14
    d.MarginY := 12
    owner.Opt("+Disabled")

    d.AddText("xm ym+4 w130 h22 +0x200", "On / off hotkey:")
    eToggle := d.AddEdit("x+6 yp w110 h22", App.ToggleHk)
    d.AddText("x+16 yp w110 h22 +0x200", "Window hotkey:")
    eMenu := d.AddEdit("x+6 yp w110 h22", App.MenuHk)

    d.AddText("xm y+10 w130 h22 +0x200", "Send using:")
    ddSend := d.AddDropDownList("x+6 yp-2 w110", ["Input", "Event", "Play"])
    ddSend.Choose(App.SendMode)
    d.AddText("x+16 yp+4 w240 cGray", "Input is right for almost everything.")

    cGuard := d.AddCheckbox("xm y+14 w480", "Let go of keys that get stuck when you tab away")
    cGuard.Value := App.Guard ? 1 : 0
    cToast := d.AddCheckbox("xm y+8 w480", "Show small on screen messages")
    cToast.Value := App.Toasts ? 1 : 0

    btnStart := d.AddButton("xm y+14 w200 h28", StartupLabel())
    btnStart.OnEvent("Click", StartupClick)
    d.AddButton("x+8 yp w200 h28", "Open profiles folder").OnEvent("Click", (*) => OpenProfileFolder())

    d.AddText("xm y+14 w480 cGray", "Profiles: " App.ProfileDir)

    d.AddButton("xm y+14 w120 h30 Default", "OK").OnEvent("Click", OkClick)
    d.AddButton("x+8 yp w120 h30", "Cancel").OnEvent("Click", (*) => Finish(2))
    d.OnEvent("Close",  (*) => Finish(2))
    d.OnEvent("Escape", (*) => Finish(2))
    d.Show()

    while (done = 0)
        Sleep(40)

    owner.Opt("-Disabled")
    try WinActivate("ahk_id " owner.Hwnd)
    try d.Destroy()
    return

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
                FileCreateShortcut(target, link, A_ScriptDir, args, App.Name)
                Toast("Will start with Windows")
            }
        } catch as err {
            MsgBox("Could not change the startup shortcut.`n`n" err.Message, App.Name, "Icon! Owner" d.Hwnd)
        }
        ctrl.Text := StartupLabel()
    }

    OkClick(*) {
        App.SendMode := ddSend.Text
        App.Guard    := cGuard.Value ? true : false
        App.Toasts   := cToast.Value ? true : false

        newToggle := Trim(eToggle.Value)
        newMenu   := Trim(eMenu.Value)
        if (newToggle != App.ToggleHk || newMenu != App.MenuHk) {
            App.ToggleHk := newToggle
            App.MenuHk   := newMenu
            RegisterGlobal()
            try owner["Master"].Text := "Remapping enabled (" App.ToggleHk ")"
        }
        SaveSettings()
        Toast("Options saved")
        Finish(1)
    }

    Finish(code) {
        done := code
    }
}

;=============================================================================
;  Help
;=============================================================================
ShowHelp(owner := "") {
    lines := []
    lines.Push(App.Name " " App.Ver)
    lines.Push("")
    lines.Push("Profiles")
    lines.Push("  A profile is a file in the profiles folder holding a set of remaps")
    lines.Push("  and the programs they apply to. Tick a profile to switch it on.")
    lines.Push("  A profile with no programs listed works everywhere; one with")
    lines.Push("  programs only works while one of them is the window you are in.")
    lines.Push("  When two profiles claim the same key, the one aimed at the program")
    lines.Push("  you are in wins.")
    lines.Push("")
    lines.Push("Modes")
    lines.Push("  hold     the target is held for exactly as long as you hold the key.")
    lines.Push("  tap      one press, one click, however long you hold the key.")
    lines.Push("  toggle   press once to hold the target, press again to let go.")
    lines.Push("  turbo    repeats the target while you hold the key.")
    lines.Push("")
    lines.Push("Key names")
    lines.Push("  Mouse:    LButton, RButton, MButton, XButton1, XButton2,")
    lines.Push("            WheelUp, WheelDown")
    lines.Push("  Keyboard: a to z, 0 to 9, Space, Enter, Tab, Escape, Shift, Ctrl,")
    lines.Push("            Alt, CapsLock, Up, Down, Left, Right, F1 to F12,")
    lines.Push("            Numpad0 to Numpad9, LWin, RWin")
    lines.Push("  none      swallows the key, the program never sees it.")
    lines.Push("")
    lines.Push("Good to know")
    lines.Push("  The key you press is cancelled unless you tick 'also send the key")
    lines.Push("  I pressed', so E sending a right click does not also type an E.")
    lines.Push("  Capture records the next key or button you press.")
    lines.Push("  Editing a profile in the window rewrites its file, which drops")
    lines.Push("  hand written comment lines. Notes after a key survive.")
    lines.Push("  If a key ever feels stuck, press " App.ToggleHk " twice.")

    text := ""
    for line in lines
        text .= line "`n"

    if IsObject(owner)
        MsgBox(text, App.Name, "Iconi Owner" owner.Hwnd)
    else
        MsgBox(text, App.Name, "Iconi")
}

;=============================================================================
;  Starter profiles, written on first run when the folder does not exist yet.
;  They match the files shipped alongside this script.
;=============================================================================
StarterProfiles() {
    files := Map()

    t := ""
    t .= "; Arrow keys as WASD`r`n"
    t .= "; For games that only read WASD when you would rather use the arrows.`r`n"
    t .= "; Fill in ""match"" with the game so this does not follow you around.`r`n"
    t .= "`r`n"
    t .= "[profile]`r`n"
    t .= "name        = Arrow keys as WASD`r`n"
    t .= "description = The arrow keys move in games that only understand WASD.`r`n"
    t .= "enabled     = no`r`n"
    t .= "match       =`r`n"
    t .= "`r`n"
    t .= "[keys]`r`n"
    t .= "Up    = w`r`n"
    t .= "Left  = a`r`n"
    t .= "Down  = s`r`n"
    t .= "Right = d`r`n"
    t .= "`r`n"
    files["arrow-keys-as-wasd.ini"] := t

    t := ""
    t .= "; Caps Lock to Ctrl`r`n"
    t .= "; The classic. Caps Lock is a big key in a good spot and nobody shouts.`r`n"
    t .= "`r`n"
    t .= "[profile]`r`n"
    t .= "name        = Caps Lock to Ctrl`r`n"
    t .= "description = Caps Lock acts as Ctrl everywhere.`r`n"
    t .= "enabled     = no`r`n"
    t .= "match       =`r`n"
    t .= "`r`n"
    t .= "[keys]`r`n"
    t .= "CapsLock = Ctrl`r`n"
    t .= "`r`n"
    files["caps-lock-to-ctrl.ini"] := t

    t := ""
    t .= "; Hotline Miami`r`n"
    t .= "; Press E to throw or pick up, instead of right clicking the trackpad.`r`n"
    t .= "; Format: when I press = what the app receives, options   ; note`r`n"
    t .= "`r`n"
    t .= "[profile]`r`n"
    t .= "name        = Hotline Miami`r`n"
    t .= "description = Throw and pick up with E instead of right click.`r`n"
    t .= "enabled     = yes`r`n"
    t .= "match       = HotlineMiami.exe, HotlineMiami2.exe`r`n"
    t .= "`r`n"
    t .= "[keys]`r`n"
    t .= "e = RButton, block       ; throw / pick up, the game sees a right click`r`n"
    t .= "q = LButton, off         ; turn this on to attack with Q as well`r`n"
    t .= "f = MButton, off         ; middle click, unused by the game by default`r`n"
    t .= "`r`n"
    files["hotline-miami.ini"] := t

    t := ""
    t .= "; Laptop trackpad`r`n"
    t .= "; Mouse buttons from the keyboard, for trackpads that make them awkward.`r`n"
    t .= "; Works everywhere because ""match"" is blank. Narrow it to one program`r`n"
    t .= "; with the Choose programs button if you would rather it stayed local.`r`n"
    t .= "`r`n"
    t .= "[profile]`r`n"
    t .= "name        = Laptop trackpad`r`n"
    t .= "description = Right click and middle click from the keyboard.`r`n"
    t .= "enabled     = no`r`n"
    t .= "match       =`r`n"
    t .= "`r`n"
    t .= "[keys]`r`n"
    t .= "RAlt  = RButton          ; right click`r`n"
    t .= "RCtrl = MButton, off     ; middle click, for opening links in a new tab`r`n"
    t .= "`r`n"
    files["laptop-trackpad.ini"] := t

    t := ""
    t .= "; No Windows key`r`n"
    t .= "; Stops the Windows key from minimising a game mid fight.`r`n"
    t .= "; Fill in ""match"" with your game, or leave it blank to block it everywhere.`r`n"
    t .= "`r`n"
    t .= "[profile]`r`n"
    t .= "name        = No Windows key`r`n"
    t .= "description = Swallows the Windows key so nothing gets minimised.`r`n"
    t .= "enabled     = no`r`n"
    t .= "match       =`r`n"
    t .= "`r`n"
    t .= "[keys]`r`n"
    t .= "LWin = none              ; none = the key is swallowed, nothing is sent`r`n"
    t .= "RWin = none`r`n"
    t .= "`r`n"
    files["no-windows-key.ini"] := t

    return files
}
