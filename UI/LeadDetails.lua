local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local GreetAction = ns.GreetAction or require("CraftAlert.Model.GreetAction")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local ClickRouter = ns.ClickRouter or require("CraftAlert.UI.ClickRouter")
local Tooltip = ns.Tooltip or require("CraftAlert.UI.Tooltip")
local LinkHover = ns.LinkHover or require("CraftAlert.UI.LinkHover")
local CardTipText = ns.CardTipText or require("CraftAlert.UI.CardTipText")
local DetailsHeader = ns.DetailsHeader or require("CraftAlert.UI.DetailsHeader")
local DetailsBody = ns.DetailsBody or require("CraftAlert.UI.DetailsBody")
local ScrollView = ns.ScrollView or require("CraftAlert.UI.ScrollView")

-- Spec A.4: the split view's details pane, the selected lead in full. The header and the info
-- strip under it (UI/DetailsHeader.lua, details spec A.1-A.2), the body (UI/DetailsBody.lua,
-- details spec A.3-A.5), and an action bar with Greet, Whisper and Dismiss. Between the strip and
-- the bar the body scrolls (scroll bars spec §4, UI/ScrollView.lua), as tall as what it shows and
-- back to its top for each new lead. The strip, the body and the body's two bubbles each hover
-- their links (LinkHover); tooltip zones lie over the customer and, while it holds no link, the
-- strip. The pane carries the GetTime() at which its lead became the shown one, and the buttons
-- run the look rule on it (§7.5 rule 3).
local LeadDetails = {}

local min = math.min

local ANCHOR = "ANCHOR_RIGHT"
-- Action bar buttons: Greet and Whisper from the left, Dismiss at the right edge, BUTTON_GAP
-- apart, at most BUTTON_WIDTH wide (spec A.4 small hosts).
local BUTTON_GAP, BUTTON_WIDTH, BUTTON_HEIGHT = 8, 100, 22

-- Left to right: each button's key in details.buttons, its label, what it does to the shown lead,
-- read at click time, and its tooltip for that lead, read at hover time. Greet and Dismiss act as
-- a left and a right click, look rule included.
local ACTIONS = {
  {
    key = "greet",
    label = "Greet",
    run = function(details)
      ClickRouter.Handle("LeftButton", details.lead, details.shownAt)
    end,
    tip = CardTipText.Greet,
  },
  {
    key = "whisper",
    label = "Whisper",
    run = function(details)
      GreetAction.Empty(details.lead)
    end,
    tip = CardTipText.Whisper,
  },
  {
    key = "dismiss",
    label = "Dismiss",
    run = function(details)
      ClickRouter.Handle("RightButton", details.lead, details.shownAt)
    end,
    tip = CardTipText.Dismiss,
  },
}

local function now()
  return _G["GetTime"]()
end

-- Forgets the hovered link of the strip, the body and its bubbles, and hides a tooltip any of the
-- pane's frames owns.
local function hideOwned(details)
  LinkHover.Clear(details.strip)
  LinkHover.Clear(details.body)
  for _, bubble in pairs(details.sections.bubbles) do
    LinkHover.Clear(bubble)
  end
  for _, children in ipairs({ details.zones, details.buttons }) do
    for _, child in pairs(children) do
      Tooltip.HideIfOwned(child)
    end
  end
end

local function createButton(details, action, previous)
  local button = _G["CreateFrame"]("Button", nil, details.bar, "UIPanelButtonTemplate")
  button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
  if action.key == "dismiss" then
    button:SetPoint("RIGHT", details.bar, "RIGHT", -Theme.LAYOUT.DETAILS_PADDING, 0)
  elseif previous then
    button:SetPoint("LEFT", previous, "RIGHT", BUTTON_GAP, 0)
  else
    button:SetPoint("LEFT", details.bar, "LEFT", Theme.LAYOUT.DETAILS_PADDING, 0)
  end
  button:SetText(Localization.Text(action.label))
  button:RegisterForClicks("LeftButtonUp")
  button:SetScript("OnClick", function()
    if details.lead then
      action.run(details)
    end
  end)
  local function showTip()
    local tip = Tooltip.Get()
    tip:SetOwner(button, ANCHOR)
    action.tip(tip, details.lead)
    tip:Show()
  end
  button:HookScript("OnEnter", showTip)
  button:HookScript("OnLeave", Tooltip.HideIfOwned)
  return button
end

local function createBar(details)
  local bar = _G["CreateFrame"]("Frame", nil, details.frame)
  bar:SetHeight(Theme.LAYOUT.ACTION_BAR_HEIGHT)
  bar:SetPoint("BOTTOMLEFT", details.frame, "BOTTOMLEFT", 0, 0)
  bar:SetPoint("BOTTOMRIGHT", details.frame, "BOTTOMRIGHT", 0, 0)
  details.bar = bar
  details.buttons = {}
  local previous
  for _, action in ipairs(ACTIONS) do
    previous = createButton(details, action, previous)
    details.buttons[action.key] = previous
  end
end

-- On screen again (the window reopened, UIParent back after Alt+Z): the lead counts as shown from
-- now, so the time under the hidden UI is no look (§7.5 rule 3).
local function onShow(details)
  if details.lead then
    details.shownAt = now()
  end
end

-- The pane inside `parent`, covering it, empty until Show.
function LeadDetails.New(parent)
  local details = { width = 0, rightInset = Theme.LAYOUT.DETAILS_PADDING }
  local frame = _G["CreateFrame"]("Frame", nil, parent)
  frame:SetAllPoints(parent)
  details.frame = frame
  DetailsHeader.Create(details)
  createBar(details)
  -- The box spans the pane between the strip and the action bar, less PANE_PADDING on the right
  -- for the scroll bar; the body, as tall as what it shows (0 until the first paint), scrolls in it.
  local box = _G["CreateFrame"]("Frame", nil, frame)
  box:SetPoint("TOPLEFT", details.strip, "BOTTOMLEFT", 0, 0)
  box:SetPoint("BOTTOMRIGHT", details.bar, "TOPRIGHT", -Theme.LAYOUT.PANE_PADDING, 0)
  local body = _G["CreateFrame"]("Button", nil, frame)
  body:SetClipsChildren(true)
  body:SetHeight(0)
  LinkHover.Attach(body, nil)
  details.body = body
  details.sections = DetailsBody.Create(body)
  details.scroll = ScrollView.Create(box, body)
  details.zones = {
    name = DetailsBody.Zone(details, details.header, details.name, details.name, CardTipText.Customer),
    what = DetailsBody.Zone(details, details.strip, details.strip, details.strip, CardTipText.What),
    matched = details.sections.zones.matched,
    crafters = details.sections.zones.crafters,
  }
  frame:SetScript("OnShow", function()
    onShow(details)
  end)
  frame:SetScript("OnHide", function()
    hideOwned(details)
  end)
  frame:Hide()
  return details
end

-- Shows `lead`; one other than the shown lead counts as shown from now, takes down the tooltip
-- the pane's frames own and starts at the body's top. The same lead repainted (edited in place)
-- keeps its time and its place.
function LeadDetails.Show(details, lead)
  if details.lead ~= lead then
    details.shownAt = now()
    hideOwned(details)
    ScrollView.ScrollTo(details.scroll, 0)
  end
  details.lead = lead
  DetailsHeader.Paint(details, lead)
  DetailsBody.Paint(details.sections, lead)
  details.zones.what:SetShown(lead.itemLink == nil)
  details.frame:Show()
end

function LeadDetails.Clear(details)
  details.lead, details.shownAt, details.sections.lead = nil, nil, nil
  details.frame:Hide()
end

-- The header's name and lines end `inset` before its right edge (default: the padding), for a
-- host that puts something over the header's right, e.g. a gear.
function LeadDetails.SetRightInset(details, inset)
  details.rightInset = inset
  for _, line in ipairs({ details.lineOne, details.lineTwo }) do
    line:SetPoint("RIGHT", details.header, "RIGHT", -inset, 0)
  end
  DetailsHeader.FitName(details)
end

-- The pane is `width` wide (0 or less: not known yet): the three buttons share it, up to
-- BUTTON_WIDTH each, the header's name is cut to fit, and the body (the pane less the box's
-- right inset and the scroll bar) re-wraps its bubbles and re-measures its height.
function LeadDetails.Layout(details, width)
  details.width = width
  DetailsHeader.FitName(details)
  DetailsHeader.FitStrip(details)
  local bodyWidth = width > 0 and width - Theme.LAYOUT.PANE_PADDING - details.scroll.bar:GetWidth() or 0
  DetailsBody.SetWidth(details.sections, bodyWidth)
  local room = Theme.LAYOUT.DETAILS_PADDING * 2 + BUTTON_GAP * (#ACTIONS - 1)
  local buttonWidth = width > 0 and min(BUTTON_WIDTH, (width - room) / #ACTIONS) or BUTTON_WIDTH
  for _, button in pairs(details.buttons) do
    button:SetWidth(buttonWidth)
  end
end

ns.LeadDetails = LeadDetails
return LeadDetails
