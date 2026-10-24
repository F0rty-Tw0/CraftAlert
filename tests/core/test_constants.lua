local Assert = require("tests.helpers.assert")
local Constants = require("CraftAlert.Core.Constants")

local FLAVOR_KEYS = { "retail", "forever", "era", "tbc", "wrath", "cata", "mop" }
local SHIPPED_SOUND_KITS = { 8959, 3081, 5274, 12867, 8960 }
local CHANNEL_FIELDS = { "trade", "services", "general", "lfg", "guild", "communities" }

return function()
  Assert.equal(type(Constants.version), "string")

  for _, key in ipairs(FLAVOR_KEYS) do
    local flavor = Constants.flavors[key]
    Assert.truthy(flavor, key .. " flavor row")
    Assert.truthy(flavor.learnSignal == 1 or flavor.learnSignal == 2 or flavor.learnSignal == 3, key .. " learnSignal")
    Assert.equal(type(flavor.linkInLearnText), "boolean", key .. " linkInLearnText")
    Assert.equal(type(flavor.craftFrame), "boolean", key .. " craftFrame")
    for _, field in ipairs(CHANNEL_FIELDS) do
      Assert.equal(type(flavor.channels[field]), "boolean", key .. " channels." .. field)
    end
    Assert.same(flavor.soundKits, SHIPPED_SOUND_KITS, key .. " soundKits")
    Assert.truthy(flavor.channels.trade, key .. " has Trade")
    Assert.truthy(flavor.channels.general, key .. " has General")

    local templates = Constants.templates[key]
    Assert.equal(templates.item, "Hi! I can craft {item}.")
    Assert.equal(templates.profession, "Hi! I have {profession}, what do you need?")
    Assert.equal(templates.altProfession, "Hi! My alt {crafter} has {profession}, what do you need?")
  end

  -- flavor-choices.md: Retail and Forever learn through NEW_RECIPE_LEARNED, Classic through the system message.
  Assert.equal(Constants.flavors.retail.learnSignal, 2)
  Assert.equal(Constants.flavors.forever.learnSignal, 2)
  Assert.equal(Constants.flavors.retail.learnPatternGlobal, nil)
  for _, key in ipairs({ "era", "tbc", "wrath", "cata", "mop" }) do
    Assert.equal(Constants.flavors[key].learnSignal, 1, key)
    Assert.equal(Constants.flavors[key].learnPatternGlobal, "ERR_LEARN_RECIPE_S", key)
    Assert.equal(Constants.flavors[key].linkInLearnText, false, key)
  end

  -- Only Era and TBC enchant through the CraftFrame.
  Assert.equal(Constants.flavors.era.craftFrame, true)
  Assert.equal(Constants.flavors.tbc.craftFrame, true)
  Assert.equal(Constants.flavors.wrath.craftFrame, false)
  Assert.equal(Constants.flavors.retail.craftFrame, false)

  -- Forever has Services (42), TBC does not; Retail has LookingForGroup, Forever does not.
  Assert.equal(Constants.flavors.forever.channels.services, true)
  Assert.equal(Constants.flavors.tbc.channels.services, false)
  Assert.equal(Constants.flavors.retail.channels.lfg, true)
  Assert.equal(Constants.flavors.forever.channels.lfg, false)

  -- §7.4: only Retail has crafting orders to send an alt's customer to.
  Assert.equal(Constants.templates.retail.altItem, "Hi! My alt {crafter} can craft {item}, send the order there.")
  for _, key in ipairs({ "forever", "era", "tbc", "wrath", "cata", "mop" }) do
    Assert.equal(Constants.templates[key].altItem, "Hi! My alt {crafter} can craft {item}, whisper them.", key)
  end

  -- §6.3 default word lists and §6.4 ambiguous slot words.
  Assert.same(Constants.intentWords, { "lf", "lfc", "lfrc", "wtb", "wtc", "need", "needs", "looking", "any", "any1", "anyone", "who", "recraft" })
  Assert.same(Constants.blockerWords, { "wts", "lfw", "selling" })
  Assert.same(Constants.ambiguousWords, { "legs", "leg", "head", "hands", "feet", "ring", "back", "hand", "band", "hood", "vest" })
  Assert.same(Constants.craftCueWords, { "crafter", "craft", "crafted", "maker", "recraft", "recrafter", "recrafting" })

  -- §6.2 item 2: an alias made only of these words is never created.
  Assert.same(Constants.aliasStopWords, {
    "enchant",
    "of",
    "the",
    "and",
    "recipe",
    "pattern",
    "plans",
    "formula",
    "schematic",
    "minor",
    "lesser",
    "greater",
    "superior",
    "major",
  })
end
