local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- Static facts. The per-flavor rows mirror docs/knowledge/flavor-choices.md; rows marked
-- "inferred" there (Era, Wrath, Cata, MoP) copy TBC Anniversary until a client is probed.
local Constants = {}

Constants.version = "0.1.0"

-- Sound kits valid on every probed flavor; 888 is invalid on Retail, so it is not shipped.
local SOUND_KITS = { 8959, 3081, 5274, 12867, 8960 }

local LEARN_BY_EVENT = 2 -- NEW_RECIPE_LEARNED (Retail, Forever: recipe ID)
local LEARN_BY_SYSTEM_MESSAGE = 1 -- CHAT_MSG_SYSTEM matched against ERR_LEARN_RECIPE_S (Classic)

local function channels(trade, services, general, lfg, guild, communities)
  return { trade = trade, services = services, general = general, lfg = lfg, guild = guild, communities = communities }
end

local function classicFlavor(craftFrame)
  return {
    learnSignal = LEARN_BY_SYSTEM_MESSAGE,
    learnPatternGlobal = "ERR_LEARN_RECIPE_S",
    linkInLearnText = false,
    channels = channels(true, false, true, false, true, false),
    soundKits = SOUND_KITS,
    craftFrame = craftFrame,
  }
end

-- Channels (zone channel IDs General 1, Trade 2, Services 42) as observed in Phase 0.
-- Retail Services was not observed but the channel exists there; Communities is Retail and Forever only.
Constants.flavors = {
  retail = {
    learnSignal = LEARN_BY_EVENT,
    learnPatternGlobal = nil,
    linkInLearnText = false,
    channels = channels(true, true, true, true, true, true),
    soundKits = SOUND_KITS,
    craftFrame = false,
  },
  forever = {
    learnSignal = LEARN_BY_EVENT,
    learnPatternGlobal = nil,
    linkInLearnText = false,
    channels = channels(true, true, true, false, true, true),
    soundKits = SOUND_KITS,
    craftFrame = false,
  },
  era = classicFlavor(true),
  tbc = classicFlavor(true),
  wrath = classicFlavor(false),
  cata = classicFlavor(false),
  mop = classicFlavor(false),
}

-- §6.3: defaults for the editable intent and blocker lists.
Constants.intentWords = { "lf", "lfc", "wtb", "need", "needs", "looking", "any", "any1", "anyone", "who", "recraft" }
Constants.blockerWords = { "wts", "lfw", "selling" }

-- §6.2 item 2: filler and tier words. An alias made only of these (or of slang, stat,
-- profession, intent and blocker words) is never created, so "enchant weapon" is no alias.
Constants.aliasStopWords = {
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
}

-- §6.4: slot words that count only next to another slot/type word or a phrase: body parts,
-- and "ring" ("ring me when ready", "ring of blood"; user ruling 2026-10-20).
Constants.ambiguousWords = { "legs", "head", "hands", "feet", "ring" }

-- Class-armor spec §5: words that mark a line as asking for crafting, so a body-part slot word
-- may take the sender's armor type. Every profession word counts too. Fixed, not user-editable.
Constants.craftCueWords = { "crafter", "craft", "crafted", "maker" }

-- §7.4: greeting templates. Only Retail has crafting orders to point an alt's customer to.
local function templates(altItemTail)
  return {
    item = "Hi! I can craft {item}.",
    altItem = "Hi! My alt {crafter} can craft {item}, " .. altItemTail,
    profession = "Hi! I have {profession}, what do you need?",
    altProfession = "Hi! My alt {crafter} has {profession}, what do you need?",
  }
end

Constants.templates = {
  retail = templates("send the order there."),
  forever = templates("whisper them."),
  era = templates("whisper them."),
  tbc = templates("whisper them."),
  wrath = templates("whisper them."),
  cata = templates("whisper them."),
  mop = templates("whisper them."),
}

ns.Constants = Constants
return Constants
