local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local AwaySummary = ns.AwaySummary or require("CraftAlert.Model.AwaySummary")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local Tooltip = ns.Tooltip or require("CraftAlert.UI.Tooltip")
local LeadText = ns.LeadText or require("CraftAlert.UI.LeadText")
local ClickRouter = ns.ClickRouter or require("CraftAlert.UI.ClickRouter")
local LinkHover = ns.LinkHover or require("CraftAlert.UI.LinkHover")
local Dock = ns.Dock or require("CraftAlert.UI.Dock")
local Launcher = ns.Launcher or require("CraftAlert.UI.Launcher")
local LeadsWindow = ns.LeadsWindow or require("CraftAlert.UI.LeadsWindow")
local ToastLayout = ns.ToastLayout or require("CraftAlert.UI.ToastLayout")
local ToastChrome = ns.ToastChrome or require("CraftAlert.UI.ToastChrome")

-- Design spec §7.1 and native-HUD spec §4: the one alert toast. Created on the first alert
-- (design spec §4.4 rule 5) as frame CraftAlertToast, a native tooltip-backdrop panel docked
-- beside the launcher (UI/Dock.lua); dragging it moves the launcher, so it keeps no position of
-- its own. A newer lead replaces the shown one and the "+N more" badge counts the leads it
-- replaced; the toast hides after the toast duration (UI/ToastChrome.lua) or when its lead
-- leaves the list.
local AlertToast = {}

-- The "+N more" count on the shown toast: leads it replaced since it appeared (0 when hidden).
AlertToast.more = 0

local concat = table.concat
local match = string.match
local tostring = tostring
local type = type

local FRAME_NAME = "CraftAlertToast"
local NO_LAUNCHER_POSITION = { "TOP", 0, -160 }
local SOUND_CHANNEL = "Master"

---@type table
local toast = nil -- { frame, parts = ToastLayout.Build(frame) }, nil until the first alert
local current = { lead = nil, shownAt = nil, summary = false } -- summary: the away summary shows

local function now()
  return _G["GetTime"]()
end

local function settings()
  return _G["CraftAlertDB"].settings
end

local function trim(text)
  return match(text or "", "^%s*(.-)%s*$")
end

-- The rank and the realm tag (quality-rank spec §4.5, design spec §7.2), whichever the lead
-- has, or "".
local function detailText(lead)
  local parts = {}
  parts[#parts + 1] = LeadText.Rank(lead)
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

local function showDetail(detail, text)
  detail:SetText(text)
  if text == "" then
    detail:Hide()
  else
    detail:Show()
  end
end

-- The face: `name` in its class colour (by `guid`, plain without), the badge, then the lines.
local function paint(name, guid, headline, detail, message)
  local frame, parts = toast.frame, toast.parts
  parts.name:SetText(name)
  FrameKit.PaintName(parts.name, guid)
  parts.badge:SetText(badgeText())
  parts.headline:SetText(headline)
  showDetail(parts.detail, detail)
  parts.message:SetText(message)
  LinkHover.Clear(frame)
  ToastLayout.Fit(frame, parts, detail ~= "")
  frame:SetAlpha(settings().opacity or 1)
  frame:Show()
  AlertToast.Dock()
end

local function render(lead)
  paint(tostring(lead.customer), lead.guid, LeadText.Headline(lead), detailText(lead), trim(lead.message))
end

local function hide()
  current.lead, current.shownAt, current.summary = nil, nil, false
  AlertToast.more = 0
  toast.frame:Hide()
  Launcher.ShowLead(nil)
end

-- What matched (lead.why, never drawn on the face) and the clicks; the summary's own clicks.
local function showTooltip(frame)
  if current.summary then
    local clicks = { Localization.Text("Left-click: open the leads"), Localization.Text("Right-click: dismiss") }
    ToastChrome.ShowTooltip(frame, nil, clicks)
    return
  end
  local why = current.lead and current.lead.why
  local matched = type(why) == "string" and why ~= "" and Localization.Text("Matched: %s", why) or nil
  ToastChrome.ShowTooltip(frame, matched, LeadText.ClickLines())
end

-- A click on a link inside the message belongs to the link (LinkHover), never to the lead.
local function onClick(frame, button)
  local overLink = LinkHover.IsOverLink(frame)
  if overLink then
    return
  end
  if current.summary then
    local action = ClickRouter.Summary(button)
    if action then
      hide()
    end
    if action == "open" then
      LeadsWindow.Open()
    end
    return
  end
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

-- Hides the toast once its lead is dismissed, ignored or expired; else re-docks a shown toast.
-- Bootstrap subscribes Launcher.Refresh to "change" before the first alert subscribes this, so a
-- launcher that "Hide when no leads" kept hidden (no centre when the toast docked) is shown by now.
local function onLeadsChange()
  local lead = current.lead
  if lead and not Leads.IsActive(lead.id) then
    hide()
    return
  end
  local frame, parts = toast.frame, toast.parts
  if lead and frame:IsShown() then
    -- The item link can arrive after the alert (Leads waits for the client's item cache).
    parts.headline:SetText(LeadText.Headline(lead))
    ToastLayout.Fit(frame, parts, parts.detail:IsShown())
    AlertToast.Dock()
  end
end

-- The scripts go on before LinkHover.Attach, which hooks OnLeave and OnHide.
local function create()
  local frame = _G["CreateFrame"]("Button", FRAME_NAME, _G["UIParent"], "TooltipBackdropTemplate")
  frame:SetWidth(Theme.LAYOUT.TOAST_WIDTH)
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  frame:SetScript("OnEnter", showTooltip)
  frame:SetScript("OnLeave", Tooltip.HideIfOwned)
  frame:SetScript("OnClick", onClick)
  frame:SetScript("OnShow", onShow)
  frame:SetScript("OnDragStart", Launcher.StartDrag)
  frame:SetScript("OnDragStop", Launcher.StopDrag)
  LinkHover.Attach(frame, showTooltip)
  local parts = ToastLayout.Build(frame)
  frame:Hide()
  Leads.On("change", onLeadsChange)
  local created = { frame = frame, parts = parts }

  return created
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

-- The sound and taskbar flash alone, for a lead shown elsewhere (WhisperMessenger's preview).
-- The lead argument is ignored.
AlertToast.Alert = alert

-- A new lead (Leads.On("new"), wired by Bootstrap): show it, light the launcher, sound, flash.
-- Nothing in an instance.
function AlertToast.Show(lead)
  if FlavorCompat.InInstance() then
    return
  end
  toast = toast or create()
  local replacing = toast.frame:IsShown() and current.lead ~= nil and current.lead ~= lead
  AlertToast.more = replacing and AlertToast.more + 1 or 0
  current.lead, current.shownAt, current.summary = lead, now(), false
  render(lead)
  Launcher.ShowLead(lead)
  alert()
  ToastChrome.HideAfter(toast.frame, hide)
end

-- The away summary (§7.6; Model/AwaySummary.lua through Bootstrap, or WhisperBridge when WM refuses
-- its preview): the same toast with its own clicks and tooltip, no sound (each lead alerted when it
-- came), hidden after the toast duration; a new lead replaces it. Nothing in an instance.
function AlertToast.ShowSummary(count, expired)
  if FlavorCompat.InInstance() then
    return
  end
  toast = toast or create()
  current.lead, current.shownAt, current.summary = nil, nil, true
  AlertToast.more = 0
  paint(Localization.Text("Craft Alert"), nil, AwaySummary.Text(count, expired), "", "")
  Launcher.ShowLead(nil)
  ToastChrome.HideAfter(toast.frame, hide)
end

-- ScanGate.OnChange (wired by Bootstrap): entering an instance hides a shown toast; it is not
-- shown again on leaving. Arguments are ignored.
function AlertToast.OnGate()
  if toast ~= nil and toast.frame:IsShown() and FlavorCompat.InInstance() then
    hide()
  end
end

-- Docks the toast beside the launcher (Dock.Anchor), or at a fixed spot on UIParent before the
-- launcher exists. Bootstrap runs it after every launcher drag (Launcher.OnMoved); render and
-- every leads "change" while the toast is shown run it too.
function AlertToast.Dock()
  if toast == nil then
    return
  end
  local frame, launcher, screen = toast.frame, Launcher.Frame(), _G["UIParent"]
  frame:ClearAllPoints()
  if launcher == nil then
    local point, x, y = NO_LAUNCHER_POSITION[1], NO_LAUNCHER_POSITION[2], NO_LAUNCHER_POSITION[3]
    frame:SetPoint(point, screen, point, x, y)

    return
  end
  local lx, ly = launcher:GetCenter()
  local sx, sy = screen:GetCenter()
  local point, relativePoint, x, y = Dock.Anchor(lx, ly, sx, sy)
  frame:SetPoint(point, launcher, relativePoint, x, y)
end

-- The lead on the toast and GetTime() when it appeared, or nil (hidden, also by Alt+Z, or
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
