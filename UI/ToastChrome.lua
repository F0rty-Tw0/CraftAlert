local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Tooltip = ns.Tooltip or require("CraftAlert.UI.Tooltip")

-- Design spec §7.1 and §4.3 rule 1: the alert toast's tooltip and its hide timer, shared by the
-- toast's lead and away-summary modes (UI/AlertToast.lua). There is one toast, so one timer.
local ToastChrome = {}

local ipairs = ipairs

local hideAt = 0
local timerPending = false
---@type table
local timerFrame = nil -- the frame of the latest HideAfter
---@type function
local hideFrame = nil

local function now()
  return _G["GetTime"]()
end

local armHide

local function onHideTimer()
  timerPending = false
  if timerFrame:IsShown() then
    armHide()
  end
end

-- One pending timer: it fires at the deadline set by the latest HideAfter, or re-arms for the rest.
armHide = function()
  if timerPending then
    return
  end
  local remaining = hideAt - now()
  if remaining <= 0 then
    hideFrame()
    return
  end
  timerPending = true
  _G["C_Timer"].After(remaining, onHideTimer)
end

-- `hide()` runs the toast duration from now unless `frame` was hidden by then; a later call moves
-- the deadline.
function ToastChrome.HideAfter(frame, hide)
  timerFrame, hideFrame = frame, hide
  hideAt = now() + (_G["CraftAlertDB"].settings.toastDuration or 20)
  armHide()
end

-- Blizzard's tooltip hierarchy (Blizzard_SharedXML/SharedTooltipTemplates.lua, every flavour): gold
-- title, the white `description` when given, a blank line, one green instruction line per entry of
-- `clicks`, then the drag (it moves the launcher).
function ToastChrome.ShowTooltip(frame, description, clicks)
  local tooltip = Tooltip.Get()
  tooltip:SetOwner(frame, "ANCHOR_TOP")
  _G["GameTooltip_SetTitle"](tooltip, Localization.Text("Craft Alert"), _G["NORMAL_FONT_COLOR"])
  if description then
    _G["GameTooltip_AddHighlightLine"](tooltip, description)
  end
  _G["GameTooltip_AddBlankLineToTooltip"](tooltip)
  for _, line in ipairs(clicks) do
    _G["GameTooltip_AddInstructionLine"](tooltip, line)
  end
  _G["GameTooltip_AddInstructionLine"](tooltip, Localization.Text("Drag: move"))
  tooltip:Show()
end

ns.ToastChrome = ToastChrome
return ToastChrome
