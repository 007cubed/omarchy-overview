# Workspace Overview

A live overview of every workspace on the focused monitor for [Omarchy](https://omarchy.org/),
a bar widget in the same shape, and an optional set of touchpad gestures built around it.

<!-- ![Workspace Overview](preview.png) -->

- Omarchy's ten workspace slots in a 5×2 grid, with live window previews
- **Click** a window to focus it, or a workspace to go there
- **Drag** a window onto another workspace to move it
- **Drag a number badge** onto another workspace to swap the two. They trade numbers, so each
  keeps its layout (splits, sizes, floating windows, fullscreen) exactly; the screen stays as it
  is, and if one of them is the current workspace it goes along to its new number
- One mark per meaning: the current workspace has an accent outline and badge; where a click
  or Enter goes (hover and arrow keys alike) gets a ring just outside the tile; the window under
  the pointer gets a light wash; a hovered number gets an outline and an open hand
- While dragging, the copy follows the pointer, what was lifted dims, and the target is the tile
  nearest the copy, counted in whole tiles per axis; 15 % of a tile already reaches the next
  one, so swaps stay short on a touchpad (accent ring and wash); the line under the grid says what
  the drop does ("Move firefox: 2 → 7 · Esc cancels", "Swap 2 ↔ 7"). Esc cancels the drag; a
  drop on its own tile does nothing
- **1–0** jump to that slot, **Esc** or a click on the background closes
- **Arrows** or **hjkl** move a selection (it starts on the current slot and follows the
  pointer), **Enter** goes there
- **Shift + 1–0** moves the window under the pointer (or the selected slot's focused window) to
  that slot and stays in the overview. It goes by the key's place on the number row, so it works
  on any keyboard layout
- The line under the grid names what is under the pointer ("Go to 7", "firefox — title"), and
  lists the controls when nothing is
- **Pointer:** opening puts the pointer on the current workspace's tile. Closing without going
  anywhere puts it back where it was; going somewhere leaves it on the window that got focus (or
  the middle of the screen), so focus-follows-mouse keeps that focus. Off with `cursor:no_warps`
- **Switch hint:** outside the overview, every workspace switch flashes a small 5×2 card at the
  bottom of the screen for about 0.6 s: "3 → 4" over the grid, its highlight sliding from the old
  slot to the new one. Carrying a window (4 fingers sideways, Super + Shift + number) adds an
  arrow across the grid from the slot it left to the new one (a wrap such as 5 → 1 too, back across the row), drawn with the slide, and the app's
  icon and name under the grid; the slot it left shows what is still there. The carry hint stays
  a little longer (about 0.75 s). It stays away while the overview is open and on a workspace
  with a fullscreen window.
- **Level hint:** when the focused window changes level (a 4-finger spread or pinch, or Super + T /
  Super + O) the same card shows three cells, tiled, floating and popped, with pictures of each:
  the new level named on top and accent-filled, a triangle in each gap it crossed pointing the
  way it went (a Super jump crosses two), and the app under it.

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

## Carry arrow colour (optional)

When a window is carried to another workspace, the switch hint draws an arrow from where it
came from. It is the theme's foreground unless Omarchy's `shell.toml` says otherwise, either the
theme's own or your `~/.config/omarchy/shell.toml` (which survives theme switches):

```toml
[overview]
carry-arrow = "green"   # a colors.toml name (green, yellow, magenta, …), a role
                        # (accent, text, urgent, muted) or "#rrggbb"
```

A name follows the theme: "green" is each theme's own green. The other workspaces step back
while the arrow shows. The default, foreground, keeps at least 3:1 (WCAG 1.4.11) against
everything under it in all 23 stock themes; other theme colours fall below that in some.

## Bar widget (optional)

The plugin is also a bar widget that shows the ten slots as the same 5×2 grid, 1–5 over 6–10,
so a row change reads as a move up or down. After the slots it shows the shown workspace's layout
the way `omarchy.workspaces` does (a square tiles, a circle scrolls, a triangle floats); click it
to cycle, as Super + L. Put it in place of `omarchy.workspaces` in
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
| 3 fingers ← → | next/previous slot, looping within the row (5 → 1, 10 → 6), empty ones too. On a scrolling workspace it first moves to the next/previous window in the strip, and goes on to the slot only past its end |
| 3 fingers ↑ | fullscreen |
| 3 fingers ↓ | toggle row: go to the slot above or below (3 ↔ 8), sliding vertically |
| 4 fingers ↑ | open the overview |
| 4 fingers ↓ | close the overview; outside it, toggle the scratchpad |
| 4 fingers ← → | carry the focused window to the next/previous slot, same loop, with a short slide |
| Super + 3 fingers | resize: the dividers follow your fingers, on both axes |
| Super + 3-finger tap | reset the split under the cursor to 50/50 |
| Super + 4 fingers | drag the window under the cursor |
| 4-finger spread | lift the window one step: tiled → floating (where it is) → popped (centred, kept on top on every workspace, like Omarchy's Super + O) |
| 4-finger pinch | put it back one step: fullscreen → normal, popped → floating, floating → tiled |
| Super + 4-finger spread | straight to popped |
| Super + 4-finger pinch | straight back into the tiling |

It replaces any gestures you already have on the same fingers. To take only some of them,
copy the lines you want instead of loading the file.

### How it works

- **Slides.** Omarchy turns workspace animations off, so the sideways, carry and row gestures
  turn the animation on just for their own move (a critically damped spring, about 0.16 s;
  sideways for switch and carry, vertical for rows) and off again 0.3 s later. Workspace keys still jump. Only the newest swipe
  turns it off, so quick swipes don't cut each other short. With animations off it only moves.
- **Rows.** The ten slots are the overview's 5×2 grid, so 3 fingers move around it: sideways
  along the row, down to the other row. With two rows one toggle is enough. Like Super + number,
  going to an empty slot makes that workspace. Fingers left go to the next slot, right to the
  previous one, and the row loops: 5 → 1, 1 → 5, 10 → 6, 6 → 10, never across rows. These are
  plain one-shot gestures, not Hyprland's tracked workspace swipe (which can't loop), so the move
  fires as soon as the swipe is recognised and doesn't follow the fingers.
- **Wraps.** Hyprland picks the slide's direction by workspace number, so a wrap such as 5 → 1
  slides in number order, the opposite way to the swipe. It uses the same slide anyway, and the
  switch hint draws a carried wrap like any other carry: one arrow back across the row.
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
