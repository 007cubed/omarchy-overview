# Workspace Overview

A live overview of every workspace on the focused monitor for [Omarchy](https://omarchy.org/),
a bar widget in the same shape, and an optional set of touchpad gestures built around it.

<!-- ![Workspace Overview](preview.png) -->

- Omarchy's ten workspace slots in a 5×2 grid, with live window previews
- **Click** a window to focus it, or a workspace to go there
- **Drag** a window onto another workspace to move it
- **Drag a number badge** onto another workspace to swap the two
- While dragging, the start tile has a dashed outline, the target a solid one, and the line
  under the grid says what the drop does ("Move firefox: 2 → 7", "Swap 2 ↔ 7")
- **1–0** jump to that slot, **Esc** or a click on the background closes
- **Pointer:** opening puts the pointer on the current workspace's tile. Closing without going
  anywhere puts it back where it was; going somewhere leaves it on the window that got focus (or
  the middle of the screen), so focus-follows-mouse keeps that focus. Off with `cursor:no_warps`
- **Switch hint:** outside the overview, every workspace switch flashes a small 5×2 card at the
  bottom of the screen for about 0.6 s: "3 → 4" over the grid, its highlight sliding from the old
  slot to the new one. Carrying a window (4 fingers sideways, Super + Shift + number) looks
  different: the app's icon and "Move firefox: 3 → 4", and a dashed outline on the slot it left.
  It stays away while the overview is open and on a workspace with a fullscreen window.

## Install

```bash
omarchy plugin add https://github.com/GuyKawaii/omarchy-overview.git --enable --yes
```

Open it from a keybinding, a gesture or a terminal:

```bash
omarchy-shell shell toggle guykawaii.overview '{}'
```

For example, on Super + Alt + O (free in Omarchy's defaults) in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + O", "Workspace overview", function()
  hl.exec_cmd("omarchy-shell shell toggle guykawaii.overview '{}'")
end)
```

## Bar widget (optional)

The plugin is also a bar widget that shows the ten slots as the same 5×2 grid, 1–5 over 6–10,
so a row change reads as a move up or down. Put it in place of `omarchy.workspaces` in
`~/.config/omarchy/shell.json`:

```json
"left": [
  { "id": "omarchy.menu" },
  { "id": "guykawaii.overview", "style": "grid" }
]
```

| `style` | Looks like |
|---|---|
| `grid` (default) | a small 5×2 block of cells: solid where there are windows, an outline where empty; the current slot is an accent cell with a ring that slides to it. Hover a slot for its number |
| `row` | the current row's five numbers, sliding up or down when the row changes, plus ▴/▾ pointing at the other row (accent when it has windows; click to toggle row) |
| `combo` | the current row's five numbers, with the other row as five short bars on its side (under 1–5, over 6–0), solid where it has windows; on a row change the numbers slide and the bars flip sides. Click a bar to go to that slot |

Click a slot to go there; the wheel steps through the slots. The setting applies live. Unlike
Omarchy's widget it does not show or cycle the workspace layout.

## Gestures (optional)

`hypr/gestures.lua` is a full touchpad gesture set for Hyprland 0.56+. Load it at the end of
`~/.config/hypr/input.lua`:

```lua
dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/guykawaii.overview/hypr/gestures.lua")
```

| Gesture | Action |
|---|---|
| 3 fingers ← → | switch workspace, empty ones too, stopping at 1 and 10 |
| 3 fingers ↑ | fullscreen |
| 3 fingers ↓ | toggle row: go to the slot above or below (3 ↔ 8), sliding vertically |
| 4 fingers ↑ | open the overview |
| 4 fingers ↓ | close the overview; outside it, toggle the scratchpad |
| 4 fingers ← → | carry the focused window to the next/previous workspace, with a short slide |
| Super + 3 fingers | resize: the dividers follow your fingers, on both axes |
| Super + 3-finger tap | reset the split under the cursor to 50/50 |
| Super + 4 fingers | drag the window under the cursor |

It replaces any gestures you already have on the same fingers. To take only some of them,
copy the lines you want instead of loading the file.

### How it works

- **Slides.** Omarchy turns workspace animations off, so the carry and row gestures turn the
  slide on just for their own move (a critically damped spring, about 0.16 s; sideways for carry,
  vertical for rows) and off again 0.3 s later. Workspace keys still jump. Only the newest swipe
  turns it off, so quick swipes don't cut each other short. With animations off it only moves.
- **Rows.** The ten slots are the overview's 5×2 grid, so 3 fingers move around it: sideways
  along the slots, down to the other row. With two rows one toggle is enough. Like Super + number,
  toggling into an empty slot makes that workspace. A 3-finger swipe from 5 to 6 still crosses
  rows. Hyprland picks the slide's direction by workspace number, so going 3 → 8 slides up.
- **Persistent slots.** Hyprland's swipe only steps through workspaces that exist, so empty slots
  would be skipped. The file keeps every monitor's ten slots as persistent workspaces (redone when
  a monitor arrives), so the swipe visits all ten and still follows your fingers; with
  `workspace_swipe_create_new` off it never makes an eleventh. The costs: Omarchy's own workspace
  widget shows all ten numbers, Super + Tab steps through empty slots too, and
  the windows of an unplugged monitor still wait as guests on another one, as before.
- **Scratchpad.** 4 fingers down closes the overview when its layer is open, and otherwise pulls
  the scratchpad down like a drop-down terminal. For 0.3 s after the overview closes it is ignored,
  so a double swipe doesn't open the scratchpad by accident.
- **Resize.** Hyprland's built-in `resize` gesture only snaps the window being resized, so the
  windows next to it trail behind, and it does nothing when the cursor sits on the half of a
  window next to a screen edge. This one feeds the finger movement to the resize dispatcher and
  pauses animations on that workspace's windows while the fingers are down.
- **Split reset.** A 3-finger tap is a middle click. Hyprland 0.56 has no exact split ratio, so
  the bind clamps the split to its minimum and adds back to 50/50.

## Updating

```bash
omarchy plugin update guykawaii.overview
omarchy restart shell
```

The shell caches the QML, so changes to the plugin show up only after a restart. Changes to
`hypr/gestures.lua` apply on `hyprctl reload`.

## Requirements

- Omarchy with the Quickshell desktop shell and the Lua Hyprland config
- Hyprland 0.56 or newer for the gestures
- Omarchy's ten workspace slots per monitor (the default)

## License

MIT
