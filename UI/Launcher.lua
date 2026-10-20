local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local Status = ns.Status or require("CraftAlert.Core.Status")
local ScanGate = ns.ScanGate or require("CraftAlert.Core.ScanGate")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local LeadsWindow = ns.LeadsWindow or require("CraftAlert.UI.LeadsWindow")

-- Spec §7.3 and §7.6: the launcher button, frame CraftAlertLauncher, the one Craft Alert frame
-- made at login (§4.4 rule 5). Lit while scanning, dim while paused; a badge counts the leads;
-- the tooltip is the status line; a click toggles the leads window; "Hide when no leads"
-- hides it while the list is empty. Draggable, position saved in CraftAlertDB.ui.launcher.
local Launcher = {}

local tostring = tostring

local FRAME_NAME = "CraftAlertLauncher"
local UI_KEY = "launcher"
local FALLBACK_POSITION = { "RIGHT", -60, 120 }
local ICON_INSET = 2
local ICON_CROP = { 0.08, 0.92, 0.08, 0.92 }
local BADGE_OFFSET = 6

---@type table
local launcher = nil -- the button, nil until Create

local function showTooltip(frame)
  local tooltip, secondary = _G["GameTooltip"], Theme.COLORS.textSecondary
  tooltip:SetOwner(frame, "ANCHOR_LEFT")
  tooltip:SetText(Localization.Text("Craft Alert"))
  tooltip:AddLine(Status.Text(ScanGate.State()), 1, 1, 1, true)
  tooltip:AddLine(Localization.Text("Click: leads window · Drag: move"), secondary[1], secondary[2], secondary[3], true)
  tooltip:Show()
end

local function hideTooltip()
  _G["GameTooltip"]:Hide()
end

local function createBadge(frame)
  local size = Theme.LAYOUT.ICON_BADGE_SIZE
  local badge = _G["CreateFrame"]("Frame", nil, frame)
  badge:SetSize(size, size)
  badge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", BADGE_OFFSET, BADGE_OFFSET)
  local circle = badge:CreateTexture(nil, "ARTWORK")
  circle:SetAllPoints(badge)
  circle:SetTexture(Theme.BADGE_TEXTURE)
  local accent = Theme.COLORS.accent
  circle:SetVertexColor(accent[1], accent[2], accent[3], accent[4])
  local count = FrameKit.Text(badge, Theme.FONTS.badge, Theme.COLORS.badgeText)
  count:SetPoint("CENTER", badge, "CENTER", 0, 0)
  count:SetJustifyH("CENTER")
  return badge, count
end

local function create()
  local frame = _G["CreateFrame"]("Button", FRAME_NAME, _G["UIParent"])
  frame:SetSize(Theme.LAYOUT.ICON_SIZE, Theme.LAYOUT.ICON_SIZE)
  FrameKit.Panel(frame)
  local icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", frame, "TOPLEFT", ICON_INSET, -ICON_INSET)
  icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -ICON_INSET, ICON_INSET)
  icon:SetTexture(Theme.ICON)
  icon:SetTexCoord(ICON_CROP[1], ICON_CROP[2], ICON_CROP[3], ICON_CROP[4])
  frame.icon = icon
  frame.badge, frame.badgeText = createBadge(frame)
  FrameKit.Draggable(frame, UI_KEY)
  FrameKit.Place(frame, UI_KEY, FALLBACK_POSITION)
  frame:RegisterForClicks("LeftButtonUp")
  frame:SetScript("OnClick", LeadsWindow.Toggle)
  frame:SetScript("OnEnter", showTooltip)
  frame:SetScript("OnLeave", hideTooltip)
  return frame
end

-- Bootstrap calls this at login; later calls return the same button.
function Launcher.Create()
  launcher = launcher or create()
  Launcher.Refresh()
  return launcher
end

-- Lit or dim from ScanGate.IsActive(), badge and visibility from the leads. Arguments are
-- ignored (Bootstrap subscribes it to ScanGate.OnChange and Leads.On("change")).
function Launcher.Refresh()
  if launcher == nil then
    return
  end
  local lit = ScanGate.IsActive()
  launcher.icon:SetDesaturated(not lit)
  launcher:SetAlpha(lit and 1 or Theme.DIM_ALPHA)
  local count = #Leads.List()
  launcher.badgeText:SetText(tostring(count))
  if count > 0 then
    launcher.badge:Show()
  else
    launcher.badge:Hide()
  end
  local hideEmpty = _G["CraftAlertDB"].settings.hideLauncherWhenNoLeads
  if hideEmpty and not Leads.HasActive() then
    launcher:Hide()
  else
    launcher:Show()
  end
end

ns.Launcher = Launcher
return Launcher
