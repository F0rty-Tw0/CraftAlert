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

local strips = {} -- host → the strip last made on it; a rebuilt view replaces its host's strip
local subscribed = false

local SECONDS_PER_DAY = 24 * 60 * 60
local NOON = 12 * 60 * 60
-- Inline colour codes: a code replaces the FontString's rgb, never its alpha, so the strip's base
-- colour is the opaque Theme grey.
local GOLD_CODE = "|cffffd100"
local WHITE_CODE = "|cffffffff"
local CODE_END = "|r"
local SEPARATOR = " · "

-- The counters this flavor shows, in order: `filled` on Retail only (no crafting orders
-- elsewhere). → { { count, word } ... }.
local function parts(counters)
  local shown = {
    { counters.seen, Localization.Text("seen") },
    { counters.greeted, Localization.Text("greeted") },
    { counters.replied, Localization.Text("replied") },
  }
  if FlavorCompat.isRetail then
    shown[#shown + 1] = { counters.filled, Localization.Text("filled") }
  end
  return shown
end

-- "3 seen · 2 filled"; skipZeros leaves out the zero counters. → the line, or "" when none is left.
local function plainLine(counters, skipZeros)
  local words = {}
  for _, part in ipairs(parts(counters)) do
    if part[1] ~= 0 or not skipZeros then
      words[#words + 1] = Localization.Text("%d %s", part[1], part[2])
    end
  end
  return table.concat(words, SEPARATOR)
end

-- Gold "Today", then every counter with its non-zero numbers in white.
local function stripLine(counters)
  local words = {}
  for _, part in ipairs(parts(counters)) do
    local count = part[1] == 0 and "0" or WHITE_CODE .. part[1] .. CODE_END
    words[#words + 1] = count .. " " .. part[2]
  end
  return GOLD_CODE .. Localization.Text("Today") .. CODE_END .. "  " .. table.concat(words, SEPARATOR)
end

-- Row `i` (1 = today): "Today", "Yesterday", then "Sun 25 Oct". Stepped from today's noon, as
-- Ledger.LastDays steps its day keys, so the label and the counters name the same day.
local function dayLabel(i, todayNoon)
  if i == 1 then
    return Localization.Text("Today")
  elseif i == 2 then
    return Localization.Text("Yesterday")
  end
  local date = _G["date"]
  local at = todayNoon - (i - 1) * SECONDS_PER_DAY
  -- date("*t").day: MSVC's strftime (WoW on Windows) has no %e or %-d for an unpadded day.
  return Localization.Text("%s %d %s", date("%a", at), date("*t", at).day, date("%b", at))
end

local function todayNoon()
  local current = _G["time"]()
  local clock = _G["date"]("*t", current)
  return current - (clock.hour * 3600 + clock.min * 60 + clock.sec) + NOON
end

-- Blizzard's tooltip hierarchy: gold title, one unwrapped row per day (today first) with its
-- non-zero counters or a grey "no leads", a blank line, then the gold week line.
local function showTooltip(strip)
  local tooltip = Tooltip.Get()
  local gold, grey = _G["NORMAL_FONT_COLOR"], Theme.COLORS.grey
  tooltip:SetOwner(strip, "ANCHOR_BOTTOM")
  _G["GameTooltip_SetTitle"](tooltip, Localization.Text("Last 7 days"), gold)
  local noon = todayNoon()
  local week = { seen = 0, greeted = 0, replied = 0, filled = 0 }
  for i, counters in ipairs(Ledger.LastDays(WEEK)) do
    for field in pairs(week) do
      week[field] = week[field] + counters[field]
    end
    local line = plainLine(counters, true)
    if line == "" then
      tooltip:AddDoubleLine(dayLabel(i, noon), Localization.Text("no leads"), 1, 1, 1, grey[1], grey[2], grey[3])
    else
      tooltip:AddDoubleLine(dayLabel(i, noon), line, 1, 1, 1, 1, 1, 1)
    end
  end
  _G["GameTooltip_AddBlankLineToTooltip"](tooltip)
  local goldR, goldG, goldB = gold:GetRGB()
  tooltip:AddDoubleLine(Localization.Text("Week"), plainLine(week, false), goldR, goldG, goldB, 1, 1, 1)
  tooltip:Show()
end

-- Re-reads today's counters; hides the strip in an instance.
function LedgerStrip.Refresh(strip)
  if FlavorCompat.InInstance() then
    strip:Hide()
    return
  end
  strip.text:SetText(stripLine(Ledger.Today()))
  strip:Show()
end

local function refreshAll()
  for _, strip in pairs(strips) do
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
  strip.text = FrameKit.Text(strip, Theme.FONTS.body, Theme.COLORS.grey)
  -- Both sides, one line (FrameKit.Text turns word wrap off): a narrow host cuts the text short.
  strip.text:SetPoint("LEFT", strip, "LEFT", layout.PADDING, 0)
  strip.text:SetPoint("RIGHT", strip, "RIGHT", -layout.PADDING, 0)
  strips[host] = strip
  if not subscribed then
    subscribed = true
    Ledger.OnChange(refreshAll)
  end
  return strip
end

-- Ends the strip text `inset` px before the strip's right, clear of a control placed there.
function LedgerStrip.SetRightInset(strip, inset)
  local layout = Theme.LAYOUT
  strip.text:ClearAllPoints()
  strip.text:SetPoint("LEFT", strip, "LEFT", layout.PADDING, 0)
  strip.text:SetPoint("RIGHT", strip, "RIGHT", -inset, 0)
end

ns.LedgerStrip = LedgerStrip
return LedgerStrip
