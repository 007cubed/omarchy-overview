-- Touchpad gestures for Omarchy (Hyprland 0.56+, Lua config), built around the
-- guykawaii.overview plugin. Load it from ~/.config/hypr/input.lua:
--
--   dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/guykawaii.overview/hypr/gestures.lua")
--
-- 3 fingers: move between places. 4 fingers: the overview and carrying windows.
--   3 left/right       next/previous slot, looping within the row (5 -> 1, 10 -> 6)
--   3 up               fullscreen
--   3 down             toggle row: the slot above or below (3 <-> 8)
--   4 up               open / close the overview
--   4 down             close the overview; outside it, toggle the scratchpad
--   4 left/right       carry the focused window to the next/previous slot, same loop
--   SUPER + 3 swipe    resize: the dividers follow the fingers
--   SUPER + 3 tap      reset the split under the cursor to 50/50 (a middle click)
--   SUPER + 4 swipe    drag the window under the cursor
--   SUPER + 4 pinch    float / tile the window under the cursor
--
-- Assumes Omarchy's ten workspace slots per monitor (o.workspaces).

local OVERVIEW = "guykawaii.overview"

-- Slides ------------------------------------------------------------------------
-- Omarchy keeps the workspaces animation off, so workspace keys jump. A gesture
-- turns it on just for its own move and off again 300 ms later. Each move bumps
-- `slide_gen`, so only the newest move's timer turns it off (an older timer would
-- cut a later slide short). With animations off altogether it only moves.
hl.curve("overviewCarrySpring", { type = "spring", mass = 1, stiffness = 800, dampening = 49 })
local slide_gen = 0
local function with_slide(style, fn)
  if not hl.get_config("animations:enabled") then
    fn()
    return
  end
  slide_gen = slide_gen + 1
  local gen = slide_gen
  hl.animation({ leaf = "workspaces", enabled = true, speed = 4, spring = "overviewCarrySpring", style = style })
  fn()
  hl.timer(function()
    if gen == slide_gen then
      hl.animation({ leaf = "workspaces", enabled = false })
    end
  end, { timeout = 300, type = "oneshot" })
end

-- The active workspace's slot (1-10), or nil on a special or named workspace.
local function active_slot()
  local workspace = hl.get_active_workspace()
  if not workspace or workspace.special or workspace.id < 1 then
    return nil
  end
  return (workspace.id - 1) % 10 + 1
end

-- The slot `step` places along the active slot's row (the ten slots are a 5x2 grid,
-- 1-5 over 6-10), looping: 5 + 1 = 1, 1 - 1 = 5, 10 + 1 = 6, 6 - 1 = 10. Never leaves the row;
-- nil on a special or named workspace.
local function row_slot(step)
  local slot = active_slot()
  if not slot then
    return nil
  end
  local row = (slot - 1) // 5 * 5
  local target = row + (slot - 1 - row + step) % 5 + 1
  return target
end

-- Hyprland picks a workspace slide's direction by number, so a wrap (5 -> 1) slides
-- in number order, the opposite way to the swipe. It uses the same "slide" anyway.
-- Switch: go to the next/previous slot in the row. The built-in workspace swipe
-- can't loop, so it is two one-shot gestures. Like Super + number, it makes the
-- workspace if it is empty.
local function focus_by(step)
  return function()
    local slot = row_slot(step)
    if slot then
      with_slide("slide", o.workspaces.focus(slot))
    end
  end
end

-- Carry: take the focused window to the next/previous slot in the row.
local function move_window_by(step)
  return function()
    local slot = row_slot(step)
    if slot then
      with_slide("slide", o.workspaces.move_window(slot))
    end
  end
end

-- Rows: the ten slots are a 5x2 grid, 1-5 over 6-10, as in the overview. Toggling
-- the row goes to the slot above or below (3 <-> 8), sliding vertically. Like
-- Super + number, it makes the workspace if it is empty.
local function toggle_row()
  local slot = active_slot()
  if not slot then
    return
  end
  with_slide("slidevert", o.workspaces.focus(slot <= 5 and slot + 5 or slot - 5))
end

local function overview_open()
  for _, layer in ipairs(hl.get_layers()) do
    if layer.namespace == "guykawaii-overview" then
      return true
    end
  end
  return false
end

-- 4 down right after the overview closed (a double swipe, or Esc then a swipe)
-- would open the scratchpad by accident, so it is ignored for 300 ms.
local overview_just_closed = false
hl.on("layer.closed", function(layer)
  if layer and layer.namespace == "guykawaii-overview" then
    overview_just_closed = true
    hl.timer(function() overview_just_closed = false end, { timeout = 300, type = "oneshot" })
  end
end)

-- Resize --------------------------------------------------------------------------
-- Not the built-in "resize" action: in 0.56 it only snaps the window being resized,
-- so its neighbours trail behind on the windowsMove animation, and its cursor-corner
-- logic does nothing when the cursor sits next to a screen edge. The plain resize
-- dispatcher moves the dividers with the fingers on both axes from anywhere in the
-- window. While the fingers are down, the workspace's windows get no_anim by
-- setprop; "unset" afterwards hands them back to the window rules.
local resize_windows = {}
local function set_no_anim(value)
  for _, w in ipairs(resize_windows) do
    hl.dispatch(hl.dsp.window.set_prop({ prop = "no_anim", value = value, window = w }))
  end
end

-- Gestures ------------------------------------------------------------------------
-- One-shot gestures fire on `start`, as soon as the swipe is recognised: Hyprland
-- fixes the direction then, and an end-only action can't be cancelled either.
-- Fingers left = next slot, right = previous (workspace_swipe_invert's convention).
hl.gesture({ fingers = 3, direction = "left", action = { start = focus_by(1) } })
hl.gesture({ fingers = 3, direction = "right", action = { start = focus_by(-1) } })
hl.gesture({ fingers = 3, direction = "up", action = "fullscreen" })
-- Fires as soon as the swipe is recognised, like 4 up, not when the fingers lift.
hl.gesture({ fingers = 3, direction = "down", action = { start = toggle_row } })

-- Fires as soon as the swipe is recognised, not when the fingers lift, so the
-- overview is already appearing during the swipe.
hl.gesture({ fingers = 4, direction = "up", action = {
  start = function()
    hl.exec_cmd("omarchy-shell shell toggle " .. OVERVIEW .. " '{}'")
  end,
} })
-- 4 down closes the overview when it is open, and otherwise toggles the scratchpad
-- (pulled down like a drop-down terminal; same as SUPER+S).
hl.gesture({ fingers = 4, direction = "down", action = { start = function()
  if overview_open() then
    hl.exec_cmd("omarchy-shell shell hide " .. OVERVIEW)
  elseif not overview_just_closed then
    hl.dispatch(hl.dsp.workspace.toggle_special("scratchpad"))
  end
end } })
hl.gesture({ fingers = 4, direction = "left", action = { start = move_window_by(1) } })
hl.gesture({ fingers = 4, direction = "right", action = { start = move_window_by(-1) } })

hl.gesture({ fingers = 3, direction = "swipe", mods = "SUPER", action = {
  start = function()
    local active = hl.get_active_window()
    resize_windows = active and hl.get_workspace_windows(active.workspace) or {}
    set_no_anim("1")
  end,
  update = function(e)
    hl.dispatch(hl.dsp.window.resize({ x = e.delta.x, y = e.delta.y, relative = true }))
  end,
  finish = function()
    set_no_anim("unset")
    resize_windows = {}
  end,
} })
-- Broad "swipe" rules last, so they don't overshadow the directional ones.
-- SUPER + 4-finger pinch (in or out): toggle the window under the cursor between
-- floating and tiled, like SUPER+T. Fires as the pinch is recognised.
hl.gesture({ fingers = 4, direction = "pinch", mods = "SUPER", action = { start = function()
  hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
end } })
hl.gesture({ fingers = 4, direction = "swipe", mods = "SUPER", action = "move" })

-- 0.56 has no "splitratio exact", so clamp to the minimum (0.1) and add 0.9.
o.bind("SUPER + mouse:274", "Reset window split", function()
  hl.dispatch(hl.dsp.layout("splitratio -1.9"))
  hl.dispatch(hl.dsp.layout("splitratio 0.9"))
end)
