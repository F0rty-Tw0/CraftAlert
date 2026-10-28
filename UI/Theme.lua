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
  -- The launcher badge's number and rim, as WhisperMessenger's badge.
  badgeText = { 0.07, 0.07, 0.10, 1.0 },
  badgeRim = { 0, 0, 0, 0.75 },
  -- Lead states: the dots, the "replied" tag and the ledger counts.
  greeted = { 0.12, 0.72, 0.96, 1.0 },
  replied = { 0.30, 0.82, 0.40, 1.0 },
  warning = { 0.90, 0.72, 0.20, 1.0 },
  -- Blizzard's HIGHLIGHT_FONT_COLOR, NORMAL_FONT_COLOR, GRAY_FONT_COLOR and GREEN_FONT_COLOR (the
  -- tooltips' instruction lines), for colour codes and texts.
  white = { 1.0, 1.0, 1.0, 1.0 },
  gold = { 1.0, 0.82, 0.0, 1.0 },
  grey = { 0.5, 0.5, 0.5, 1.0 },
  green = { 0.1, 1.0, 0.1, 1.0 },
  -- The details pane's header band and the 1 px line between the panes.
  headerFill = { 0.09, 0.08, 0.07, 0.60 },
  divider = { 1, 1, 1, 0.08 },
  -- The selected row's tint over the quest-log highlight (spec D1).
  selectedTint = { 1, 0.82, 0 },
}

-- Blizzard font object names.
Theme.FONTS = {
  title = "GameFontHighlight",
  name = "GameFontNormal",
  body = "GameFontHighlightSmall",
  detail = "GameFontDisableSmall",
  badge = "GameFontHighlightSmall",
  heading = "GameFontNormalLarge",
  -- Settings labels and input text, as WhisperMessenger's settings labels (WM_Highlight).
  setting = "GameFontHighlight",
}

-- The spacing scale: every gap and padding takes one of these steps, bar the off-scale values
-- commented where they are declared.
local SPACE = { XS = 4, S = 8, M = 12, L = 16, XL = 24, XXL = 32 }

Theme.LAYOUT = {
  SPACE = SPACE,
  -- The button widths: small (Play), standard (details actions), wide and extra wide.
  BUTTON_WIDTH = { S = 48, M = 100, L = 140, XL = 180 },
  -- off-scale: the details action bar's buttons, not resized to BUTTON_HEIGHT.
  ACTION_BUTTON_HEIGHT = 22,
  -- off-scale: the lead count's place in the title-bar art.
  STATUS_OFFSET = { x = 64, y = -42 },
  -- off-scale: the nav row's highlight inset.
  NAV_BUTTON_INSET = 2,
  PADDING = SPACE.S,
  TOAST_WIDTH = 320,
  DOCK_GAP = SPACE.S,
  WINDOW_WIDTH = 840,
  WINDOW_HEIGHT = 560,
  WINDOW_MIN_WIDTH = 720,
  WINDOW_MIN_HEIGHT = 420,
  ROW_ICON_SIZE = 14,
  HEADER_ICON_SIZE = 36,
  ICON_SIZE = 53,
  PORTRAIT_SIZE = 44,
  RING_SIZE = 56,
  ICON_BADGE_SIZE = 20,
  NAV_BUTTON_HEIGHT = 28,
  -- The settings rows' widest (WhisperMessenger's SETTINGS_CONTROL_WIDTH): a narrower page
  -- (another addon's panel) narrows them, a wider one centers them.
  CONTROL_WIDTH = 350,
  CONTROL_HEIGHT = 24,
  -- Between settings rows and above a section label (WhisperMessenger's toggle row spacing and its
  -- gap before a section title).
  CONTROL_GAP = SPACE.L,
  SECTION_GAP = SPACE.XXL,
  -- The label line above a slider, input or dropdown: a 12 px line of FONTS.setting, then 6 px
  -- (WhisperMessenger's SETTINGS_LABEL_SPACING) to the control's top.
  LABEL_HEIGHT = 18,
  -- An input's text insets, clear of InputBoxTemplate's 8 px end caps (the left one starts 5 px
  -- out of the box) by 3 px.
  -- off-scale: clear of the template art.
  INPUT_INSET = { left = 6, right = 11 },
  -- Room right of the slider bar for the template's value text (drawn 25 px right of the bar).
  SLIDER_VALUE_WIDTH = 56,
  -- A settings page's rows inside its scroll content (16 px in from the left, as WhisperMessenger's
  -- settings pages); the scroll bar right of the content sizes itself (UI/ScrollBar.lua).
  PAGE_PADDING = { left = SPACE.L, right = SPACE.L, top = SPACE.M, bottom = SPACE.M },
  -- Between a list's rows and its scroll bar: WhisperMessenger's SCROLLBAR_RETAIL_GUTTER (there,
  -- the most of its retail bar that may hang into the empty space right of a view).
  -- off-scale: WhisperMessenger's scroll bar gutter.
  SCROLLBAR_GAP = 5,
  MUTE_SIZE = 16,
  INPUT_HEIGHT = 22,
  BUTTON_HEIGHT = 20,
  LIST_ROW_HEIGHT = 20,
  GEAR_SIZE = 20,
  -- The leads window's split view (WhisperMessenger's Layout numbers): list pane and its 48 px
  -- rows, the details pane's header and info strip (details spec A.1-A.2), padding, action bar
  -- and the status band.
  LIST_WIDTH = 260,
  LIST_MIN_WIDTH = 180, -- the narrowest list, in WhisperMessenger's panel (WM's CONTACTS_MIN_WIDTH)
  ROW_HEIGHT = 48,
  LIST_ROW_INSET = 2,
  -- A lead row's hover tooltip is at least this wide, so the chat line is not a tall column.
  ROW_TIP_WIDTH = 360,
  -- A settings control's hover tip wraps at this width, wide enough for ~50 letters a line.
  TIP_WIDTH = 300,
  PANE_PADDING = SPACE.XS,
  LIST_ICON_SIZE = 34,
  DETAILS_HEADER_HEIGHT = 62,
  INFO_STRIP_HEIGHT = 24,
  DETAILS_PADDING = SPACE.L,
  ACTION_BAR_HEIGHT = 44,
  BAND_HEIGHT = 36,
  -- The ledger line above the split view's panes (UI/LedgerStrip.lua).
  LEDGER_HEIGHT = 20,
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
  -- The character frame's round portrait mask: the round icon's mask and the status dot's art (spec D5, D10).
  CIRCLE_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
  -- The leads window's settings gear (spec §7.1): the quest log settings gear, the world map's where missing.
  GEAR_ATLAS = "QuestLog-icon-setting",
  GEAR_FILE = "Interface\\WorldMap\\Gear_64Grey",
  BACK_ATLAS = "common-icon-backarrow",
  BACK_FILE = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up",
  -- Pane backgrounds (atlases, painted through FrameKit.PaintPanel) and the chat window's resize grabber.
  PANEL_BACKGROUND = "Professions-background-summarylist",
  WIDE_PANEL_BACKGROUND = "auctionhouse-background-index",
  SIZE_GRABBER_UP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up",
  SIZE_GRABBER_DOWN = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down",
  SIZE_GRABBER_HIGHLIGHT = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight",
  -- A recipe's mute switch: the voice chat speaker; muted, the speaker crossed out in red (atlases,
  -- the same art's files where missing). The action bars' square button highlight.
  SPEAKER_ATLAS = "voicechat-icon-speaker",
  SPEAKER_FILE = "Interface\\Common\\VoiceChat-Speaker",
  MUTED_ATLAS = "voicechat-icon-speaker-mute",
  MUTED_FILE = "Interface\\Common\\VoiceChat-Muted",
  ICON_HIGHLIGHT = "Interface\\Buttons\\ButtonHilight-Square",
}
Theme.DIM_ALPHA = 0.5

ns.Theme = Theme
return Theme
