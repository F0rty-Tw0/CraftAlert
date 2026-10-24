-- The spec §6.2 item 6 fixture index: enabled Enchanting, Blacksmithing and Tailoring crafters
-- and its eight recipes, built through the real Index.Build on Retail keys.
--   local Fixture = require("tests.helpers.matcher_fixture")
--   local ns = Fixture.load()                -- fresh modules, Retail stubs
--   local index = Fixture.index(ns)          -- built and ready for Matcher.SetIndex
--   Fixture.expect(ns, "lf mongoose", "item:enchant weapon - mongoose")
-- The recipes carry no item IDs (group = lowercase name), so item links never match by ID; the
-- four Blacksmithing items get the slot/armor words ItemKeywords gives the real items, added to
-- wordIndex after the build ("green iron chest" needs wordIndex.chest -> Green Iron Hauberk).
local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

local Fixture = {}

Fixture.ENCH, Fixture.BS, Fixture.TAILOR, Fixture.LW = 333, 164, 197, 165
Fixture.SENDER = "Customer-Other"

local MODULES = {
  "Core.FlavorCompat",
  "Core.Constants",
  "Core.EventRouter",
  "Core.PlayerName",
  "Model.Tokenizer",
  "Model.Slang",
  "Model.ItemKeywords",
  "Model.ProfessionWords",
  "Model.ClassArmor",
  "Model.StatSlot",
  "Model.MatchCandidates",
  "Model.PhraseMatch",
  "Model.Aliases",
  "Model.TypoPass",
  "Model.WordGroups",
  "Model.Index",
  "Model.Matcher",
  "Persistence.Defaults",
}

-- Item words of the four Blacksmithing recipes (what ItemKeywords gives the real items).
Fixture.itemWords = {
  ["lionheart helm"] = { "helm", "helmet", "head", "plate" },
  ["green iron hauberk"] = { "chest", "robe", "mail" },
  ["green iron leggings"] = { "legs", "leg", "pants", "mail" },
  ["green iron boots"] = { "boots", "boot", "feet", "shoes", "mail" },
}

-- Fresh copies of every module the matcher needs, loaded after Wow.reset (and flavor stubs).
function Fixture.load(flavor)
  Wow.reset()
  if flavor then
    Wow.flavor(flavor)
  end
  local ns = {}
  for _, path in ipairs(MODULES) do
    ns[string.match(path, "%.(%w+)$")] = Fresh.require(path)
  end
  return ns
end

-- A character record with the given profession keys and recipes.
function Fixture.character(professions, recipes)
  local list = {}
  for _, key in ipairs(professions) do
    list[key] = { name = tostring(key), primary = false, read = true }
  end
  return { source = "local", enabled = true, realms = {}, professions = list, recipes = recipes }
end

local function recipe(name, prof)
  return { name = name, prof = prof }
end

function Fixture.db(ns)
  local ENCH, BS = Fixture.ENCH, Fixture.BS
  local db = ns.Defaults.Db()
  db.characters["Ench-Realm"] = Fixture.character({ ENCH }, {
    [11] = recipe("Enchant Weapon - Fiery Weapon", ENCH),
    [12] = recipe("Enchant Weapon - Mongoose", ENCH),
    [13] = recipe("Enchant Chest - Lesser Stamina", ENCH),
    [14] = recipe("Enchant Chest - Greater Stamina", ENCH),
  })
  db.characters["Smith-Realm"] = Fixture.character({ BS }, {
    [21] = recipe("Lionheart Helm", BS),
    [22] = recipe("Green Iron Hauberk", BS),
    [23] = recipe("Green Iron Leggings", BS),
    [24] = recipe("Green Iron Boots", BS),
  })
  db.characters["Tailor-Realm"] = Fixture.character({ Fixture.TAILOR }, {})
  return db
end

-- Index.Build of the fixture db plus the Blacksmithing item words (then WordGroups.Build
-- again, so the step 4.4 group structures include them).
function Fixture.index(ns, db)
  db = db or Fixture.db(ns)
  local index = ns.Index.Build(db, db.settings, {
    ownKey = "Me-Realm",
    professionOrder = function()
      return { Fixture.ENCH, Fixture.BS, Fixture.TAILOR, Fixture.LW }
    end,
  })
  for phrase, words in pairs(Fixture.itemWords) do
    local record = index.phraseSet[phrase]
    if record then
      for _, word in ipairs(words) do
        local list = index.wordIndex[word] or {}
        index.wordIndex[word] = list
        for _, entry in ipairs(record.entries) do
          list[#list + 1] = entry
        end
      end
    end
  end
  ns.WordGroups.Build(index)
  return index
end

-- The fixture plus an enabled leatherworker (spec §6.2 item 6: "Lower Blackrock Spire").
function Fixture.withLeatherworker(ns)
  local db = Fixture.db(ns)
  db.characters["Lw-Realm"] = Fixture.character({ Fixture.LW }, { [31] = recipe("Rugged Armor Kit", Fixture.LW) })
  return Fixture.index(ns, db)
end

-- itemID -> { equipLoc, classID, subclassID } served through the C_Item stub (class 4: armor).
Fixture.items = {
  [501] = { "INVTYPE_WAIST", 4, 4 }, -- plate belt
  [502] = { "INVTYPE_LEGS", 4, 4 }, -- plate legs
  [503] = { "INVTYPE_FEET", 4, 4 }, -- plate boots
  [504] = { "INVTYPE_HEAD", 4, 4 }, -- plate helm
  [505] = { "INVTYPE_WAIST", 4, 4 }, -- plate belt
  [506] = { "INVTYPE_CHEST", 4, 3 }, -- mail chest
  [601] = { "INVTYPE_WAIST", 4, 1 }, -- cloth belt
  [602] = { "INVTYPE_WAIST", 4, 1 },
  [603] = { "INVTYPE_HEAD", 4, 1 }, -- cloth helm
  [604] = { "INVTYPE_LEGS", 4, 1 }, -- cloth legs
  [605] = { "INVTYPE_WAIST", 4, 1 }, -- cloth belt
  [606] = { "INVTYPE_CLOAK", 4, 1 }, -- cloth cloak
  [701] = { "INVTYPE_WAIST", 4, 2 }, -- leather belt
  [702] = { "INVTYPE_HEAD", 4, 2 }, -- leather helm
  [703] = { "INVTYPE_LEGS", 4, 2 }, -- leather legs
  [801] = { "INVTYPE_FINGER", 4, 0 }, -- ring
  [802] = { "INVTYPE_HAND", 4, 2 }, -- leather gloves
  [910] = { "INVTYPE_WEAPON", 2, 7 }, -- one-handed sword
  [950] = { "INVTYPE_TRINKET", 4, 0 }, -- trinket
}

function Fixture.stubItems()
  Wow.stub("C_Item", {
    GetItemInfoInstant = function(itemID)
      local item = Fixture.items[itemID]
      if item then
        return itemID, "type", "subtype", item[1], 0, item[2], item[3]
      end
    end,
  })
end

-- Item recipes with slot/armor words: plate belt and plate legs known by two smiths (one also
-- a jewelcrafter). extra(db) adds more; order is the profession order. Set on the Matcher.
function Fixture.itemIndex(ns, extra, order)
  local BS = Fixture.BS
  Fixture.stubItems()
  local db = ns.Defaults.Db()
  local smith = { [1] = { item = 501, name = "Thick Plate Belt", prof = BS }, [2] = { item = 502, name = "Plate Greaves", prof = BS } }
  db.characters["Smith-Realm"] = Fixture.character({ BS, 755 }, smith)
  db.characters["Alt-Realm"] = Fixture.character({ BS }, { [1] = { item = 501, name = "Thick Plate Belt", prof = BS } })
  if extra then
    extra(db)
  end
  local index = ns.Index.Build(db, db.settings, {
    ownKey = "Me-Realm",
    professionOrder = function()
      return order or { Fixture.TAILOR, BS, Fixture.LW }
    end,
  })
  ns.Matcher.SetIndex(index)
  return index
end

function Fixture.why(result)
  return table.concat({ unpack(result.why, 1, result.whyCount) }, "+")
end

-- Stubs GetPlayerInfoByGUID. classes[guid] is a class token (returned as "Localized", token)
-- or a function whose returns are returned. → counter; counter.n counts calls.
function Fixture.stubClasses(classes)
  local counter = { n = 0 }
  Wow.stub("GetPlayerInfoByGUID", function(guid)
    counter.n = counter.n + 1
    local class = classes[guid]
    if type(class) == "function" then
      return class(guid)
    end
    if class then
      return "Localized", class
    end
  end)
  return counter
end

-- The match outcome: "item:<group>", "profession:<key>" or "stop:<lastStop>", and the result.
---@return string outcome
---@return table|nil result nil on a stop
function Fixture.outcome(ns, text, guid)
  local result = ns.Matcher.Match("trade", text, Fixture.SENDER, guid)
  if result then
    Assert.equal(ns.Matcher.lastStop, "match", text)
    return result.kind .. ":" .. tostring(result.kind == "item" and result.group or result.prof), result
  end
  return "stop:" .. ns.Matcher.lastStop, nil
end

-- Asserts the match outcome: "item:<group>", "profession:<key>" or "stop:<lastStop>".
---@return table|nil result nil on a stop
function Fixture.expect(ns, text, outcome, message, guid)
  local got, result = Fixture.outcome(ns, text, guid)
  Assert.equal(got, outcome, message or text)
  return result
end

return Fixture
