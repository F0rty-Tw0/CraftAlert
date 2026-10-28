local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local LeadText = ns.LeadText or require("CraftAlert.UI.LeadText")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local CardBody = ns.CardBody or require("CraftAlert.UI.CardBody")
local CardTipText = ns.CardTipText or require("CraftAlert.UI.CardTipText")

-- Spec C.3: each customer's info line in their WhisperMessenger conversation, with its hover
-- tooltip lines, following the customer's newest active lead. UI/WhisperBridge.lua calls Sync on
-- every Leads "change" and hands it the call into WM; the line and lines are built again only for
-- a customer whose newest lead, or what of it they show, changed.
local BridgeInfo = {}

local concat = table.concat
local ipairs = ipairs
local pairs = pairs

-- The lead fields the line and the tooltip lines read that can change while the lead is listed: a
-- repeated request (message, channel, why, time), a new main crafter (crafter, recipe), a loaded
-- item (its link).
local FEEDS = { "time", "message", "channel", "why", "crafter", "recipeName", "itemLink" }

local built = {} -- customer -> { lead, class, text, lines, joined, and each FEEDS field as built }
local sent = {} -- customer -> the `joined` WM last accepted

local function add(parts, text)
  if text and text ~= "" then
    parts[#parts + 1] = text
  end
end

-- "Craft Alert: <what> · <profession> · <crafter>", the profession dropped when it is the what, the
-- crafter in class colour when known.
local function infoText(lead)
  local what, parts = LeadText.What(lead), {}
  add(parts, what)
  if lead.profName ~= what then
    add(parts, lead.profName)
  end
  local crafter = CardBody.Crafters(lead)[1]
  add(parts, crafter and FrameKit.ClassCode(crafter.name, crafter.color))
  return FrameKit.ThemeCode(Localization.Text("Craft Alert") .. ":", Theme.COLORS.gold) .. " " .. concat(parts, " · ")
end

-- Whether `entry` was built from `lead` as it is now; the customer's class colours the chat line
-- and may only be known later.
local function isCurrent(entry, lead, class)
  if entry == nil or entry.lead ~= lead or entry.class ~= class then
    return false
  end
  for _, field in ipairs(FEEDS) do
    if entry[field] ~= lead[field] then
      return false
    end
  end
  return true
end

-- The customer's line and lines for `lead`, from the last build while it is current.
local function entryFor(customer, lead)
  local class = FlavorCompat.ClassOf(lead.guid)
  local entry = built[customer]
  if isCurrent(entry, lead, class) then
    return entry
  end
  entry = { lead = lead, class = class, text = infoText(lead), lines = CardTipText.InfoLines(lead) }
  for _, field in ipairs(FEEDS) do
    entry[field] = lead[field]
  end
  entry.joined = entry.text .. "\n" .. concat(entry.lines, "\n")
  built[customer] = entry
  return entry
end

-- Each customer's newest lead (Leads.List is newest first).
local function newestByCustomer()
  local newest = {}
  for _, lead in ipairs(Leads.List()) do
    if newest[lead.customer] == nil then
      newest[lead.customer] = lead
    end
  end
  return newest
end

-- A line goes out only when its text or a tooltip line changed; a customer without an active lead
-- loses theirs. Only what WM accepted counts as sent, so a refused line or removal is tried again
-- on the next sync. send(customer, text, lines) → whether WM accepted; text nil removes.
function BridgeInfo.Sync(send)
  local newest = newestByCustomer()
  for customer, lead in pairs(newest) do
    local entry = entryFor(customer, lead)
    if sent[customer] ~= entry.joined and send(customer, entry.text, entry.lines) then
      sent[customer] = entry.joined
    end
  end
  for customer in pairs(built) do
    if newest[customer] == nil then
      built[customer] = nil
    end
  end
  for customer in pairs(sent) do
    if newest[customer] == nil and send(customer, nil, nil) then
      sent[customer] = nil
    end
  end
end

ns.BridgeInfo = BridgeInfo
return BridgeInfo
