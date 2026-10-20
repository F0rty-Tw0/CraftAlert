local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local SettingsFixture = require("tests.helpers.settings_fixture")

-- A public Settings API that records what it is given.
local function stubSettings()
  local registered = { categories = {}, addOn = {} }
  Wow.stub("Settings", {
    RegisterCanvasLayoutCategory = function(frame, name)
      local category = { frame = frame, name = name }
      registered.categories[#registered.categories + 1] = category
      return category
    end,
    RegisterAddOnCategory = function(category)
      registered.addOn[#registered.addOn + 1] = category
    end,
  })
  return registered
end

local function buttonsUnder(parent)
  local found = {}
  for _, frame in ipairs(Wow.frames) do
    if frame.frameType == "Button" and frame.parent == parent then
      found[#found + 1] = frame
    end
  end
  return found
end

-- §9: one Blizzard Settings category holding one button that opens the settings window.
local function testOneCategoryOneButton()
  local ns = SettingsFixture.load()
  local registered = stubSettings()
  local category = ns.BlizzardCategory.Register()
  Assert.equal(#registered.categories, 1)
  Assert.same(registered.addOn, { category }, "listed under AddOns")
  Assert.equal(category.name, "Craft Alert")
  local buttons = buttonsUnder(category.frame)
  Assert.equal(#buttons, 1, "one button")
  Assert.equal(buttons[1].label:GetText(), "Open Craft Alert settings")
  Assert.equal(SettingsFixture.window(), nil, "the window waits for the click (§4.4 rule 5)")
  Widgets.click(buttons[1])
  Assert.equal(SettingsFixture.window():IsShown(), true)
  Widgets.click(buttons[1])
  Assert.equal(SettingsFixture.window():IsShown(), true, "a second click keeps it open")
  -- Bootstrap calls it once; a second call registers nothing new.
  Assert.equal(ns.BlizzardCategory.Register(), category)
  Assert.equal(#registered.categories, 1)
end

-- A client without the canvas-layout API (an older Classic Settings, or none) gets no category;
-- /ca config still opens the window.
local function testMissingApi()
  local ns = SettingsFixture.load()
  local frames = #Wow.frames
  Wow.stub("Settings", nil)
  Assert.equal(ns.BlizzardCategory.Register(), nil)
  Wow.stub("Settings", { RegisterAddOnCategory = function() end })
  Assert.equal(ns.BlizzardCategory.Register(), nil)
  Assert.equal(#Wow.frames, frames, "no frame made")
end

return function()
  testOneCategoryOneButton()
  testMissingApi()
end
