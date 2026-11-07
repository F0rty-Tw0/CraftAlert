local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Theme = ns.Theme or require("CraftAlert.UI.Theme")

-- Phone-style slide spec: the widths BridgePanel (UI/BridgePanel.lua) gives its panes in WM's
-- host. `hostWidth` is the host's (0 before it is laid out), `splitWidth` WM's divider position
-- from onSplit (nil until WM calls it).
local BridgeWidths = {}

local max = math.max
local min = math.min

-- WM's CONTENT_MIN_WIDTH and CONTACTS_MIN_WIDTH (UI/Theme/Layout.lua:12-13, WM): the details keep
-- at least 340 px of the host, the list takes the rest between 180 and the standalone 260.
local DETAILS_MIN_WIDTH = 340
-- A host narrower than the list's minimum plus the details' minimum cannot show both: the narrow
-- page (one pane at a time) takes over.
local NARROW_BELOW = Theme.LAYOUT.LIST_MIN_WIDTH + DETAILS_MIN_WIDTH

-- A host not laid out yet (0) is wide.
function BridgeWidths.IsNarrow(hostWidth)
  return hostWidth > 0 and hostWidth < NARROW_BELOW
end

-- WM's divider once it called onSplit, else what the host leaves the details, between the minimum
-- and the standalone window's.
local function splitOrClamp(hostWidth, splitWidth)
  if splitWidth ~= nil then
    return splitWidth
  end
  return min(Theme.LAYOUT.LIST_WIDTH, max(Theme.LAYOUT.LIST_MIN_WIDTH, hostWidth - DETAILS_MIN_WIDTH))
end

-- The list's width in the host: the divider, kept clear of the details' minimum (WM's phone window
-- resized past the narrow threshold sends a split of about its full width); the rail is under the cap.
-- Narrow, the List is the whole host and the divider is ignored (kept for when the host widens).
-- Never below 0, even for a host under the details' minimum that is not yet known to be narrow.
function BridgeWidths.List(hostWidth, splitWidth, narrow)
  if narrow then
    return hostWidth
  end
  local width = splitOrClamp(hostWidth, splitWidth)
  if splitWidth ~= nil and hostWidth > 0 then
    return max(0, min(width, hostWidth - DETAILS_MIN_WIDTH))
  end
  return width
end

-- The settings nav keeps its minimum when WM's divider snaps to the rail.
function BridgeWidths.Nav(hostWidth, splitWidth)
  return max(splitOrClamp(hostWidth, splitWidth), Theme.LAYOUT.LIST_MIN_WIDTH)
end

ns.BridgeWidths = BridgeWidths
return BridgeWidths
