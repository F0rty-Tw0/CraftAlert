local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

local FALLBACK = { "TOP", 0, -160 }

local function load(ui)
  Wow.reset()
  Wow.stub("CraftAlertDB", { ui = ui })
  Fresh.require("Core.FlavorCompat")
  Fresh.require("UI.Theme")
  return Fresh.require("UI.FrameKit")
end

-- Where FrameKit.Place anchored a new frame: point, relativePoint, x, y on UIParent.
local function placed(FrameKit)
  local frame = rawget(_G, "CreateFrame")("Frame")
  frame:SetPoint("CENTER", nil, "CENTER", 1, 1) -- Place must clear this one
  FrameKit.Place(frame, "toast", FALLBACK)
  local point, relativeTo, relativePoint, x, y = frame:GetPoint()
  Assert.truthy(rawequal(relativeTo, rawget(_G, "UIParent")), "anchored on UIParent")
  Assert.equal(#frame.points, 1, "the old anchor is cleared")
  return { point, relativePoint, x, y }
end

-- A well-formed saved position is used as it is.
local function testSavedPosition()
  local FrameKit = load({ toast = { point = "BOTTOMLEFT", relativePoint = "TOPRIGHT", x = 12, y = -4 } })
  Assert.same(placed(FrameKit), { "BOTTOMLEFT", "TOPRIGHT", 12, -4 })
end

-- A hand-edited or half-written record falls back to the default anchor, never errors.
local function testMalformedFallsBack()
  local malformed = {
    { point = "MIDDLE", relativePoint = "TOP", x = 0, y = 0 },
    { point = "TOP", relativePoint = 5, x = 0, y = 0 },
    { point = "TOP", relativePoint = "TOP", x = "10", y = 0 },
    { point = "TOP", relativePoint = "TOP", x = 0 },
    {},
  }
  for i, record in ipairs(malformed) do
    local FrameKit = load({ toast = record })
    Assert.same(placed(FrameKit), { "TOP", "TOP", 0, -160 }, "record " .. i)
  end
  -- A saved record that is not a table is replaced by an empty one; no db at all still places.
  local FrameKit = load({ toast = "junk" })
  Assert.same(placed(FrameKit), { "TOP", "TOP", 0, -160 })
  Assert.same(rawget(_G, "CraftAlertDB").ui.toast, {})
  FrameKit = load(nil)
  Wow.stub("CraftAlertDB", nil)
  Assert.same(placed(FrameKit), { "TOP", "TOP", 0, -160 })
end

-- Art takes the atlas when the client knows it, else the fallback file, else hides the texture.
local function testArt()
  local FrameKit = load({})
  local frame = rawget(_G, "CreateFrame")("Frame")
  local known = { Known = true }
  Wow.stub("C_Texture", {
    GetAtlasInfo = function(name)
      return known[name] and { width = 1 } or nil
    end,
  })
  local t = frame:CreateTexture()
  Assert.equal(FrameKit.Art(t, "Known", "InterfaceX", "ADD"), true)
  Assert.equal(t.atlas, "Known")
  Assert.equal(t.texture, nil)
  Assert.equal(t.blendMode, "ADD")
  t = frame:CreateTexture()
  Assert.equal(FrameKit.Art(t, "Missing", "InterfaceX", "ADD"), false)
  Assert.equal(t.atlas, nil)
  Assert.equal(t.texture, "InterfaceX")
  Assert.equal(t.blendMode, "ADD")
  Assert.equal(t.shown, true)
  t = frame:CreateTexture()
  Assert.equal(FrameKit.Art(t, "Missing"), false)
  Assert.equal(t.shown, false)
  -- A raising GetAtlasInfo and a missing C_Texture both count as "atlas missing".
  Wow.stub("C_Texture", {
    GetAtlasInfo = function()
      error("boom")
    end,
  })
  t = frame:CreateTexture()
  Assert.equal(FrameKit.Art(t, "Known", "InterfaceX"), false)
  Assert.equal(t.texture, "InterfaceX")
  Wow.stub("C_Texture", nil)
  t = frame:CreateTexture()
  Assert.equal(FrameKit.Art(t, "Known"), false)
  Assert.equal(t.shown, false)
end

-- AtlasExists: the client knows the atlas; a nil answer, a raising GetAtlasInfo or no C_Texture
-- count as unknown.
local function testAtlasExists()
  local FrameKit = load({})
  Wow.stub("C_Texture", {
    GetAtlasInfo = function(name)
      return name == "Known" and { width = 1 } or nil
    end,
  })
  Assert.same({ FrameKit.AtlasExists("Known"), FrameKit.AtlasExists("Missing") }, { true, false })
  Wow.stub("C_Texture", {
    GetAtlasInfo = function()
      error("boom")
    end,
  })
  Assert.equal(FrameKit.AtlasExists("Known"), false)
  Wow.stub("C_Texture", nil)
  Assert.equal(FrameKit.AtlasExists("Known"), false)
end

-- PaintPanel draws a pane atlas when the client has it; with no atlas it touches nothing (never hides).
local function testPaintPanel()
  local FrameKit = load({})
  local texture = _G["CreateFrame"]("Frame"):CreateTexture(nil, "BACKGROUND")
  Assert.equal(FrameKit.PaintPanel(texture, "Professions-background-summarylist"), true)
  Assert.same({ texture.atlas, texture.blendMode }, { "Professions-background-summarylist", "BLEND" })
  Wow.stub("C_Texture", {
    GetAtlasInfo = function()
      return nil
    end,
  })
  local bare = _G["CreateFrame"]("Frame"):CreateTexture(nil, "BACKGROUND")
  Assert.equal(FrameKit.PaintPanel(bare, "x"), false)
  Assert.same({ bare.atlas, bare.blendMode }, { nil, nil }) -- left empty, never hidden
  Assert.equal(bare.shown, true)
  Wow.stub("C_Texture", {
    GetAtlasInfo = function()
      error("boom")
    end,
  })
  Assert.equal(FrameKit.PaintPanel(bare, "x"), false, "a raising GetAtlasInfo counts as unknown")
  Wow.stub("C_Texture", nil)
  Assert.equal(FrameKit.PaintPanel(bare, "x"), false)
end

local function testListHighlight()
  local FrameKit = load({})
  local Theme = require("CraftAlert.UI.Theme")
  local button = rawget(_G, "CreateFrame")("Button")
  local texture = FrameKit.ListHighlight(button)
  Assert.equal(texture.layer, "HIGHLIGHT")
  Assert.equal(texture.texture, Theme.ART.LIST_HOVER)
  Assert.equal(texture.blendMode, "ADD")
  Assert.equal(texture:GetAlpha(), Theme.ART.LIST_HOVER_ALPHA)
  Assert.same(texture.points, { { "ALL", button } })
end

-- The client's icon for a skill-line ID; a Classic name key, or a client without the API, has none.
local function testProfessionIcon()
  local FrameKit = load({})
  Assert.equal(FrameKit.ProfessionIcon(333), nil, "no C_TradeSkillUI")
  Wow.stub("C_TradeSkillUI", {
    GetTradeSkillTexture = function(id)
      return (id == 333 or id == "Enchanting") and 136244 or nil
    end,
  })
  Assert.equal(FrameKit.ProfessionIcon(333), 136244)
  Assert.equal(FrameKit.ProfessionIcon(164), nil, "unknown id")
  Assert.equal(FrameKit.ProfessionIcon("Enchanting"), nil, "Classic name key")
  Assert.equal(FrameKit.ProfessionIcon(nil), nil)
  Wow.stub("C_TradeSkillUI", {})
  Assert.equal(FrameKit.ProfessionIcon(333), nil, "no GetTradeSkillTexture")
end

-- The class colour of a class token, from RAID_CLASS_COLORS.
local function testClassColor()
  local FrameKit = load({})
  Assert.equal(FrameKit.ClassColor("MAGE"), nil, "no RAID_CLASS_COLORS")
  Wow.stub("RAID_CLASS_COLORS", { MAGE = { r = 0.25, g = 0.78, b = 0.92 } })
  Assert.same(FrameKit.ClassColor("MAGE"), { r = 0.25, g = 0.78, b = 0.92 })
  Assert.equal(FrameKit.ClassColor("ROGUE"), nil, "unknown token")
  Assert.equal(FrameKit.ClassColor(nil), nil)
  Assert.equal(FrameKit.ClassColor(5), nil, "non-string token")
end

-- A Theme colour's alpha folds into the colour (a colour code has none): one rule for the codes
-- and the opaque colour a text with codes takes.
local function testThemeColourFoldsAlpha()
  local FrameKit = load({})
  local halfWhite = { 1, 1, 1, 0.5 }
  Assert.equal(FrameKit.ThemeCode("x", halfWhite), "|cff7f7f7fx|r")
  Assert.equal(FrameKit.ThemeCode("x", { 1, 0, 0 }), "|cffff0000x|r", "no alpha: as given")
  Assert.same(FrameKit.Opaque(halfWhite), { 0.5, 0.5, 0.5, 1 })
end

-- A name in its class colour; without one, in the fallback Theme colour, else plain.
local function testClassCode()
  local FrameKit = load({})
  Assert.equal(FrameKit.ClassCode("Me", { r = 1, g = 0.5, b = 0 }), "|cffff7f00Me|r")
  Assert.equal(FrameKit.ClassCode("Me", nil, { 1, 1, 1, 1 }), "|cffffffffMe|r")
  Assert.equal(FrameKit.ClassCode("Me", nil), "Me")
end

-- r, g, b of a class colour; without one, of the fallback Theme colour (its alpha left out).
local function testClassRGB()
  local FrameKit = load({})
  Assert.same({ FrameKit.ClassRGB({ r = 1, g = 0.5, b = 0 }, { 0, 0, 0, 1 }) }, { 1, 0.5, 0 })
  Assert.same({ FrameKit.ClassRGB(nil, { 0.2, 0.4, 0.6, 0.5 }) }, { 0.2, 0.4, 0.6 })
end

-- Wrapping text, cut at maxLines lines only when given; a client without SetMaxLines still wraps.
local function testWrapped()
  local FrameKit = load({})
  local parent = rawget(_G, "CreateFrame")("Frame")
  local text = FrameKit.Wrapped(parent, "GameFontNormal", { 1, 1, 1, 1 }, 2)
  Assert.same({ text.wordWrap, text.maxLines, text.font, text.textColor }, { true, 2, "GameFontNormal", { 1, 1, 1, 1 } })
  local spy, capped = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal"), false
  function spy:SetMaxLines()
    capped = true
  end
  local spyParent = {
    CreateFontString = function()
      return spy
    end,
  }
  Assert.equal(FrameKit.Wrapped(spyParent, "GameFontNormal").wordWrap, true)
  Assert.equal(capped, false, "no maxLines: no cap")
  spy.SetMaxLines, spy.wordWrap = nil, false
  Assert.equal(FrameKit.Wrapped(spyParent, "GameFontNormal", nil, 2).wordWrap, true, "no SetMaxLines")
end

-- The localized name of a class token, from LOCALIZED_CLASS_NAMES_MALE.
local function testClassName()
  local FrameKit = load({})
  Assert.equal(FrameKit.ClassName("DRUID"), nil, "no LOCALIZED_CLASS_NAMES_MALE")
  Wow.stub("LOCALIZED_CLASS_NAMES_MALE", { DRUID = "Druid" })
  Assert.equal(FrameKit.ClassName("DRUID"), "Druid")
  Assert.equal(FrameKit.ClassName("ROGUE"), nil, "unknown token")
  Assert.equal(FrameKit.ClassName(nil), nil)
end

-- The old WhisperMessenger look is gone: no panel/title-bar builders, no surface or control colours
-- (`divider` is back as the split view's pane line, asserted in test_theme.lua).
local function testLookCodeGone()
  local FrameKit = load({})
  local Theme = Fresh.require("UI.Theme")
  Assert.equal(FrameKit.Panel, nil, "Panel")
  Assert.equal(FrameKit.Fill, nil, "Fill")
  Assert.equal(FrameKit.TitleBar, nil, "TitleBar")
  local deleted = { "surface", "chrome", "border", "toggleOn", "toggleOff", "knob", "option", "optionHover", "optionSelected", "input" }
  for _, key in ipairs(deleted) do
    Assert.equal(Theme.COLORS[key], nil, "COLORS." .. key)
  end
  local kept = { "textPrimary", "textSecondary", "textTimestamp", "accent", "badgeText", "greeted", "warning" }
  for _, key in ipairs(kept) do
    local color = Theme.COLORS[key]
    Assert.equal(type(color), "table", "COLORS." .. key)
    Assert.equal(#color, 4, "COLORS." .. key .. " has four numbers")
    for i = 1, 4 do
      Assert.equal(type(color[i]), "number", "COLORS." .. key .. "[" .. i .. "]")
    end
  end
  local gone = { "SWITCH_WIDTH", "KNOB_SIZE", "SLIDER_THUMB_WIDTH", "TITLE_BAR_HEIGHT" }
  for _, key in ipairs(gone) do
    Assert.equal(Theme.LAYOUT[key], nil, "LAYOUT." .. key)
  end
end

return function()
  testSavedPosition()
  testMalformedFallsBack()
  testArt()
  testAtlasExists()
  testPaintPanel()
  testListHighlight()
  testProfessionIcon()
  testClassColor()
  testClassName()
  testThemeColourFoldsAlpha()
  testClassCode()
  testClassRGB()
  testWrapped()
  testLookCodeGone()
  Wow.reset()
end
