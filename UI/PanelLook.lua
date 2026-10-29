local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- The look of the panes inside WhisperMessenger's tab: WM's GetLook answer (spec Part 1) as one
-- value, native (today's paint) for the standalone window, an old WM and any answer that is not
-- the contract.
local PanelLook = {}

PanelLook.NATIVE = { mode = "native" }

local KEYS = {
  "bg_primary",
  "bg_secondary",
  "bg_header",
  "bg_input",
  "divider",
  "contacts_divider",
  "bg_contact_selected",
  "bg_contact_hover",
  "scrollbar",
  "scrollbar_hover",
}

-- WM's hud setting -> look mode; "off" is the flat look.
local MODES = { off = "flat", classic = "classic", retail = "retail" }

local function isColor(value)
  if type(value) ~= "table" or #value ~= 4 then
    return false
  end
  for i = 1, 4 do
    if type(value[i]) ~= "number" then
      return false
    end
  end
  return true
end

-- { mode = "retail" | "classic" | "flat", colors = WM's ten colours }, or NATIVE.
function PanelLook.FromWM(answer)
  if type(answer) ~= "table" or type(answer.colors) ~= "table" then
    return PanelLook.NATIVE
  end
  local mode = MODES[answer.hud]
  if mode == nil then
    return PanelLook.NATIVE
  end
  for _, key in ipairs(KEYS) do
    if not isColor(answer.colors[key]) then
      return PanelLook.NATIVE
    end
  end
  return { mode = mode, colors = answer.colors }
end

-- The look's colour for `key`, `fallback` when the look has none (native).
function PanelLook.Color(look, key, fallback)
  return look.colors and look.colors[key] or fallback
end

ns.PanelLook = PanelLook
return PanelLook
