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
local LauncherArt = ns.LauncherArt or require("CraftAlert.UI.LauncherArt")
local ProfessionList = ns.ProfessionList or require("CraftAlert.Professions.ProfessionList")

-- Spec §7.3 and §7.6: the launcher button, frame CraftAlertLauncher, the one Craft Alert frame
-- made at login (§4.4 rule 5). Lit while scanning, dim while paused; a badge counts the leads;
-- the tooltip is the status line; a click toggles the leads window; "Hide when no leads"
-- hides it while the list is empty. Draggable, position saved in CraftAlertDB.ui.launcher.
-- Native-HUD spec §5.1–5.2: CraftScan-style ring and portrait (UI/LauncherArt.lua); the portrait shows the
-- shown lead's profession, else the first profession; a new lead pulses the ring.
local Launcher = {}

local tostring = tostring
local ipairs = ipairs

local FRAME_NAME = "CraftAlertLauncher"
local UI_KEY = "launcher"
local FALLBACK_POSITION = { "RIGHT", -60, 120 }
local BADGE_OFFSET = 6

---@type table
local launcher = nil -- the button, nil until Create
local leadShown = false
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

-- Blizzard's tooltip hierarchy (Blizzard_SharedXML/SharedTooltipTemplates.lua, every flavour): gold
-- title, the status in white, a blank line, one green instruction line per action.
local function showTooltip(frame)
  local tooltip = _G["GameTooltip"]
  tooltip:SetOwner(frame, "ANCHOR_LEFT")
  _G["GameTooltip_SetTitle"](tooltip, Localization.Text("Craft Alert"), _G["NORMAL_FONT_COLOR"])
  _G["GameTooltip_AddHighlightLine"](tooltip, Status.Text(ScanGate.State()))
  _G["GameTooltip_AddBlankLineToTooltip"](tooltip)
  _G["GameTooltip_AddInstructionLine"](tooltip, Localization.Text("Click: open the leads window"))
  _G["GameTooltip_AddInstructionLine"](tooltip, Localization.Text("Drag: move"))
  tooltip:Show()
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

-- The button, or nil before Create.
function Launcher.Frame()
  return launcher
end

-- A lead: its profession's icon, and the ring pulses once then keeps pulsing. nil: the idle
-- icon, and the looping pulse stops.
function Launcher.ShowLead(lead)
  if launcher == nil then
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
  if launcher == nil then
    return
  end
  launcher:StartMoving()
end

function Launcher.StopDrag()
  if launcher == nil then
    return
  end
  launcher:StopMovingOrSizing()
  FrameKit.SavePosition(launcher, UI_KEY)
  for _, fn in ipairs(movedHandlers) do
    fn()
  end
end

-- Lit or dim from ScanGate.IsActive(), badge and visibility from the leads. Arguments are
-- ignored (Bootstrap subscribes it to ScanGate.OnChange and Leads.On("change")).
function Launcher.Refresh()
  if launcher == nil then
    return
  end
  if not leadShown then
    launcher.icon:SetTexture(iconFor(nil))
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
