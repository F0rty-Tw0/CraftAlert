local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local LeadText = ns.LeadText or require("CraftAlert.UI.LeadText")
local ClickRouter = ns.ClickRouter or require("CraftAlert.UI.ClickRouter")

-- Spec §7.1: the one alert toast. Created on the first alert (§4.4 rule 5) as frame
-- CraftAlertToast; draggable, clamped, position saved in CraftAlertDB.ui.toast. A newer lead
-- replaces the shown one and the "+N more" badge counts the leads it replaced; the toast hides
-- after the toast duration (one pending timer, §4.3 rule 1) or when its lead leaves the list.
local AlertToast = {}

-- The "+N more" count on the shown toast: leads it replaced since it appeared (0 when hidden).
AlertToast.more = 0

local concat = table.concat
local match = string.match
local type = type

local FRAME_NAME = "CraftAlertToast"
local UI_KEY = "toast"
local FALLBACK_POSITION = { "TOP", 0, -160 }
local SOUND_CHANNEL = "Master"
local LINE_GAP = 3

---@type table
local toast = nil -- { frame, name, badge, message, what, detail }, nil until the first alert
local current = { lead = nil, shownAt = nil }
local hideAt = 0
local timerPending = false

local function now()
  return _G["GetTime"]()
end

local function settings()
  return _G["CraftAlertDB"].settings
end

local function trim(text)
  return match(text or "", "^%s*(.-)%s*$")
end

-- Crafter, why, and the realm tag (§7.2) on one line.
local function detailText(lead)
  local parts = { LeadText.Crafter(lead) }
  if lead.why and lead.why ~= "" then
    parts[#parts + 1] = lead.why
  end
  parts[#parts + 1] = LeadText.RealmTag(lead)
  return concat(parts, " · ")
end

local function badgeText()
  if current.lead and current.lead.test then
    if AlertToast.more > 0 then
      return Localization.Text("Test · +%d more", AlertToast.more)
    end
    return Localization.Text("Test")
  end
  if AlertToast.more > 0 then
    return Localization.Text("+%d more", AlertToast.more)
  end
  return ""
end

local function render(lead)
  toast.name:SetText(tostring(lead.customer))
  FrameKit.PaintName(toast.name, lead.guid)
  toast.badge:SetText(badgeText())
  toast.message:SetText(trim(lead.message))
  toast.what:SetText(LeadText.What(lead))
  toast.detail:SetText(detailText(lead))
  toast.frame:SetAlpha(settings().opacity or 1)
  toast.frame:Show()
end

local function hide()
  current.lead, current.shownAt = nil, nil
  AlertToast.more = 0
  toast.frame:Hide()
end

local armHide

local function onHideTimer()
  timerPending = false
  if toast.frame:IsShown() then
    armHide()
  end
end

-- One pending timer: it fires at the deadline set by the latest alert, or re-arms for the rest.
armHide = function()
  if timerPending then
    return
  end
  local remaining = hideAt - now()
  if remaining <= 0 then
    hide()
    return
  end
  timerPending = true
  _G["C_Timer"].After(remaining, onHideTimer)
end

local function startHideTimer()
  hideAt = now() + (settings().toastDuration or 20)
  armHide()
end

local function onClick(_, button)
  if ClickRouter.Handle(button, current.lead, current.shownAt) then
    hide()
  end
end

-- On screen again (UIParent back after Alt+Z): the lead counts as shown from now, so the time
-- under the hidden UI is no look (§7.5 rule 3).
local function onShow()
  if current.lead then
    current.shownAt = now()
  end
end

-- Hides the toast once its lead is dismissed, ignored or expired.
local function onLeadsChange()
  local lead = current.lead
  if lead and not Leads.IsActive(lead.id) then
    hide()
  end
end

local function line(frame, font, color, anchor)
  local text = FrameKit.Text(frame, font, color)
  text:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -LINE_GAP)
  text:SetPoint("RIGHT", frame, "RIGHT", -Theme.LAYOUT.PADDING, 0)
  return text
end

local function create()
  local layout, colors, fonts = Theme.LAYOUT, Theme.COLORS, Theme.FONTS
  local frame = _G["CreateFrame"]("Button", FRAME_NAME, _G["UIParent"])
  frame:SetSize(layout.TOAST_WIDTH, layout.TOAST_HEIGHT)
  frame:SetFrameStrata("DIALOG")
  FrameKit.Panel(frame)
  FrameKit.Draggable(frame, UI_KEY)
  FrameKit.Place(frame, UI_KEY, FALLBACK_POSITION)
  frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  frame:SetScript("OnClick", onClick)
  frame:SetScript("OnShow", onShow)
  local name = FrameKit.Text(frame, fonts.name)
  name:SetPoint("TOPLEFT", frame, "TOPLEFT", layout.PADDING, -layout.PADDING)
  local badge = FrameKit.Text(frame, fonts.badge, colors.accent)
  badge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -layout.PADDING, -layout.PADDING)
  badge:SetJustifyH("RIGHT")
  name:SetPoint("RIGHT", badge, "LEFT", -layout.PADDING, 0)
  local message = line(frame, fonts.body, colors.textPrimary, name)
  local what = line(frame, fonts.body, colors.textPrimary, message)
  local detail = line(frame, fonts.detail, colors.textSecondary, what)
  frame:Hide()
  Leads.On("change", onLeadsChange)
  return { frame = frame, name = name, badge = badge, message = message, what = what, detail = detail }
end

local function alert()
  local values = settings()
  local playSound = _G["PlaySound"]
  if values.sound ~= 0 and type(playSound) == "function" then
    playSound(values.sound, SOUND_CHANNEL)
  end
  local flash = _G["FlashClientIcon"]
  if values.flash and type(flash) == "function" then
    flash()
  end
end

-- A new lead (Leads.On("new"), wired by Bootstrap): show it, sound, flash.
function AlertToast.Show(lead)
  toast = toast or create()
  local replacing = toast.frame:IsShown() and current.lead ~= nil and current.lead ~= lead
  AlertToast.more = replacing and AlertToast.more + 1 or 0
  current.lead, current.shownAt = lead, now()
  render(lead)
  alert()
  startHideTimer()
end

-- The lead on the toast and GetTime() when it appeared, or nil (hidden, also by Alt+Z, test
-- lead gone). IsVisible, not IsShown: a toast under a hidden UIParent stays shown.
function AlertToast.VisibleLead()
  local lead = current.lead
  if toast == nil or not toast.frame:IsVisible() or lead == nil or not Leads.IsActive(lead.id) then
    return nil
  end
  return lead, current.shownAt
end

ns.AlertToast = AlertToast
return AlertToast
