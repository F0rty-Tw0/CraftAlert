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
  -- Blizzard's HIGHLIGHT_FONT_COLOR, NORMAL_FONT_COLOR and GRAY_FONT_COLOR, for colour codes.
  white = { 1.0, 1.0, 1.0, 1.0 },
  gold = { 1.0, 0.82, 0.0, 1.0 },
  grey = { 0.5, 0.5, 0.5, 1.0 },
  -- The details pane's header band and the 1 px line between the panes.
  headerFill = { 0.09, 0.08, 0.07, 0.60 },
  divider = { 1, 1, 1, 0.08 },
}

-- Blizzard font object names (WhisperMessenger's FONT_MAP bases).
Theme.FONTS = {
  title = "GameFontHighlight",
  name = "GameFontNormal",
  body = "GameFontHighlightSmall",
  detail = "GameFontDisableSmall",
  badge = "GameFontHighlightSmall",
  heading = "GameFontNormalLarge",
}

Theme.LAYOUT = {
  PADDING = 8,
  TOAST_WIDTH = 320,
  DOCK_GAP = 8,
  WINDOW_WIDTH = 840,
  WINDOW_HEIGHT = 560,
  WINDOW_MIN_WIDTH = 720,
  WINDOW_MIN_HEIGHT = 420,
  ROW_ICON_SIZE = 14,
  HEADER_ICON_SIZE = 32,
  ICON_SIZE = 53,
  PORTRAIT_SIZE = 44,
  RING_SIZE = 56,
  ICON_BADGE_SIZE = 20,
  NAV_BUTTON_HEIGHT = 28,
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
  -- The leads window's split view (WhisperMessenger's Layout numbers): list pane and its 48 px
  -- rows, the details pane's header, padding, action bar and the status band.
  LIST_WIDTH = 260,
  ROW_HEIGHT = 48,
  LIST_ROW_INSET = 2,
  PANE_PADDING = 4,
  LIST_ICON_SIZE = 34,
  DETAILS_HEADER_HEIGHT = 56,
  DETAILS_PADDING = 16,
  DETAILS_GAP = 12,
  ACTION_BAR_HEIGHT = 44,
  BAND_HEIGHT = 36,
  -- left, top, right, bottom: the content frame inside a ButtonFrameTemplate window.
  CONTENT_INSET = { 4, -60, -6, 4 },
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
  BACK_ATLAS = "common-icon-backarrow",
  BACK_FILE = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up",
  -- Pane backgrounds (atlases, painted through FrameKit.PaintPanel) and the chat window's resize grabber.
  PANEL_BACKGROUND = "Professions-background-summarylist",
  WIDE_PANEL_BACKGROUND = "auctionhouse-background-index",
  SIZE_GRABBER_UP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up",
  SIZE_GRABBER_DOWN = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down",
  SIZE_GRABBER_HIGHLIGHT = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight",
}
Theme.DIM_ALPHA = 0.5

ns.Theme = Theme
return Theme
