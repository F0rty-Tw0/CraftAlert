local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Theme = ns.Theme or require("CraftAlert.UI.Theme")

-- Native-HUD spec §5.3: which side of the launcher the toast docks to. The toast opens toward the screen
-- centre, on the launcher's own vertical half. A nil centre counts as left / upper.
local Dock = {}

-- lx, ly: launcher centre; sx, sy: UIParent centre.
-- → point, relativePoint, x, y: the toast's anchor to the launcher.
function Dock.Anchor(lx, ly, sx, sy)
  local gap = Theme.LAYOUT.DOCK_GAP
  local left = lx == nil or sx == nil or lx < sx
  local upper = ly == nil or sy == nil or ly >= sy
  local vertical = upper and "TOP" or "BOTTOM"
  if left then
    return vertical .. "LEFT", vertical .. "RIGHT", gap, 0
  end

  return vertical .. "RIGHT", vertical .. "LEFT", -gap, 0
end

ns.Dock = Dock
return Dock
