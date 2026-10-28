local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")

-- Spec §7.6: the status line (launcher tooltip, and chat at login and at the first
-- activation). Pure text from a ScanGate.State() table; imports nothing from ScanGate.
local Status = {}

local concat = table.concat

function Status.PausedText(state)
  local reason = state.reason
  if reason == "noTrade" then
    return Localization.Text("Paused — no Trade chat here")
  end
  if reason == "instance" then
    return Localization.Text("Paused — off in instances")
  end
  if reason == "notStarted" then
    return Localization.Text("Paused — Craft Alert did not start; /reload to try again")
  end
  if reason == "disabled" then
    return Localization.Text("Paused — Craft Alert is turned off")
  end
  if reason == "building" then
    return Localization.Text("Starting — loading recipes")
  end
  if state.unreadProfession then
    return Localization.Text("Paused — no profession read yet: open %s once", state.unreadProfession)
  end
  return Localization.Text("Paused — no recipes to listen for")
end

local pausedText = Status.PausedText

-- state: ScanGate.State() = { active, reason, channels, recipeCount, crafterCount, unreadProfession }.
function Status.Text(state)
  if not state.active then
    return pausedText(state)
  end
  local channels = #state.channels > 0 and concat(state.channels, ", ") or Localization.Text("no channel")
  return Localization.Text(
    "Listening in %s — %s, %s",
    channels,
    Localization.Plural(state.recipeCount, "%d recipe", "%d recipes"),
    Localization.Plural(state.crafterCount, "%d crafter", "%d crafters")
  )
end

ns.Status = Status
return Status
