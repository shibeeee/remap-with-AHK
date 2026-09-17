# Hotline Miami Remap

Remaps keys in Hotline Miami to others using AutoHotkey.

Out of the box it does the one thing everybody wants: **E throws** (it becomes the
right mouse button), so you can throw and pick up weapons without taking your
hand off the mouse. Everything else, including the WASD / movement remaps, ships
switched off and is one tick box away in the settings window.

The remaps only apply while a Hotline Miami window is in focus, so you can leave
the script running while you alt tab, chat, or browse.

```
E  ->  right mouse button   (throw / pick up)
```

## Quick start

1. Install [AutoHotkey v2](https://www.autohotkey.com/) (v2.0 or newer, not v1).
2. Download `HotlineMiamiRemap.ahk` from this repository.
3. Double click it. A tray icon appears.
4. Start Hotline Miami and press **E** to throw.

Press **F9** (or double click the tray icon) for the settings window, **F8** to
switch all remapping on and off. Both hotkeys are configurable.

## What is set up by default

| When you press | The game gets | Group | On? |
| --- | --- | --- | --- |
| `E` | right mouse (throw / pick up) | Core | **yes** |
| `Q` | left mouse (attack) | Core | no |
| `Up` `Left` `Down` `Right` | `W` `A` `S` `D` | Movement | no |
| `Mouse 4` | `R` (restart level), tap mode | Extras | no |
| `Mouse 5` | `Space` | Extras | no |
| `Caps Lock` | `Shift` | Extras | no |
| `Left Windows` | nothing, key is blocked | Extras | no |
| `Right Alt` | left mouse on turbo, 60 ms | Extras | no |

Nothing is locked down: change any row, add your own, or delete the lot and
start over with **Restore defaults**.

### Turning on WASD / movement

Open the settings window and tick **"Enable the movement group"**. That switches
on the four arrow key remaps in one go, so the arrow keys move your character
while the game still thinks it is reading WASD. Want a different movement
layout, say IJKL or ESDF? Edit those four rows (or add new ones) and point them
at `w`, `a`, `s` and `d`.

## The settings window

* **The list.** One row per remap. Double click a row to edit it, or use
  Add / Edit / On off / Remove. Changes take effect immediately and are saved
  for you.
* **Capture.** In the edit window, click Capture and press the key or mouse
  button you mean. No need to know AutoHotkey key names.
* **Profiles.** Keep separate setups side by side (one for Hotline Miami, one
  for Hotline Miami 2, one for a friend) and switch between them from the drop
  down. New, Copy and Delete are right there.
* **Options.**
  * *Only remap while Hotline Miami is in focus* (on by default). Untick it to
    remap everywhere, which is handy when testing.
  * *Release stuck keys automatically*: if you alt tab mid throw, the script
    lets go of whatever it was holding.
  * *Game programs*: the executables to watch for, comma separated. Defaults to
    `HotlineMiami.exe, HotlineMiami2.exe`. Add your own if you use a different
    build.
  * *Send using*: `Input` is fastest and right for almost everyone. Try `Event`
    or `Play` only if the game ignores the remapped key.
  * *Run at Windows startup*: one click, creates or removes the shortcut.

## Modes

Every remap has a mode, so one key can do more than a plain swap.

| Mode | What it does |
| --- | --- |
| `hold` | The target is held for exactly as long as you hold your key. Use this for throwing, attacking and moving. |
| `tap` | One press, one click, however long you hold the key. |
| `toggle` | Press once to hold the target down, press again to let go. |
| `turbo` | Repeats the target while you hold the key. The interval in milliseconds is yours to set. |

There is also **Also send the original key**, which passes your key through to
the game as well as sending the target, and the target `None`, which swallows
the key so the game never sees it (that is how the Windows key row works).

## Key names

The Capture button fills these in for you, but if you would rather type:

* Mouse: `LButton`, `RButton`, `MButton`, `XButton1`, `XButton2`, `WheelUp`, `WheelDown`
* Movement: `w`, `a`, `s`, `d`, `Up`, `Down`, `Left`, `Right`
* Other: `Space`, `Enter`, `Tab`, `Escape`, `Shift`, `Ctrl`, `Alt`, `CapsLock`,
  `F1` to `F12`, `Numpad0` to `Numpad9`
* `None` blocks the key

The full list lives in the
[AutoHotkey key list](https://www.autohotkey.com/docs/v2/KeyList.htm).

## Where settings are kept

Next to the script, in `HotlineMiamiRemap.ini`. Copy the folder and your setup
comes with it. One line per remap:

```ini
[Profile Default]
Count=2
M1=1|e|RButton|hold|60|0|Core|Throw / pick up weapon
M2=0|Up|w|hold|60|0|Movement|Arrow keys move instead of WASD
```

The fields are: enabled, your key, what the game gets, mode, turbo interval,
passthrough, group, note. You can edit the file by hand and pick
**Reload script** from the tray menu, but the settings window is easier.

## Troubleshooting

**The remap does nothing.** Check the tray tooltip: it says `active`,
`waiting for the game` or `off`. If it is waiting while the game is running,
your build uses a different executable name; add it under *Game programs*. If
you launched the game as administrator, run the script as administrator too, or
Windows will not let it send keys to the game.

**A key feels stuck.** Press the on / off hotkey twice (F8 by default), which
releases everything. *Release stuck keys automatically* handles the usual cause,
alt tabbing mid press.

**The game ignores the sent key.** Switch *Send using* from `Input` to `Event`,
and to `Play` as a last resort. Some capture and overlay software also swallows
synthetic input.

**On screen messages do not show.** Tooltips cannot draw over exclusive
fullscreen. Run the game borderless or windowed, or untick the option.

**It does not start.** You need AutoHotkey **v2**. A v1 install will refuse the
script with a version error.

## Requirements

* Windows
* AutoHotkey v2.0 or newer
* Hotline Miami, or any other game really: nothing here is specific to it
  beyond the default executable names

## License

GPL-3.0, see [LICENSE](LICENSE).
