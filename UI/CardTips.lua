local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local CardTipText = ns.CardTipText or require("CraftAlert.UI.CardTipText")
local CardHover = ns.CardHover or require("CraftAlert.UI.CardHover")

-- Lead-cards spec §2, §2.1: when a card's tooltips show (UI/CardTipText.lua says what they hold).
-- Mouse-enabled zones lie over its customer, what line, Matched row and Crafters row; the Greet button
-- has one; the latest chat line shows while the cursor is on the bare card (ShowChat). A zone has no
-- text of its own and forwards clicks to the card, so a click anywhere on it greets or dismisses. No
-- zone covers the Request text or a link in the what line: LinkHover shows those item tooltips. No
-- OnUpdate: every tooltip starts from an Enter or from the cursor leaving a link.
local CardTips = {}

local ANCHOR = "ANCHOR_RIGHT"

local function tooltip()
  return _G["GameTooltip"]
end

-- `build(tip, lead)` fills the tooltip; the lead is read when the cursor comes, not before.
local function showZoneTip(card, zone, build)
  local lead = card.lead
  if lead == nil then
    return
  end
  local tip = tooltip()
  tip:SetOwner(zone, ANCHOR)
  build(tip, lead)
  tip:Show()
end

local function hideIfOwned(frame)
  local tip = tooltip()
  if tip:IsOwned(frame) then
    tip:Hide()
  end
end

-- Hides the tooltip when one of the card's zones, buttons or the card itself owns it.
local function hideOwned(card)
  hideIfOwned(card)
  for _, children in ipairs({ card.zones, card.buttons }) do
    for _, child in pairs(children) do
      hideIfOwned(child)
    end
  end
end

-- True while the cursor is on a link in the card or on one of its shown zones or buttons: those own
-- the tooltip there. The client may send the card's OnLeave and a zone's OnEnter before a link's
-- OnHyperlinkLeave, and card:IsMouseOver() stays true over a child.
local function onLinkOrChild(card)
  if card.hoveredLink ~= nil then
    return true
  end
  for _, children in ipairs({ card.zones, card.buttons }) do
    for _, child in pairs(children) do
      if child:IsShown() and child:IsMouseOver() then
        return true
      end
    end
  end
  return false
end

-- A mouse-enabled Button over `first` through `last` (card regions); clicks go to the card's OnClick.
local function createZone(card, first, last, build)
  local zone = _G["CreateFrame"]("Button", nil, card)
  if first == last then
    zone:SetAllPoints(first)
  else
    zone:SetPoint("TOPLEFT", first, "TOPLEFT", 0, 0)
    zone:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", 0, 0)
  end
  zone:EnableMouse(true)
  zone:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  zone:SetScript("OnClick", function(_, button)
    card:GetScript("OnClick")(card, button)
  end)
  zone:SetScript("OnEnter", function()
    CardHover.Enter(card)
    showZoneTip(card, zone, build)
  end)
  zone:SetScript("OnLeave", function()
    hideIfOwned(zone)
    CardHover.Leave(card)
  end)
  return zone
end

-- Spec §2.1: the lead's latest chat line, owned by the card. Shown when the cursor comes onto the card
-- itself (OnEnter, also when it comes back from a zone or a button) and when it leaves a link onto the
-- card (LinkHover's body hook); nothing shows for a lead without a message, nor while the cursor is
-- on a link, a zone or a button.
function CardTips.ShowChat(card)
  local lead = card.lead
  if lead == nil or lead.message == nil or onLinkOrChild(card) then
    return
  end
  local tip = tooltip()
  tip:SetOwner(card, ANCHOR)
  CardTipText.Chat(tip, lead)
  tip:Show()
  card.chatTip = { time = lead.time, message = lead.message }
end

-- Adds the four zones (card.zones), the Greet button's tooltip and the chat tooltip's OnEnter to a card;
-- CardHover.Attach has made the buttons already. The card's OnLeave hides a tooltip it owns (LinkHover.Clear).
function CardTips.Attach(card)
  card.zones = {
    name = createZone(card, card.name, card.name, CardTipText.Customer),
    what = createZone(card, card.what, card.what, CardTipText.What),
    matched = createZone(card, card.labels.matched, card.values.matched, CardTipText.Matched),
    crafters = createZone(card, card.labels.crafters, card.values.crafters, CardTipText.Crafters),
  }
  local greet = card.buttons.greet
  greet:HookScript("OnEnter", function()
    local tip = tooltip()
    tip:SetOwner(greet, ANCHOR)
    CardTipText.Greet(tip)
    tip:Show()
  end)
  greet:HookScript("OnLeave", function()
    hideIfOwned(greet)
  end)
  card:HookScript("OnEnter", CardTips.ShowChat)
  card:HookScript("OnHide", hideOwned)
end

-- True while the card shows its chat tooltip (not a link's) for a line older than the lead's newest.
local function chatTipStale(card)
  local lead, shown = card.lead, card.chatTip
  local tip = tooltip()
  local showing = shown ~= nil and card.hoveredLink == nil and tip:IsShown() and tip:IsOwned(card)
  return showing and (shown.time ~= lead.time or shown.message ~= lead.message)
end

-- After the card shows a lead: a new lead takes down the tooltip any of the card's frames owns; the
-- same lead repeated (edited in place) rebuilds a chat tooltip that shows; the what zone yields to an
-- item link, and the Matched zone goes with its row.
function CardTips.Refresh(card, leadChanged)
  if leadChanged then
    hideOwned(card)
    card.chatTip = nil
  elseif chatTipStale(card) then
    CardTips.ShowChat(card)
  end
  card.zones.what:SetShown(card.lead.itemLink == nil)
  card.zones.matched:SetShown(card.values.matched:IsShown())
end

ns.CardTips = CardTips
return CardTips
