local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local SettingsFixture = require("tests.helpers.settings_fixture")
local CraftersFixture = require("tests.helpers.crafters_fixture")

local open, row, take = SettingsFixture.open, SettingsFixture.row, SettingsFixture.take
local BS, ENCH, crafters, rowOf, iconOf =
  CraftersFixture.BS, CraftersFixture.ENCH, CraftersFixture.crafters, CraftersFixture.rowOf, CraftersFixture.iconOf

-- The Crafters page's mute switches (UI/Settings/RecipeMute.lua) and the buttons that mute many
-- recipes at once (UI/Settings/RecipeList.lua): Mute all / Unmute all, "Only <expansion>", and
-- the untracked rows' speakers.
-- The mute icon's tooltip in the house style (gold title, white text, green instruction); a click
-- under the pointer repaints it for the new state.
local function testCraftersMuteTooltip()
  local ns = SettingsFixture.load({ db = crafters })
  open(ns, "Crafters")
  local tooltip, mute = ns.Tooltip.Get(), rowOf(9001).mute
  Widgets.fire(mute, "OnEnter")
  Assert.equal(tooltip.owner, mute)
  Assert.same(tooltip.lines, { "Alerts on", "Requests for this recipe alert you", " ", "Click: mute" })
  Assert.same(tooltip.colors, { { 1, 0.82, 0 }, { 1, 1, 1 }, {}, { 0.1, 1, 0.1 } })
  Widgets.click(mute)
  Assert.same(tooltip.lines, { "Muted", "Requests for this recipe do not alert you", " ", "Click: unmute" })
  Widgets.fire(mute, "OnLeave")
  Assert.equal(tooltip:IsShown(), false)
end

-- The switch keeps its own state (`recipe`, `muted`): a parent without an `item` field, as a
-- Blizzard recipe row, reads fine, and a repaint under the pointer follows the new state.
local function testMuteKeepsOwnState()
  local ns = SettingsFixture.load({ db = crafters })
  local mute = ns.RecipeMute.Create(_G["CreateFrame"]("Frame", nil, _G["UIParent"]), function() end)
  local tooltip = ns.Tooltip.Get()
  mute.recipe = { bind = 4 }
  ns.RecipeMute.Paint(mute, true, false)
  Widgets.fire(mute, "OnEnter")
  Assert.same(tooltip.lines, { "Muted", "Requests for this recipe do not alert you", " ", "Click: unmute" })
  ns.RecipeMute.Paint(mute, false, false)
  Assert.same(tooltip.lines, { "Alerts on", "Requests for this recipe alert you", " ", "Click: mute" }, "a shown tooltip follows Paint")
  Widgets.fire(mute, "OnLeave")

  mute.recipe = { bind = 0 }
  ns.RecipeMute.Paint(mute, false, true)
  Widgets.fire(mute, "OnEnter")
  Assert.same(tooltip.lines, {
    "Not tracked",
    "Items with no binding (materials, potions, gems) do not alert",
    " ",
    "Turn on Track unbound items in Craft Alert's General settings",
  })
  Widgets.fire(mute, "OnLeave")
end

local function mutedNames(character)
  local names = {}
  for _, recipe in pairs(character.recipes) do
    if recipe.muted then
      names[#names + 1] = recipe.name
    end
  end
  table.sort(names)
  return names
end

-- Mute all / Unmute all act on the recipes the search leaves in the list, rebuild the index once,
-- and rebuild nothing when no recipe changes.
local function testCraftersMuteAll()
  local ns, db, refreshes = SettingsFixture.load({
    db = function(accountDb)
      crafters(accountDb)
      accountDb.characters["Me-Realm"].recipes = {
        [9001] = { item = 501, name = "Alpha Plate", prof = BS },
        [9002] = { item = 502, name = "Beta Plate", prof = BS },
        [9003] = { item = 503, name = "Gamma Sword", prof = BS },
        [9004] = { name = "Enchant Plate", prof = ENCH },
      }
    end,
  })
  local me = db.characters["Me-Realm"]
  open(ns, "Crafters")
  take(refreshes)
  local window = SettingsFixture.window()
  local function press(label)
    Widgets.click(SettingsFixture.button(window, label))
  end

  press("Unmute all")
  Assert.same(take(refreshes), {}, "nothing muted: nothing to rebuild")
  Widgets.type(row("Search recipes").input, "plate")
  press("Mute all")
  Assert.same(mutedNames(me), { "Alpha Plate", "Beta Plate" }, "only the listed recipes")
  Assert.same(take(refreshes), { "rebuild:mute" }, "one request for both")
  Assert.equal(iconOf(9001).desaturated, true, "the list repaints")
  press("Mute all")
  Assert.same(take(refreshes), {}, "all muted already")
  Widgets.type(row("Search recipes").input, "beta")
  press("Unmute all")
  Assert.same(mutedNames(me), { "Alpha Plate" }, "only the listed recipe")
  Assert.same(take(refreshes), { "rebuild:mute" })
  Widgets.type(row("Search recipes").input, "")
  press("Unmute all")
  Assert.same(mutedNames(me), {})
  Assert.equal(me.recipes[9001].muted, nil, "unmuted recipes keep no muted field")
  Assert.same(take(refreshes), { "rebuild:mute" })
  Widgets.type(row("Search recipes").input, "zzz")
  press("Mute all")
  Assert.same(mutedNames(me), {}, "an empty list mutes nothing")
  Assert.same(take(refreshes), {})
end

-- The "Only <expansion>" button under the shown recipes, or nil. Found while shown; tests keep the frame.
local function onlyButton()
  for _, frame in ipairs(Wow.frames) do
    local text = frame.label and frame.label:GetText()
    if type(text) == "string" and text:find("^Only ") and SettingsFixture.visible(frame) then
      return frame
    end
  end
  return nil
end

-- "Only <expansion>": the profession's current line is its highest stored `line`; the label names
-- its expansion (one lookup per render), else "Only current expansion". A click keeps alerts only
-- for that line over the whole profession (the search ignored, recipes without a line left alone,
-- other professions and characters untouched) with one rebuild; nothing to change → no rebuild.
-- No recipe with a line → no button.
local function testCraftersOnlyExpansion()
  local ns, db, refreshes = SettingsFixture.load({
    db = function(accountDb)
      crafters(accountDb)
      accountDb.characters["Me-Realm"].recipes = {
        [9001] = { name = "Old Belt", prof = BS, line = 2540 },
        [9002] = { name = "War Belt", prof = BS, line = 2883 },
        [9003] = { name = "New Belt", prof = BS, line = 2918, muted = true },
        [9004] = { name = "New Helm", prof = BS, line = 2918 },
        [9005] = { name = "Lost Belt", prof = BS, muted = true },
        [9006] = { name = "Lost Helm", prof = BS },
        [9010] = { name = "Enchant Bracer - Health", prof = ENCH },
      }
      accountDb.characters["Alt-Realm"].recipes = { [9001] = { name = "Old Belt", prof = BS, line = 2540 } }
    end,
  })
  local names = { [2540] = "Classic", [2883] = "Khaz Algar", [2918] = "Midnight" }
  local lookups = {}
  Wow.stub("C_TradeSkillUI", {
    GetProfessionInfoBySkillLineID = function(id)
      lookups[#lookups + 1] = id
      return { professionID = id, expansionName = names[id] }
    end,
  })
  local me = db.characters["Me-Realm"]
  open(ns, "Crafters")
  take(refreshes)
  local button = assert(onlyButton(), "the button shows")
  Assert.equal(button.label:GetText(), "Only Midnight")
  Assert.equal(lookups[#lookups], 2918, "the label asks for the highest line")
  local muteBar = SettingsFixture.button(SettingsFixture.window(), "Mute all").parent
  Assert.equal(button.parent.points[1][2], muteBar, "its own row under Mute all / Unmute all")
  Assert.same(button.points, { { "TOPLEFT", button.parent, "TOPLEFT", 0, 0 }, { "TOPRIGHT", button.parent, "TOPRIGHT", 0, 0 } }, "full width")

  Widgets.type(row("Search recipes").input, "new")
  local asked = #lookups
  Widgets.click(button)
  Assert.equal(#lookups - asked, 1, "the click asks nothing per recipe; the re-render asks the label once")
  Assert.same(mutedNames(me), { "Lost Belt", "Old Belt", "War Belt" }, "older lines muted, the current one on, no-line recipes as they were")
  Assert.equal(me.recipes[9003].muted, nil, "unmuted recipes keep no muted field")
  Assert.same(take(refreshes), { "rebuild:mute" }, "one request")
  Assert.equal(me.professions[BS].newestLine, 2918, "the click remembers the line")
  Assert.equal(db.characters["Alt-Realm"].recipes[9001].muted, nil, "another character is untouched")
  Assert.equal(me.recipes[9010].muted, nil, "another profession is untouched")
  Widgets.click(button)
  Assert.same(take(refreshes), {}, "nothing to change: no rebuild")

  -- No expansion name (nil, empty, or a client without the call) → the generic label.
  names[2918] = ""
  Widgets.pick(row("Profession").input, ENCH)
  Assert.equal(onlyButton(), nil, "no recipe with a line: no button")
  Assert.equal(button:IsShown(), false)
  Widgets.pick(row("Profession").input, BS)
  Assert.equal(button.label:GetText(), "Only current expansion")
  Wow.stub("C_TradeSkillUI", {})
  Widgets.pick(row("Profession").input, ENCH)
  Widgets.pick(row("Profession").input, BS)
  Assert.equal(button:IsShown(), true)
  Assert.equal(button.label:GetText(), "Only current expansion", "no GetProfessionInfoBySkillLineID")
end

-- 8.0 order: Classic 2540 (low recipe IDs) and Kul Tiran 2533 (high IDs): the button's current
-- line is 2533 (median recipe-ID rank, not the highest line ID), and a click mutes Classic.
local function testCraftersOnlyNewestByRank()
  local ns, db, refreshes = SettingsFixture.load({
    db = function(accountDb)
      crafters(accountDb)
      accountDb.characters["Me-Realm"].recipes = {
        [2385] = { name = "Old Belt", prof = BS, line = 2540 },
        [2386] = { name = "Old Helm", prof = BS, line = 2540 },
        [250001] = { name = "KT Belt", prof = BS, line = 2533 },
        [250002] = { name = "KT Helm", prof = BS, line = 2533 },
      }
    end,
  })
  local names = { [2540] = "Classic", [2533] = "Battle for Azeroth" }
  Wow.stub("C_TradeSkillUI", {
    GetProfessionInfoBySkillLineID = function(id)
      return { professionID = id, expansionName = names[id] }
    end,
  })
  local me = db.characters["Me-Realm"]
  open(ns, "Crafters")
  take(refreshes)
  local button = assert(onlyButton())
  Assert.equal(button.label:GetText(), "Only Battle for Azeroth")
  Widgets.click(button)
  Assert.same(mutedNames(me), { "Old Belt", "Old Helm" })
  Assert.equal(me.professions[BS].newestLine, 2533)
  Assert.same(take(refreshes), { "rebuild:mute" })
end

-- Items with no binding never alert while "Track unbound items" is off (Index): their rows are
-- grey and dim, an unmuted one's speaker greyed, a muted one's the crossed speaker; the speaker
-- explains why. The toggle sits under the list, rebuilds the index and repaints the rows.
local function testCraftersUntracked()
  local ns, db, refreshes = SettingsFixture.load({
    db = function(accountDb)
      crafters(accountDb)
      accountDb.characters["Me-Realm"].recipes = {
        [9001] = { name = "A Bar", prof = BS, bind = 0 },
        [9002] = { name = "B Flask", prof = BS, bind = 0, muted = true },
        [9003] = { name = "C Belt", prof = BS, bind = 1 },
        [9004] = { name = "D Helm", prof = BS },
        [9005] = { name = "E Gem", prof = BS, bind = 0 },
      }
    end,
  })
  local me = db.characters["Me-Realm"]
  open(ns, "Crafters")
  take(refreshes)
  local function look(key)
    local recipeRow = rowOf(key)
    return { recipeRow.icon.desaturated, recipeRow.icon.alpha, recipeRow.mute.icon.atlas, recipeRow.mute.icon.desaturated }
  end
  local dim = ns.Theme.DIM_ALPHA
  Assert.same(look(9001), { true, dim, "voicechat-icon-speaker", true }, "untracked: grey row, grey speaker")
  Assert.same(look(9002), { true, dim, "voicechat-icon-speaker-mute", false }, "untracked and muted: the crossed speaker")
  Assert.same(look(9003), { false, 1, "voicechat-icon-speaker", false }, "bound: as before")
  Assert.same(look(9004), { false, 1, "voicechat-icon-speaker", false }, "bind not read yet: tracked")

  local tooltip, mute = ns.Tooltip.Get(), rowOf(9001).mute
  local why = {
    "Not tracked",
    "Items with no binding (materials, potions, gems) do not alert",
    " ",
    "Turn on Track unbound items in Craft Alert's General settings",
  }
  Widgets.fire(mute, "OnEnter")
  Assert.same(tooltip.lines, why)
  Assert.same(tooltip.colors, { { 1, 0.82, 0 }, { 1, 1, 1 }, {}, { 0.1, 1, 0.1 } })
  Widgets.click(mute)
  Assert.equal(me.recipes[9001].muted, true, "the speaker still mutes")
  Assert.same(take(refreshes), { "rebuild:mute" })
  Assert.same(tooltip.lines, why, "still untracked")
  Widgets.fire(mute, "OnLeave")

  local label = "Track unbound items (materials, potions, gems)"
  open(ns, "General")
  local toggle = row(label)
  Assert.equal(toggle.input:GetChecked(), false)
  Widgets.click(toggle.input)
  Assert.equal(db.settings.includeUnbound, true)
  Assert.same(take(refreshes), { "rebuild:includeUnbound" })
  open(ns, "Crafters")
  Assert.same(look(9005), { false, 1, "voicechat-icon-speaker", false }, "tracked now: the list repaints")
  Assert.same(look(9002), { true, dim, "voicechat-icon-speaker-mute", false }, "muted stays muted")
  Widgets.fire(rowOf(9005).mute, "OnEnter")
  Assert.equal(tooltip.lines[1], "Alerts on")
  Widgets.fire(rowOf(9005).mute, "OnLeave")
  open(ns, "General")
  Widgets.click(row(label).input)
  Assert.equal(db.settings.includeUnbound, false)
  Assert.same(take(refreshes), { "rebuild:includeUnbound" })
  open(ns, "Crafters")
  Assert.same(look(9005), { true, dim, "voicechat-icon-speaker", true })

  -- The page shows what the db holds each time it opens.
  db.settings.includeUnbound = true
  ns.LeadsWindow.ToggleSettings()
  open(ns, "General")
  Assert.equal(row(label).input:GetChecked(), true)
  open(ns, "Crafters")
  Assert.same(look(9005), { false, 1, "voicechat-icon-speaker", false })
end

-- Leaving a speaker or a recipe row hides only a tooltip it owns: one another frame took since
-- (the client sends OnLeave late, or after the next OnEnter) stays.
local function testLeaveKeepsAnotherOwnersTooltip()
  local ns = SettingsFixture.load({ db = crafters })
  open(ns, "Crafters")
  local tooltip, recipeRow = ns.Tooltip.Get(), rowOf(9001)
  local other = _G["CreateFrame"]("Button", nil, _G["UIParent"])
  for _, frame in ipairs({ recipeRow.mute, recipeRow }) do
    Widgets.fire(frame, "OnEnter")
    tooltip:SetOwner(other, "ANCHOR_RIGHT")
    tooltip:Show()
    Widgets.fire(frame, "OnLeave")
    Assert.same({ tooltip:IsShown(), tooltip.owner }, { true, other }, "another frame's tooltip stays")
  end
end

return function()
  testCraftersMuteTooltip()
  testMuteKeepsOwnState()
  testCraftersMuteAll()
  testCraftersOnlyExpansion()
  testCraftersOnlyNewestByRank()
  testCraftersUntracked()
  testLeaveKeepsAnotherOwnersTooltip()
  Wow.reset()
end
