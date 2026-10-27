local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

-- The split-view numbers and art names: WhisperMessenger's constants, copied (spec A.2-A.4).
return function()
  Wow.reset()
  local Theme = Fresh.require("UI.Theme")
  local layout = Theme.LAYOUT
  Assert.same({ layout.LIST_WIDTH, layout.ROW_HEIGHT, layout.LIST_ROW_INSET, layout.PANE_PADDING, layout.LIST_ICON_SIZE }, { 260, 48, 2, 4, 34 })
  Assert.equal(layout.LIST_MIN_WIDTH, 180)
  Assert.same({ layout.DETAILS_HEADER_HEIGHT, layout.DETAILS_PADDING, layout.ACTION_BAR_HEIGHT, layout.BAND_HEIGHT }, { 62, 16, 44, 36 })
  -- Details spec A.1-A.2: the header's round icon and the info strip under the header.
  Assert.same({ layout.HEADER_ICON_SIZE, layout.INFO_STRIP_HEIGHT }, { 36, 24 })
  Assert.same(layout.CONTENT_INSET, { 4, -60, -6, 4 })
  -- A settings page's padding, inside its scroll content; the scroll bar sizes itself (UI/ScrollBar.lua).
  Assert.same(layout.PAGE_PADDING, { left = 16, right = 16, top = 12, bottom = 12 })
  Assert.same({ layout.SCROLL_INSET, layout.SCROLL_BAR_WIDTH }, {}, "the old knob room is gone")
  Assert.equal(Theme.ART.GEAR_ATLAS, "QuestLog-icon-setting")
  Assert.equal(Theme.ART.PANEL_BACKGROUND, "Professions-background-summarylist")
  Assert.equal(Theme.ART.WIDE_PANEL_BACKGROUND, "auctionhouse-background-index")
  Assert.equal(Theme.ART.SIZE_GRABBER_UP, "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  Assert.equal(Theme.ART.SIZE_GRABBER_DOWN, "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  Assert.equal(Theme.ART.SIZE_GRABBER_HIGHLIGHT, "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  Assert.same(Theme.COLORS.headerFill, { 0.09, 0.08, 0.07, 0.60 })
  Assert.same(Theme.COLORS.divider, { 1, 1, 1, 0.08 })
  -- Lead states, shared by the dots and the ledger counts: blue greeted, green replied.
  Assert.same({ Theme.COLORS.greeted, Theme.COLORS.replied }, { { 0.12, 0.72, 0.96, 1.0 }, { 0.30, 0.82, 0.40, 1.0 } })
  Assert.equal(Theme.FONTS.heading, "GameFontNormalLarge")
  -- The recipe mute switch (atlases and files seen in the retail client, 2026-10-25); no bell left.
  local art = Theme.ART
  Assert.same(
    { art.SPEAKER_ATLAS, art.SPEAKER_FILE, art.MUTED_ATLAS, art.MUTED_FILE, art.BELL_FILE },
    { "voicechat-icon-speaker", "Interface\\Common\\VoiceChat-Speaker", "voicechat-icon-speaker-mute", "Interface\\Common\\VoiceChat-Muted" }
  )
  Wow.reset()
end
