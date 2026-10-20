local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")

-- The words the toast and the leads-window rows show for a lead.
local LeadText = {}

local floor = math.floor
local max = math.max
local tostring = tostring

-- The matched item link, else the recipe, else the profession.
function LeadText.What(lead)
  return lead.itemLink or lead.recipeName or lead.profName or ""
end

function LeadText.Crafter(lead)
  return Localization.Text("by %s", tostring(lead.crafter))
end

-- §7.2: "can't order (realm)" when the customer cannot send the crafter an order, else nil.
function LeadText.RealmTag(lead)
  if lead.cannotOrder then
    return Localization.Text("can't order (realm)")
  end
  return nil
end

-- "35s" under a minute, else whole minutes ("2m"); leads expire within the hour.
function LeadText.Age(seconds)
  if seconds < 60 then
    return Localization.Text("%ds", max(0, floor(seconds)))
  end
  return Localization.Text("%dm", floor(seconds / 60))
end

ns.LeadText = LeadText
return LeadText
