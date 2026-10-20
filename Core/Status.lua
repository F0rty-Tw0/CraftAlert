local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")

-- Spec §7.6: the status line (launcher tooltip, and chat at login and at the first
-- activation). Pure text from a ScanGate.State() table; imports nothing from ScanGate.
local Status = {}

local concat = table.concat

local function counted(count, noun)
  return count .. " " .. noun .. (count == 1 and "" or "s")
end

local function pausedText(state)
  local reason = state.reason
  if reason == "notResting" then
    return Localization.Text("Paused — not in a city or inn")
  end
  if reason == "disabled" then
    return Localization.Text("Paused — Craft Alert is turned off")
  end
  if state.unreadProfession then
    return Localization.Text("Paused — no profession read yet: open %s once", state.unreadProfession)
  end
  return Localization.Text("Paused — no recipes to listen for")
end

-- state: ScanGate.State() = { active, reason, channels, recipeCount, crafterCount, unreadProfession }.
function Status.Text(state)
  if not state.active then
    return pausedText(state)
  end
  local channels = #state.channels > 0 and concat(state.channels, ", ") or Localization.Text("no channel")
  return Localization.Text("Listening in %s — %s, %s", channels, counted(state.recipeCount, "recipe"), counted(state.crafterCount, "crafter"))
end

ns.Status = Status
return Status
