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

-- The WhisperMessenger look is gone: no panel/title-bar builders, no surface or control colours.
local function testLookCodeGone()
  local FrameKit = load({})
  local Theme = Fresh.require("UI.Theme")
  Assert.equal(FrameKit.Panel, nil, "Panel")
  Assert.equal(FrameKit.Fill, nil, "Fill")
  Assert.equal(FrameKit.TitleBar, nil, "TitleBar")
  local deleted = { "surface", "chrome", "border", "divider", "toggleOn", "toggleOff", "knob", "option", "optionHover", "optionSelected", "input" }
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
  testListHighlight()
  testProfessionIcon()
  testClassColor()
  testLookCodeGone()
  Wow.reset()
end
