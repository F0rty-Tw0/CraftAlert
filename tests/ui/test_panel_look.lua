local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")
local LookFixture = require("tests.helpers.look_fixture")

-- PanelLook.FromWM turns WM's GetLook answer into a look value: native unless the answer is a table
-- with a known hud and all ten colours, each four numbers.

local function testBadAnswersAreNative()
  local PanelLook = Fresh.require("UI.PanelLook")
  for _, answer in ipairs({ false, true, "retail", 5 }) do
    Assert.equal(PanelLook.FromWM(answer), PanelLook.NATIVE, tostring(answer))
  end
  Assert.equal(PanelLook.FromWM(nil), PanelLook.NATIVE)
  Assert.equal(PanelLook.FromWM({ colors = LookFixture.answer("off").colors }), PanelLook.NATIVE, "no hud")
  for _, hud in ipairs({ "HUD", "Retail", "modern", 5, true }) do
    Assert.equal(PanelLook.FromWM(LookFixture.answer(hud)), PanelLook.NATIVE, "hud " .. tostring(hud))
  end
  Assert.equal(PanelLook.FromWM({ hud = "off" }), PanelLook.NATIVE, "no colors")
  Assert.equal(PanelLook.FromWM({ hud = "off", colors = "x" }), PanelLook.NATIVE, "colors not a table")
end

local function testEachStyle()
  local PanelLook = Fresh.require("UI.PanelLook")
  for hud, mode in pairs({ off = "flat", classic = "classic", retail = "retail" }) do
    local answer = LookFixture.answer(hud)
    local look = PanelLook.FromWM(answer)
    Assert.equal(look.mode, mode, hud)
    Assert.equal(look.colors, answer.colors, hud .. ": the colours are the answer's")
  end
end

local function testBadColourIsNative()
  local PanelLook = Fresh.require("UI.PanelLook")
  for _, key in ipairs(LookFixture.KEYS) do
    for label, bad in pairs({ missing = false, short = { 1, 2, 3 }, text = { 1, 2, 3, "x" }, long = { 1, 2, 3, 4, 5 }, scalar = "red" }) do
      local answer = LookFixture.answer("retail")
      answer.colors[key] = bad or nil
      Assert.equal(PanelLook.FromWM(answer), PanelLook.NATIVE, key .. " " .. label)
    end
  end
end

local function testColor()
  local PanelLook = Fresh.require("UI.PanelLook")
  local fallback = { 9, 9, 9, 9 }
  local flat = PanelLook.FromWM(LookFixture.answer("off"))
  Assert.equal(PanelLook.NATIVE.mode, "native")
  Assert.equal(PanelLook.NATIVE.colors, nil)
  Assert.equal(PanelLook.Color(flat, "bg_primary", fallback), flat.colors.bg_primary)
  Assert.equal(PanelLook.Color(flat, "no_such_key", fallback), fallback)
  Assert.equal(PanelLook.Color(PanelLook.NATIVE, "bg_primary", fallback), fallback)
end

return function()
  testBadAnswersAreNative()
  testEachStyle()
  testBadColourIsNative()
  testColor()
  Wow.reset()
end
