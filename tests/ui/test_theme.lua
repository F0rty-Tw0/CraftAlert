local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

-- The split-view numbers and art names: WhisperMessenger's constants, copied (spec A.2-A.4).
return function()
  Wow.reset()
  local Theme = Fresh.require("UI.Theme")
  local layout = Theme.LAYOUT
  Assert.same({ layout.LIST_WIDTH, layout.ROW_HEIGHT, layout.LIST_ROW_INSET, layout.PANE_PADDING, layout.LIST_ICON_SIZE }, { 260, 48, 2, 4, 34 })
  Assert.same(
    { layout.DETAILS_HEADER_HEIGHT, layout.DETAILS_PADDING, layout.DETAILS_GAP, layout.ACTION_BAR_HEIGHT, layout.BAND_HEIGHT },
    { 56, 16, 12, 44, 36 }
  )
  Assert.same(layout.CONTENT_INSET, { 4, -60, -6, 4 })
  Assert.equal(Theme.ART.PANEL_BACKGROUND, "Professions-background-summarylist")
  Assert.equal(Theme.ART.WIDE_PANEL_BACKGROUND, "auctionhouse-background-index")
  Assert.equal(Theme.ART.SIZE_GRABBER_UP, "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  Assert.equal(Theme.ART.SIZE_GRABBER_DOWN, "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  Assert.equal(Theme.ART.SIZE_GRABBER_HIGHLIGHT, "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  Assert.same(Theme.COLORS.headerFill, { 0.09, 0.08, 0.07, 0.60 })
  Assert.same(Theme.COLORS.divider, { 1, 1, 1, 0.08 })
  Assert.equal(Theme.FONTS.heading, "GameFontNormalLarge")
  Wow.reset()
end
