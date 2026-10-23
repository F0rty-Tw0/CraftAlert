local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- Colours, font-object names, layout numbers and art paths Craft Alert draws with, in the native
-- WoW HUD look: Blizzard templates and font objects carry the rest. Data only.
local Theme = {}

-- { r, g, b, a }
Theme.COLORS = {
  textPrimary = { 0.92, 0.92, 0.95, 1.0 },
  textSecondary = { 1.0, 1.0, 1.0, 0.55 },
  textTimestamp = { 1.0, 1.0, 1.0, 0.40 },
  accent = { 0.12, 0.72, 0.96, 1.0 },
  badgeText = { 0.98, 0.99, 1.00, 1.0 },
  greeted = { 0.30, 0.82, 0.40, 1.0 },
  warning = { 0.90, 0.72, 0.20, 1.0 },
}

-- Blizzard font object names (WhisperMessenger's FONT_MAP bases).
Theme.FONTS = {
  title = "GameFontHighlight",
  name = "GameFontNormal",
  body = "GameFontHighlightSmall",
  detail = "GameFontDisableSmall",
  badge = "GameFontHighlightSmall",
}

Theme.LAYOUT = {
  PADDING = 8,
  TOAST_WIDTH = 320,
  DOCK_GAP = 8,
  WINDOW_WIDTH = 460,
  WINDOW_HEIGHT = 320,
  WINDOW_MIN_WIDTH = 360,
  WINDOW_MIN_HEIGHT = 160,
  INSET_TOP = 28,
  INSET_BOTTOM = 26,
  ROW_ICON_SIZE = 14,
  ROW_HEIGHT = 36,
  ROW_GAP = 2,
  ICON_SIZE = 53,
  PORTRAIT_SIZE = 44,
  RING_SIZE = 56,
  ICON_BADGE_SIZE = 20,
  SETTINGS_WIDTH = 600,
  SETTINGS_HEIGHT = 480,
  NAV_WIDTH = 130,
  NAV_BUTTON_HEIGHT = 24,
  CONTROL_WIDTH = 420,
  CONTROL_HEIGHT = 24,
  CONTROL_GAP = 4,
  SECTION_GAP = 14,
  LABEL_WIDTH = 150,
  -- Room right of the slider bar for the template's value text (drawn 25 px right of the bar).
  SLIDER_VALUE_WIDTH = 56,
  INPUT_HEIGHT = 22,
  BUTTON_HEIGHT = 20,
  LIST_ROW_HEIGHT = 20,
  GEAR_SIZE = 20,
}

Theme.ICON = "Interface\\Icons\\INV_Misc_Bell_01"
-- Textures every flavor's UI source references (ui_live, ui_forever, ui_classic, ui_classic_era).
Theme.BADGE_TEXTURE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
Theme.GREETED_ICON = "Interface\\RaidFrame\\ReadyCheck-Ready"
-- Quest-log list art (plain files, not atlases): selected and hover row highlights, drawn ADD.
Theme.ART = {
  LIST_SELECTED = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight",
  LIST_HOVER = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
  LIST_SELECTED_ALPHA = 0.45,
  LIST_HOVER_ALPHA = 0.18,
  -- The leads window's settings gear (spec §7.1): the GM-ticket gear, the world map's where missing.
  GEAR_ATLAS = "GM-icon-settings",
  GEAR_FILE = "Interface\\WorldMap\\Gear_64Grey",
}
Theme.DIM_ALPHA = 0.5

ns.Theme = Theme
return Theme
