local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local GreetAction = ns.GreetAction or require("CraftAlert.Model.GreetAction")
local SendGuard = ns.SendGuard or require("CraftAlert.Model.SendGuard")

-- Spec §7.1: what a click does to a lead, the same on the toast and on leads-window rows.
-- Right dismisses whatever modifier is held, once the lead has been up 0.5 s (the look rule of
-- §7.5: a list that shifted under a still cursor never drops a lead the player has not seen);
-- on the left button shift prefills, ctrl opens an empty whisper and a plain click greets. Other
-- buttons do nothing.
local ClickRouter = {}

local type = type

local function isDown(apiName)
  local api = _G[apiName]
  return type(api) == "function" and api() and true or false
end

-- button: the OnClick button name; shownAt: GetTime() when the lead's toast or row appeared.
-- → "greet", "prefill", "empty", "dismiss", or nil when the click does nothing.
function ClickRouter.Handle(button, lead, shownAt)
  if lead == nil then
    return nil
  end
  if button == "RightButton" then
    if not SendGuard.Looked(shownAt) then
      return nil
    end
    Leads.Dismiss(lead.id)
    return "dismiss"
  end
  if button ~= "LeftButton" then
    return nil
  end
  if isDown("IsShiftKeyDown") then
    GreetAction.Prefill(lead)
    return "prefill"
  end
  if isDown("IsControlKeyDown") then
    GreetAction.Empty(lead)
    return "empty"
  end
  GreetAction.Greet(lead, shownAt)
  return "greet"
end

ns.ClickRouter = ClickRouter
return ClickRouter
