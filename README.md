# Workspace Overview

A live overview of every workspace on the focused monitor for [Omarchy](https://omarchy.org/),
plus an optional set of touchpad gestures built around it.

<!-- ![Workspace Overview](preview.png) -->

- Omarchy's ten workspace slots in a 5×2 grid, with live window previews
- **Click** a window to focus it, or a workspace to go there
- **Drag** a window onto another workspace to move it
- **Drag a number badge** onto another workspace to swap the two
- **1–0** jump to that slot, **Esc** or a click on the background closes

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

## Gestures (optional)

`hypr/gestures.lua` is a full touchpad gesture set for Hyprland 0.56+. Load it at the end of
`~/.config/hypr/input.lua`:

```lua
dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/guykawaii.overview/hypr/gestures.lua")
```

| Gesture | Action |
|---|---|
| 3 fingers ← → | switch workspace |
| 3 fingers ↑ | fullscreen |
| 3 fingers ↓ | scratchpad |
| 4 fingers ↑ | open the overview |
| 4 fingers ↓ | close the overview |
| 4 fingers ← → | carry the focused window to the next/previous workspace, with a short slide |
| Super + 3 fingers | resize: the dividers follow your fingers, on both axes |
| Super + 3-finger tap | reset the split under the cursor to 50/50 |
| Super + 4 fingers | drag the window under the cursor |

It replaces any gestures you already have on the same fingers. To take only some of them,
copy the lines you want instead of loading the file.

### How it works

- **Carry slide.** Omarchy turns workspace animations off, so the carry gesture turns the slide
  on just for its own move (a critically damped spring, about 0.16 s) and off again 0.3 s later.
  Workspace keys still jump. Only the newest swipe turns it off, so quick swipes don't cut each
  other short.
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
