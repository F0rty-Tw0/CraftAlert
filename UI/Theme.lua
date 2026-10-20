local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- The WhisperMessenger look (its default preset, UI/Theme/Presets/Data/WowDefault.lua, and the
-- Layout values the toast, leads window and launcher use), trimmed to what Craft Alert draws.
-- No presets and no font objects of its own: text uses Blizzard's font objects, which carry
-- the client's glyph fallback chain. Data only.
local Theme = {}

-- { r, g, b, a }
Theme.COLORS = {
  surface = { 0.07, 0.07, 0.10, 0.97 },
  surfaceRaised = { 0.10, 0.10, 0.14, 0.60 },
  chrome = { 0.09, 0.09, 0.13, 0.60 },
  border = { 1.0, 1.0, 1.0, 0.10 },
  divider = { 1.0, 1.0, 1.0, 0.08 },
  rowHover = { 1.0, 1.0, 1.0, 0.05 },
  textPrimary = { 0.92, 0.92, 0.95, 1.0 },
  textSecondary = { 1.0, 1.0, 1.0, 0.55 },
  textTimestamp = { 1.0, 1.0, 1.0, 0.40 },
  accent = { 0.12, 0.72, 0.96, 1.0 },
  badgeText = { 0.98, 0.99, 1.00, 1.0 },
  greeted = { 0.30, 0.82, 0.40, 1.0 },
  warning = { 0.90, 0.72, 0.20, 1.0 },
  danger = { 0.45, 0.12, 0.12, 0.80 },
  dangerHover = { 0.55, 0.16, 0.16, 0.90 },
  dangerText = { 1.0, 0.35, 0.35, 1.0 },
  -- Settings controls (WowDefault toggle_on / toggle_off / option_bg / button_fill_hover / input_bg).
  toggleOn = { 0.12, 0.72, 0.96, 1.0 },
  toggleOff = { 0.32, 0.33, 0.40, 0.95 },
  knob = { 0.98, 0.99, 1.00, 1.0 },
  option = { 0.12, 0.13, 0.18, 0.90 },
  optionHover = { 0.20, 0.45, 0.65, 1.0 },
  optionSelected = { 0.12, 0.72, 0.96, 0.16 },
  input = { 0.17, 0.19, 0.26, 1.0 },
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
  TITLE_BAR_HEIGHT = 24,
  TITLE_BUTTON_SIZE = 22,
  PADDING = 8,
  BORDER = 1,
  TOAST_WIDTH = 320,
  TOAST_HEIGHT = 96,
  WINDOW_WIDTH = 460,
  WINDOW_HEIGHT = 320,
  WINDOW_MIN_WIDTH = 360,
  WINDOW_MIN_HEIGHT = 160,
  RESIZE_GRIP_SIZE = 16,
  FOOTER_HEIGHT = 20,
  ROW_ICON_SIZE = 14,
  ROW_HEIGHT = 36,
  ROW_GAP = 2,
  BLOCK_BUTTON_WIDTH = 48,
  BLOCK_BUTTON_HEIGHT = 18,
  ICON_SIZE = 42,
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
  SWITCH_WIDTH = 28,
  SWITCH_HEIGHT = 16,
  KNOB_SIZE = 12,
  KNOB_INSET = 2,
  SLIDER_HEIGHT = 16,
  SLIDER_THUMB_WIDTH = 10,
  INPUT_HEIGHT = 22,
  BUTTON_HEIGHT = 20,
  LIST_ROW_HEIGHT = 20,
}

Theme.ICON = "Interface\\Icons\\INV_Misc_Bell_01"
-- Textures every flavor's UI source references (ui_live, ui_forever, ui_classic, ui_classic_era).
Theme.BADGE_TEXTURE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
Theme.GREETED_ICON = "Interface\\RaidFrame\\ReadyCheck-Ready"
Theme.RESIZE_GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
Theme.DIM_ALPHA = 0.5

ns.Theme = Theme
return Theme
