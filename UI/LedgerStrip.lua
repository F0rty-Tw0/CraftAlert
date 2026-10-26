local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Ledger = ns.Ledger or require("CraftAlert.Model.Ledger")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local Tooltip = ns.Tooltip or require("CraftAlert.UI.Tooltip")

-- Spec §8, plan revision R5a/R5b: the ledger line at the top of the split view (UI/LeadsView.lua
-- builds it, so the leads window and WhisperMessenger's panel share it): today's counters, with
-- `filled` on Retail only (no crafting orders elsewhere), and the last 7 days in its tooltip. Every
-- Ledger.Add repaints the shown strips: a fill fires no leads "change". Hidden in an instance.
local LedgerStrip = {}

local WEEK = 7

local strips = {} -- every strip made, at most one per host
local subscribed = false

-- `label`: "Today", or a day key. → the counters as one line.
local function line(label, counters)
  if FlavorCompat.isRetail then
    return Localization.Text(
      "%s: %d seen · %d greeted · %d replied · %d filled",
      label,
      counters.seen,
      counters.greeted,
      counters.replied,
      counters.filled
    )
  end
  return Localization.Text("%s: %d seen · %d greeted · %d replied", label, counters.seen, counters.greeted, counters.replied)
end

local function today()
  return Localization.Text("Today")
end

-- Blizzard's tooltip hierarchy: gold title, one white line per day, today first.
local function showTooltip(strip)
  local tooltip = Tooltip.Get()
  tooltip:SetOwner(strip, "ANCHOR_BOTTOM")
  _G["GameTooltip_SetTitle"](tooltip, Localization.Text("Last 7 days"), _G["NORMAL_FONT_COLOR"])
  for i, counters in ipairs(Ledger.LastDays(WEEK)) do
    _G["GameTooltip_AddHighlightLine"](tooltip, line(i == 1 and today() or counters.day, counters))
  end
  tooltip:Show()
end

-- Re-reads today's counters; hides the strip in an instance.
function LedgerStrip.Refresh(strip)
  if FlavorCompat.InInstance() then
    strip:Hide()
    return
  end
  strip.text:SetText(line(today(), Ledger.Today()))
  strip:Show()
end

local function refreshAll()
  for _, strip in ipairs(strips) do
    if strip:IsVisible() then
      LedgerStrip.Refresh(strip)
    end
  end
end

-- The strip across the top of `host`, Theme.LAYOUT.LEDGER_HEIGHT tall, a child of `parent` (the
-- view's root, so it hides with the view while the settings show).
function LedgerStrip.New(parent, host)
  local layout = Theme.LAYOUT
  local strip = _G["CreateFrame"]("Frame", nil, parent)
  strip:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
  strip:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
  strip:SetHeight(layout.LEDGER_HEIGHT)
  strip:EnableMouse(true)
  strip:SetScript("OnEnter", showTooltip)
  strip:SetScript("OnLeave", Tooltip.HideIfOwned)
  strip.text = FrameKit.Text(strip, Theme.FONTS.body, Theme.COLORS.textSecondary)
  strip.text:SetPoint("LEFT", strip, "LEFT", layout.PADDING, 0)
  strips[#strips + 1] = strip
  if not subscribed then
    subscribed = true
    Ledger.OnChange(refreshAll)
  end
  return strip
end

ns.LedgerStrip = LedgerStrip
return LedgerStrip
