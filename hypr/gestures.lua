-- Touchpad gestures for Omarchy (Hyprland 0.56+, Lua config), built around the
-- guykawaii.overview plugin. Load it from ~/.config/hypr/input.lua:
--
--   dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/guykawaii.overview/hypr/gestures.lua")
--
-- 3 fingers: move between places. 4 fingers: the overview and carrying windows.
--   3 left/right       switch workspace
--   3 up / down        fullscreen / scratchpad
--   4 up / down        open / close the overview
--   4 left/right       carry the focused window to the next/previous workspace
--   SUPER + 3 swipe    resize: the dividers follow the fingers
--   SUPER + 3 tap      reset the split under the cursor to 50/50 (a middle click)
--   SUPER + 4 swipe    drag the window under the cursor
--
-- Assumes Omarchy's ten workspace slots per monitor (o.workspaces).

local OVERVIEW = "guykawaii.overview"

-- Carry ---------------------------------------------------------------------------
-- Carrying a window slides the workspaces. Omarchy keeps that animation off, so it
-- is turned on only for the swipe. Each swipe bumps `carry_gen`, so only the newest
-- swipe's timer turns it off again (an older timer would cut a later slide short).
hl.curve("overviewCarrySpring", { type = "spring", mass = 1, stiffness = 800, dampening = 49 })
local carry_gen = 0
local function move_window_by(step)
  return function()
    local workspace = hl.get_active_workspace()
    if not workspace or workspace.special or workspace.id < 1 then
      return
    end
    local slot = (workspace.id - 1) % 10 + 1 + step
    if slot < 1 or slot > 10 then
      return
    end
    carry_gen = carry_gen + 1
    local gen = carry_gen
    hl.animation({ leaf = "workspaces", enabled = true, speed = 4, spring = "overviewCarrySpring", style = "slide" })
    o.workspaces.move_window(slot)()
    hl.timer(function()
      if gen == carry_gen then
        hl.animation({ leaf = "workspaces", enabled = false })
      end
    end, { timeout = 300, type = "oneshot" })
  end
end

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
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "up", action = "fullscreen" })
hl.gesture({ fingers = 3, direction = "down", action = "special", workspace_name = "scratchpad" })

hl.gesture({ fingers = 4, direction = "up", action = function()
  hl.exec_cmd("omarchy-shell shell toggle " .. OVERVIEW .. " '{}'")
end })
hl.gesture({ fingers = 4, direction = "down", action = function()
  hl.exec_cmd("omarchy-shell shell hide " .. OVERVIEW)
end })
hl.gesture({ fingers = 4, direction = "left", action = move_window_by(1) })
hl.gesture({ fingers = 4, direction = "right", action = move_window_by(-1) })

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
hl.gesture({ fingers = 4, direction = "swipe", mods = "SUPER", action = "move" })

-- 0.56 has no "splitratio exact", so clamp to the minimum (0.1) and add 0.9.
o.bind("SUPER + mouse:274", "Reset window split", function()
  hl.dispatch(hl.dsp.layout("splitratio -1.9"))
  hl.dispatch(hl.dsp.layout("splitratio 0.9"))
end)

-- Swiping past the last workspace does nothing instead of making an empty one.
hl.config({ gestures = { workspace_swipe_create_new = false } })
