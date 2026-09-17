# Remap

A small, general purpose key remapper for Windows, built on AutoHotkey v2.

Remaps live in **profiles**: plain text files, each one scoped to the programs
you choose. A profile only does anything while one of its programs is the
window you are tabbed into, so you can leave it running all day. Several
profiles can be on at once.

It ships with a profile that fixes the awkward bit of Hotline Miami on a
laptop:

```
press E  ->  the game receives a right click   (throw and pick up)
```

The `E` you press is cancelled, so the game never sees it. Only the right
click arrives.

## Quick start

1. Install [AutoHotkey v2](https://www.autohotkey.com/) (v2.0 or newer, not v1).
2. Download `Remap.ahk` and the `profiles` folder next to it.
3. Double click `Remap.ahk`. A tray icon appears.

**F9** opens the window, **F8** switches all remapping on and off. Both are
configurable. If you only grab `Remap.ahk`, it writes the starter profiles
itself the first time it runs.

## The window

| Pane | What it holds |
| --- | --- |
| Profiles | Every profile in the folder. Tick one to switch it on. Double click for its name, description and programs. |
| Keys | The remaps in the selected profile. Double click a row to edit it. |
| Applies to | The programs the selected profile is limited to. **Choose programs** lists what is running, or lets you click the window you mean. |

**Choose programs** is the answer to "only while I am tabbed into this". Tick
the programs, or hit *Pick a window* and click the game. Leave it empty and the
profile works everywhere.

Editing anything writes it straight back to the profile file, so there is no
save button to forget.

## Profiles that come with it

| File | What it does | On by default |
| --- | --- | --- |
| `hotline-miami.ini` | E throws and picks up, for trackpads. Scoped to `HotlineMiami.exe` and `HotlineMiami2.exe`. | **yes** |
| `laptop-trackpad.ini` | Right Alt right clicks, Right Ctrl middle clicks, everywhere. | no |
| `caps-lock-to-ctrl.ini` | Caps Lock acts as Ctrl. | no |
| `arrow-keys-as-wasd.ini` | Arrow keys move in games that only read WASD. | no |
| `no-windows-key.ini` | Swallows the Windows key so nothing gets minimised mid fight. | no |

Copy one as a starting point for your own, or hit **New**.

## The profile format

A profile is an ini file you can edit by hand or from the window:

```ini
[profile]
name        = Hotline Miami
description = Throw and pick up with E instead of right click.
enabled     = yes
match       = HotlineMiami.exe, HotlineMiami2.exe   ; blank = every program

[keys]
e = RButton, block       ; press E, the game receives a right click
q = LButton, off         ; off means the line is there but not doing anything
f = MButton, off
```

One line per remap: `what I press = what the program receives, options`.
Anything after `;` is a note and shows up in the window.

| Option | What it does |
| --- | --- |
| `hold` | Default. The target is held for exactly as long as you hold the key. |
| `tap` | One press, one click, however long you hold the key. |
| `toggle` | Press once to hold the target down, press again to let go. |
| `turbo 60` | Repeats the target while you hold the key, every 60 ms. |
| `block` | Default. The key you press is cancelled. |
| `pass` | Also send the key you pressed, as well as the target. |
| `off` | Keep the line but switch it off. |

A target of `none` swallows the key and sends nothing, which is how
`no-windows-key.ini` works.

`match` takes a comma separated list. Each entry is an executable
(`HotlineMiami.exe`), part of a window title (`Photoshop`), or a raw
AutoHotkey criterion (`ahk_class Notepad`).

### When two profiles want the same key

The profile aimed at the program you are in beats a global one. So Caps Lock
can be Ctrl everywhere while a game profile turns it into something else for
that game only. The window marks the losing row **beaten by ...** so nothing is
a mystery.

## Key names

Capture (in the edit window) records whatever you press, so you rarely need
these:

* Mouse: `LButton`, `RButton`, `MButton`, `XButton1`, `XButton2`, `WheelUp`, `WheelDown`
* Keyboard: `a` to `z`, `0` to `9`, `Space`, `Enter`, `Tab`, `Escape`, `Shift`,
  `Ctrl`, `Alt`, `CapsLock`, `Up`, `Down`, `Left`, `Right`, `F1` to `F12`,
  `Numpad0` to `Numpad9`, `LWin`, `RWin`
* `none` swallows the key

The full list is the
[AutoHotkey key list](https://www.autohotkey.com/docs/v2/KeyList.htm).

## Options

Behind the **Options** button: the on / off and window hotkeys, the send method
(`Input`, or `Event` and `Play` for programs that ignore synthetic input),
whether stuck keys are released automatically, on screen messages, and a one
click **Run at Windows startup**. They live in `Remap.ini` next to the script.

## Troubleshooting

**Nothing happens.** Hover the tray icon. It says `off`, `waiting`, or
`active: <profile>`. If it says waiting while your program is in front, the
profile is scoped to a different executable; fix it with **Choose programs**.
If you launched the program as administrator, run Remap as administrator too,
or Windows will not let it send keys there.

**A key feels stuck.** Press F8 twice, which releases everything. The watchdog
normally catches this on its own within a third of a second.

**The program ignores the key.** Switch *Send using* to `Event`, then `Play`.

**It will not start.** You need AutoHotkey **v2**. A v1 install refuses the
script with a version error.

## Why AutoHotkey and not Python

Because you should be able to read what you are running. AutoHotkey installs
once and runs a plain `.ahk` text file, so nothing here is a mystery binary.
Python would mean either shipping a compiled `.exe`, which is exactly the thing
that looks dangerous, or asking everyone to install Python plus packages for
low level keyboard hooks that AutoHotkey does natively and better. The whole
thing is one readable file and a folder of text.

## Requirements

* Windows
* AutoHotkey v2.0 or newer

## License

GPL-3.0, see [LICENSE](LICENSE).
