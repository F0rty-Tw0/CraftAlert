local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local Tooltip = ns.Tooltip or require("CraftAlert.UI.Tooltip")
local LeadText = ns.LeadText or require("CraftAlert.UI.LeadText")
local ClickRouter = ns.ClickRouter or require("CraftAlert.UI.ClickRouter")
local LinkHover = ns.LinkHover or require("CraftAlert.UI.LinkHover")
local Dock = ns.Dock or require("CraftAlert.UI.Dock")
local Launcher = ns.Launcher or require("CraftAlert.UI.Launcher")
local ToastLayout = ns.ToastLayout or require("CraftAlert.UI.ToastLayout")

-- Design spec §7.1 and native-HUD spec §4: the one alert toast. Created on the first alert
-- (design spec §4.4 rule 5) as frame CraftAlertToast, a native tooltip-backdrop panel docked
-- beside the launcher (UI/Dock.lua); dragging it moves the launcher, so it keeps no position of
-- its own. A newer lead replaces the shown one and the "+N more" badge counts the leads it
-- replaced; the toast hides after the toast duration (one pending timer, design spec §4.3
-- rule 1) or when its lead leaves the list.
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

local function render(lead)
  local frame, parts = toast.frame, toast.parts
  parts.name:SetText(tostring(lead.customer))
  FrameKit.PaintName(parts.name, lead.guid)
  parts.badge:SetText(badgeText())
  parts.headline:SetText(LeadText.Headline(lead))
  local detail = detailText(lead)
  showDetail(parts.detail, detail)
  parts.message:SetText(trim(lead.message))
  LinkHover.Clear(frame)
  ToastLayout.Fit(frame, parts, detail ~= "")
  frame:SetAlpha(settings().opacity or 1)
  frame:Show()
  AlertToast.Dock()
end

local function hide()
  current.lead, current.shownAt = nil, nil
  AlertToast.more = 0
  toast.frame:Hide()
  Launcher.ShowLead(nil)
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

-- What matched (lead.why, never drawn on the face) and the clicks, in Blizzard's tooltip hierarchy
-- (Blizzard_SharedXML/SharedTooltipTemplates.lua, every flavour): gold title, white description,
-- a blank line, one green instruction line per click, then the drag (it moves the launcher).
local function showTooltip(frame)
  local tooltip = Tooltip.Get()
  local why = current.lead and current.lead.why
  tooltip:SetOwner(frame, "ANCHOR_TOP")
  _G["GameTooltip_SetTitle"](tooltip, Localization.Text("Craft Alert"), _G["NORMAL_FONT_COLOR"])
  if type(why) == "string" and why ~= "" then
    _G["GameTooltip_AddHighlightLine"](tooltip, Localization.Text("Matched: %s", why))
  end
  _G["GameTooltip_AddBlankLineToTooltip"](tooltip)
  for _, line in ipairs(LeadText.ClickLines()) do
    _G["GameTooltip_AddInstructionLine"](tooltip, line)
  end
  _G["GameTooltip_AddInstructionLine"](tooltip, Localization.Text("Drag: move"))
  tooltip:Show()
end

-- A click on a link inside the message belongs to the link (LinkHover), never to the lead.
local function onClick(frame, button)
  local overLink = LinkHover.IsOverLink(frame)
  if overLink then
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
  current.lead, current.shownAt = lead, now()
  render(lead)
  Launcher.ShowLead(lead)
  alert()
  startHideTimer()
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
