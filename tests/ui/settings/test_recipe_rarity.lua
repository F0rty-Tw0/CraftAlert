local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local SettingsFixture = require("tests.helpers.settings_fixture")
local CraftersFixture = require("tests.helpers.crafters_fixture")

local open, row = SettingsFixture.open, SettingsFixture.row
local BS, crafters, rowOf = CraftersFixture.BS, CraftersFixture.crafters, CraftersFixture.rowOf

-- The Crafters page's recipe names in the crafted item's rarity colour (UI/Settings/RecipeRarity.lua).
local EPIC = { 0.64, 0.21, 0.93 }

-- Stubs the item API: `quality` maps itemID -> quality (an absent id is uncached); returns the
-- load requests made so far and a function that tells whether the item event is registered.
local function stubItems(quality)
  local requests = {}
  Wow.stub("C_Item", {
    GetItemInfo = function(id)
      if quality[id] then
        return "Item " .. id, nil, quality[id]
      end
    end,
    GetItemQualityColor = function(q)
      return EPIC[1], EPIC[2], EPIC[3], "ff" .. q
    end,
    RequestLoadItemDataByID = function(id)
      requests[#requests + 1] = id
    end,
  })
  local function registered()
    for _, frame in ipairs(Wow.frames) do
      if frame:IsEventRegistered("GET_ITEM_INFO_RECEIVED") then
        return true
      end
    end
    return false
  end
  return requests, registered
end

-- A recipe's name is drawn in the crafted item's rarity colour; a recipe without an item is
-- white. A muted or untracked row keeps the colour at the icon's dim alpha.
local function testCraftersRecipeRarity()
  local ns = SettingsFixture.load({
    db = function(accountDb)
      crafters(accountDb)
      accountDb.characters["Me-Realm"].recipes = {
        [9001] = { item = 501, name = "A Belt", prof = BS },
        [9002] = { name = "B Bracer", prof = BS },
        [9003] = { item = 501, name = "C Belt", prof = BS, muted = true },
        [9004] = { item = 501, name = "D Belt", prof = BS, bind = 0 },
      }
    end,
  })
  stubItems({ [501] = 4 })
  open(ns, "Crafters")
  Assert.same(rowOf(9001).name.textColor, { EPIC[1], EPIC[2], EPIC[3], 1 }, "epic")
  Assert.same(rowOf(9002).name.textColor, { 1, 1, 1, 1 }, "no item: white")
  local dim = ns.Theme.DIM_ALPHA
  Assert.same(rowOf(9003).name.textColor, { EPIC[1], EPIC[2], EPIC[3], dim }, "muted: same colour, dim")
  Assert.same(rowOf(9004).name.textColor, { EPIC[1], EPIC[2], EPIC[3], dim }, "untracked: same colour, dim")
  -- Rows are reused: a repaint with another recipe sets the colour again.
  Widgets.type(row("Search recipes").input, "bracer")
  Assert.same(rowOf(9002).name.textColor, { 1, 1, 1, 1 }, "a reused row is repainted")
end

-- An uncached item paints white and asks the client once; the answer repaints it in colour. A
-- failed load stays white and is not asked for again. The event is registered only while an
-- item is pending, and an answer for another item changes nothing.
local function testCraftersRecipeRarityLoads()
  local ns = SettingsFixture.load({
    db = function(accountDb)
      crafters(accountDb)
      accountDb.characters["Me-Realm"].recipes = {
        [9001] = { item = 501, name = "A Belt", prof = BS },
        [9002] = { item = 502, name = "B Belt", prof = BS },
      }
    end,
  })
  local quality = {}
  local requests, registered = stubItems(quality)
  Assert.falsy(registered(), "nothing pending: not registered")
  open(ns, "Crafters")
  local white = { 1, 1, 1, 1 }
  Assert.same(rowOf(9001).name.textColor, white, "uncached: white")
  Assert.same(requests, { 501, 502 }, "one request each")
  Assert.truthy(registered())
  -- Every name holds a space: a search that lists them all, as a repaint before the answer.
  Widgets.type(row("Search recipes").input, " ")
  Assert.same(requests, { 501, 502 }, "no second request")

  quality[501] = 4
  Wow.fireEvent("GET_ITEM_INFO_RECEIVED", 777, true)
  Assert.same(rowOf(9001).name.textColor, white, "another item's answer: unchanged")
  Assert.truthy(registered())
  Wow.fireEvent("GET_ITEM_INFO_RECEIVED", 501, true)
  Assert.same(rowOf(9001).name.textColor, { EPIC[1], EPIC[2], EPIC[3], 1 }, "answered: repainted")
  Assert.truthy(registered(), "502 is still pending")

  Wow.fireEvent("GET_ITEM_INFO_RECEIVED", 502, false)
  Assert.same(rowOf(9002).name.textColor, white, "failed load: white")
  Assert.falsy(registered(), "nothing pending: unregistered")
  Widgets.type(row("Search recipes").input, "belt")
  Assert.same(requests, { 501, 502 }, "a failed item is not asked for again")
  Assert.same(rowOf(9002).name.textColor, white)
end

return function()
  testCraftersRecipeRarity()
  testCraftersRecipeRarityLoads()
  Wow.reset()
end
