local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local ChatPrint = ns.ChatPrint or require("CraftAlert.Core.ChatPrint")
local CraftScanImport = ns.CraftScanImport or require("CraftAlert.Persistence.CraftScanImport")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local Controls = ns.SettingsControls or require("CraftAlert.UI.Settings.Controls")

-- Spec §10.2: the one-time CraftScan offer at login (Retail). While CraftScan's saved data is
-- loaded and the player has neither answered (`craftScanPrompted`) nor imported
-- (`craftScanImported`), a chat line and this window ask once. Accept or Decline answers it;
-- the window's close button leaves it for the next login. Accept runs the sliced import (Import,
-- shared with the Linked accounts page); its result line and the advice to disable CraftScan
-- print when the job ends. Nothing shows in an instance, and the question stays open there.
local CraftScanPrompt = {}

local FRAME_NAME = "CraftAlertCraftScanPrompt"
local WIDTH, HEIGHT = 360, 170
-- off-scale: not one of the four button widths, not resized.
local PROMPT_BUTTON_WIDTH = 110
local TEXT_INSET = 16
local BUTTON_GAP = 8

---@type table
local frame = nil -- made on the first show

-- Runs the CraftScan import of `db` → onLine(result line) when it ends, after
-- `craftScanImported` is set; onCancel() (optional) when the job errors or another import replaces it.
function CraftScanPrompt.Import(db, onLine, onCancel)
  CraftScanImport.Start(db, _G["CraftScan_DB"], function(c)
    db.settings.craftScanImported = _G["time"]()
    local characters = Localization.Plural(c.characters, "%d character", "%d characters")
    local recipes = Localization.Plural(c.recipes, "%d recipe", "%d recipes")
    local greetings = Localization.Plural(c.greetings, "%d greeting", "%d greetings")
    local line = "CraftScan import: %s, %s (%d muted) and %s (%d skipped)."
    onLine(Localization.Text(line, characters, recipes, c.muted, greetings, c.skipped))
  end, onCancel)
end

local function answer(db, accepted)
  db.settings.craftScanPrompted = true
  frame:Hide()
  if not accepted then
    return
  end
  CraftScanPrompt.Import(db, function(line)
    ChatPrint.Line(line)
    ChatPrint.Line(Localization.Text("Craft Alert has your CraftScan data now; you can disable CraftScan."))
  end)
end

local function create()
  local window = _G["CreateFrame"]("Frame", FRAME_NAME, _G["UIParent"], "ButtonFrameTemplate")
  window:SetFrameStrata("DIALOG")
  window:SetSize(WIDTH, HEIGHT)
  window:SetPoint("CENTER", _G["UIParent"], "CENTER", 0, 0)
  window:SetTitle(Localization.Text("Craft Alert — CraftScan"))
  if type(window.SetPortraitToAsset) == "function" then
    window:SetPortraitToAsset(Theme.ICON)
  else
    window.PortraitContainer.portrait:SetTexture(Theme.ICON)
  end
  local text = FrameKit.Text(window.Inset, Theme.FONTS.body)
  text:SetPoint("TOPLEFT", window.Inset, "TOPLEFT", TEXT_INSET, -TEXT_INSET)
  text:SetPoint("TOPRIGHT", window.Inset, "TOPRIGHT", -TEXT_INSET, -TEXT_INSET)
  text:SetWordWrap(true)
  text:SetJustifyH("LEFT")
  local body = "CraftScan data found. Import this account's characters, recipes and greetings? What Craft Alert already has stays as it is."
  text:SetText(Localization.Text(body))
  window.text = text
  window.accept = Controls.Button(window, Localization.Text("Import"), PROMPT_BUTTON_WIDTH, nil)
  window.accept:SetPoint("BOTTOMRIGHT", window, "BOTTOM", -BUTTON_GAP / 2, 4)
  window.decline = Controls.Button(window, Localization.Text("Decline"), PROMPT_BUTTON_WIDTH, nil)
  window.decline:SetPoint("BOTTOMLEFT", window, "BOTTOM", BUTTON_GAP / 2, 4)
  window:Hide()
  return window
end

-- Bootstrap's last login step on Retail.
function CraftScanPrompt.MaybeShow(db)
  local settings = db.settings
  if not FlavorCompat.isRetail or type(_G["CraftScan_DB"]) ~= "table" then
    return
  end
  if settings.craftScanPrompted or settings.craftScanImported or FlavorCompat.InInstance() then
    return
  end
  ChatPrint.Line(Localization.Text("CraftScan data found. Import characters, recipes, and greetings?"))
  frame = frame or create()
  frame.accept:SetScript("OnClick", function()
    answer(db, true)
  end)
  frame.decline:SetScript("OnClick", function()
    answer(db, false)
  end)
  frame:Show()
end

ns.CraftScanPrompt = CraftScanPrompt
return CraftScanPrompt
