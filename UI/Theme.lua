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
  ROW_HEIGHT = 36,
  ROW_GAP = 2,
  BLOCK_BUTTON_WIDTH = 48,
  BLOCK_BUTTON_HEIGHT = 18,
  ICON_SIZE = 42,
  ICON_BADGE_SIZE = 20,
}

Theme.ICON = "Interface\\Icons\\INV_Misc_Bell_01"
Theme.BADGE_TEXTURE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
Theme.DIM_ALPHA = 0.5

ns.Theme = Theme
return Theme
