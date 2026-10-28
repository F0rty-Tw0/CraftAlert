local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local Status = ns.Status or require("CraftAlert.Core.Status")
local ScanGate = ns.ScanGate or require("CraftAlert.Core.ScanGate")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local Tooltip = ns.Tooltip or require("CraftAlert.UI.Tooltip")
local LeadsWindow = ns.LeadsWindow or require("CraftAlert.UI.LeadsWindow")
local LauncherArt = ns.LauncherArt or require("CraftAlert.UI.LauncherArt")
local ProfessionList = ns.ProfessionList or require("CraftAlert.Professions.ProfessionList")

-- Spec §7.3 and §7.6: the launcher button, frame CraftAlertLauncher, the one Craft Alert frame
-- made at login (§4.4 rule 5). Lit while scanning, dim while paused; a gold badge counts the
-- unseen leads (Leads.IsUnseen); the tooltip is the status line; a click toggles the leads
-- window; "Hide when no leads"
-- hides it while the list is empty. Draggable, position saved in CraftAlertDB.ui.launcher.
-- Native-HUD spec §5.1–5.2: CraftScan-style ring and portrait (UI/LauncherArt.lua); the portrait shows the
-- shown lead's profession, else the first profession; a new lead pulses the ring.
local Launcher = {}

local tostring = tostring
local ipairs = ipairs

local FRAME_NAME = "CraftAlertLauncher"
local UI_KEY = "launcher"
local FALLBACK_POSITION = { "RIGHT", -60, 120 }
-- The badge's centre BADGE_INSET px in from the button's top-right corner, on the ring's edge;
-- its dark rim BADGE_RIM px wide.
local BADGE_INSET, BADGE_RIM = 8, 2

---@type table
local launcher = nil -- the button, nil until Create
local leadShown = false
local suppressed = false -- WhisperMessenger shows the leads: the button stays built but hidden
local movedHandlers = {}

-- The profession's icon from the client, else the bell.
local function iconFor(lead)
  local key = lead and lead.prof
  if lead == nil then
    local order = ProfessionList.Order()
    key = order[1]
  end

  return FrameKit.ProfessionIcon(key) or Theme.ICON
end

-- The status in white, then one green instruction line per action (Tooltip.ShowHint).
local function showTooltip(frame)
  local body = { Status.Text(ScanGate.State()) }
  local clicks = { Localization.Text("Click: open the leads window"), Localization.Text("Drag: move") }
  Tooltip.ShowHint(frame, "ANCHOR_LEFT", Localization.Text("Craft Alert"), body, clicks)
end

local function onEnter(frame)
  if frame.glow then
    frame.glow:Show()
  end
  showTooltip(frame)
end

local function onLeave(frame)
  if frame.glow then
    frame.glow:Hide()
  end
  Tooltip.HideIfOwned(frame)
end

local function circleTexture(badge, layer, color)
  local texture = badge:CreateTexture(nil, layer)
  texture:SetTexture(Theme.BADGE_TEXTURE)
  texture:SetVertexColor(color[1], color[2], color[3], color[4])
  return texture
end

-- Gold like the unseen dots it counts (LeadRow), a dark number, a dark rim where it sits on the
-- ring.
local function createBadge(frame)
  local size, colors = Theme.LAYOUT.ICON_BADGE_SIZE, Theme.COLORS
  local badge = _G["CreateFrame"]("Frame", nil, frame)
  badge:SetSize(size, size)
  badge:SetPoint("CENTER", frame, "TOPRIGHT", -BADGE_INSET, -BADGE_INSET)
  badge.rim = circleTexture(badge, "BACKGROUND", colors.badgeRim)
  badge.rim:SetPoint("TOPLEFT", badge, "TOPLEFT", -BADGE_RIM, BADGE_RIM)
  badge.rim:SetPoint("BOTTOMRIGHT", badge, "BOTTOMRIGHT", BADGE_RIM, -BADGE_RIM)
  badge.circle = circleTexture(badge, "ARTWORK", colors.gold)
  badge.circle:SetAllPoints(badge)
  local count = FrameKit.Text(badge, Theme.FONTS.badge, colors.badgeText)
  count:SetPoint("CENTER", badge, "CENTER", 0, 0)
  count:SetJustifyH("CENTER")
  return badge, count
end

local function create()
  local frame = _G["CreateFrame"]("Button", FRAME_NAME, _G["UIParent"])
  frame:SetSize(Theme.LAYOUT.ICON_SIZE, Theme.LAYOUT.ICON_SIZE)
  local art = LauncherArt.Build(frame)
  frame.icon, frame.glow, frame.pulse = art.icon, art.glow, art.pulse
  frame.pulseOnce, frame.pulseLoop = art.pulseOnce, art.pulseLoop
  frame.badge, frame.badgeText = createBadge(frame)
  FrameKit.Draggable(frame, UI_KEY)
  frame:SetScript("OnDragStart", Launcher.StartDrag)
  frame:SetScript("OnDragStop", Launcher.StopDrag)
  FrameKit.Place(frame, UI_KEY, FALLBACK_POSITION)
  frame:RegisterForClicks("LeftButtonUp")
  frame:SetScript("OnClick", LeadsWindow.Toggle)
  frame:SetScript("OnEnter", onEnter)
  frame:SetScript("OnLeave", onLeave)
  return frame
end

-- Bootstrap calls this at login; later calls return the same button.
function Launcher.Create()
  launcher = launcher or create()
  Launcher.Refresh()
  return launcher
end

-- The button, or nil before Create and while suppressed (the toast docks to a visible button).
function Launcher.Frame()
  if suppressed then
    return nil
  end
  return launcher
end

-- true hides the button and stops its drag and lead icon; false lets the next Refresh show it.
function Launcher.SetSuppressed(flag)
  suppressed = flag
end

-- A lead: its profession's icon, and the ring pulses once then keeps pulsing. nil: the idle
-- icon, and the looping pulse stops.
function Launcher.ShowLead(lead)
  if launcher == nil or suppressed then
    return
  end
  leadShown = lead ~= nil
  launcher.icon:SetTexture(iconFor(lead))
  if launcher.pulseLoop == nil then
    return
  end
  if leadShown then
    launcher.pulseOnce:Play()
    launcher.pulseLoop:Play()
  else
    launcher.pulseLoop:Stop()
  end
end

-- `fn()` runs after every drag stop, once the position is saved; may be called before Create.
function Launcher.OnMoved(fn)
  movedHandlers[#movedHandlers + 1] = fn
end

function Launcher.StartDrag()
  if launcher == nil or suppressed then
    return
  end
  launcher:StartMoving()
end

function Launcher.StopDrag()
  if launcher == nil or suppressed then
    return
  end
  launcher:StopMovingOrSizing()
  FrameKit.SavePosition(launcher, UI_KEY)
  for _, fn in ipairs(movedHandlers) do
    fn()
  end
end

-- Lit or dim from ScanGate.IsActive(), badge and visibility from the leads; hidden in an
-- instance. Arguments are ignored (Bootstrap subscribes it to ScanGate.OnChange and
-- Leads.On("change") and "seen").
function Launcher.Refresh()
  if launcher == nil then
    return
  end
  if suppressed or FlavorCompat.InInstance() then
    launcher:Hide()
    return
  end
  if not leadShown then
    launcher.icon:SetTexture(iconFor(nil))
  end
  local lit = ScanGate.IsActive()
  launcher.icon:SetDesaturated(not lit)
  launcher:SetAlpha(lit and 1 or Theme.DIM_ALPHA)
  local count = Leads.CountUnseen(Leads.List())
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
