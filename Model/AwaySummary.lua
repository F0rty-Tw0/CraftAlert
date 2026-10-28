local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local EventRouter = ns.EventRouter or require("CraftAlert.Core.EventRouter")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")

-- Spec §7.6 "Away summary" and plan revision R5c: the leads made while the player was AFK
-- (`lead.arrivedWhileAfk`, set by Leads; `/ca test` leads never count) are kept for one AFK period.
-- When the player's AFK flag clears, one summary shows how many there were and how many of them
-- expired (gone from the list without the player dismissing them), then the period starts over.
-- A secret flag waits for a readable one; in an instance the period ends with nothing shown.
local AwaySummary = {}

local pairs = pairs

local EVENT = "PLAYER_FLAGS_CHANGED"

local period = {} -- id → lead, this AFK period's leads
local count = 0
---@type function
local show = nil

local function onNew(lead)
  if lead.arrivedWhileAfk and not lead.test then
    period[lead.id] = lead
    count = count + 1
  end
end

local function expiredCount()
  local expired = 0
  for id, lead in pairs(period) do
    -- A lead the MAX_LEADS cap pushed out counts too: it left without the player acting.
    if not lead.dismissed and not Leads.IsActive(id) then
      expired = expired + 1
    end
  end
  return expired
end

-- (unit). Only the player's own flags; nothing while the AFK flag is set, secret or not a boolean,
-- nor on a client without UnitIsAFK.
local function onFlagsChanged(unit)
  if FlavorCompat.issecretvalue(unit) or unit ~= "player" or count == 0 then
    return
  end
  if FlavorCompat.IsAfk() ~= false then
    return
  end
  local total, expired = count, expiredCount()
  period, count = {}, 0
  if not FlavorCompat.InInstance() then
    show(total, expired)
  end
end

-- "4 requests you could craft while you were away (1 expired)", "1 request …" for one, the
-- expired part only when > 0.
function AwaySummary.Text(total, expired)
  local text = Localization.Plural(total, "%d request you could craft while you were away", "%d requests you could craft while you were away")
  if expired > 0 then
    text = text .. Localization.Text(" (%d expired)", expired)
  end
  return text
end

-- Bootstrap, at PLAYER_LOGIN. `display(count, expired)` shows the summary: WhisperMessenger's
-- preview when bridged, else the own toast.
function AwaySummary.Install(display)
  show = display
  Leads.On("new", onNew)
  EventRouter.On(EVENT, onFlagsChanged)
end

ns.AwaySummary = AwaySummary
return AwaySummary
