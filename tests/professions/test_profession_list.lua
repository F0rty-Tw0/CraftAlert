local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")
local ProfessionsRetail = require("tests.helpers.professions_retail")

local BS, ENCH, MINING, COOKING, FIRST_AID = 164, 333, 186, 185, 129
local CHAR = "Crafter-OwnRealm"

local function load(flavor)
  Wow.reset()
  if flavor then
    Wow.flavor(flavor)
  end
  Fresh.require("Core.FlavorCompat")
  Fresh.require("Model.ProfessionWords")
  return Fresh.require("Professions.ProfessionList"), Fresh.require("Persistence.Defaults")
end

local function slot(name, skillLine)
  return { name = name, skillLine = skillLine }
end

return function()
  for _, flavor in ipairs({ "retail", "forever" }) do
    local ProfessionList, Defaults = load(flavor)
    local db = Defaults.Db()

    -- Blacksmithing + Mining fill the profession slots; Cooking and First Aid (Forever) are secondary.
    ProfessionsRetail.install({
      slots = { slot("Blacksmithing", BS), slot("Mining", MINING), slot("First Aid", FIRST_AID), false, slot("Cooking", COOKING) },
    })
    ProfessionList.Refresh(db, CHAR)

    local character = db.characters[CHAR]
    Assert.same(character.professions, { [BS] = { name = "Blacksmithing", primary = false, read = false } }, flavor)
    Assert.equal(character.source, "local")
    Assert.equal(character.enabled, true)
    Assert.same(ProfessionList.Order(), { BS })
    Assert.truthy(ProfessionList.IsStored(db, CHAR, BS))
    Assert.falsy(ProfessionList.IsStored(db, CHAR, COOKING))
    Assert.falsy(ProfessionList.IsStored(db, CHAR, MINING))
    Assert.falsy(ProfessionList.IsStored(db, "Nobody-Realm", BS))
    Assert.same(ProfessionList.UnreadNames(db, CHAR), { "Blacksmithing" })
  end

  local ProfessionList, Defaults = load()
  local db = Defaults.Db()
  local state = ProfessionsRetail.install({ slots = { slot("Enchanting", ENCH), slot("Blacksmithing", BS) } })

  -- Slot order is the tie-break order. `primary` is the player's choice, never the slot.
  ProfessionList.Refresh(db, CHAR)
  Assert.same(ProfessionList.Order(), { ENCH, BS })
  Assert.equal(db.characters[CHAR].professions[BS].primary, false)
  Assert.equal(db.characters[CHAR].professions[ENCH].primary, false)
  Assert.same(ProfessionList.UnreadNames(db, CHAR), { "Blacksmithing", "Enchanting" })

  -- A refresh keeps the read flag, the recipes and what the player muted.
  local professions = db.characters[CHAR].professions
  professions[BS].read = true
  professions[BS].primary = true
  db.characters[CHAR].recipes[1] = { name = "belt", prof = BS, muted = true }
  db.characters[CHAR].recipes[2] = { name = "enchant bracer", prof = ENCH }
  ProfessionList.Refresh(db, CHAR)
  Assert.equal(db.characters[CHAR].professions[BS].read, true)
  Assert.equal(db.characters[CHAR].professions[BS].primary, true, "a chosen primary survives a refresh")
  Assert.equal(db.characters[CHAR].professions[ENCH].primary, false)
  Assert.equal(db.characters[CHAR].recipes[1].muted, true)
  Assert.same(ProfessionList.UnreadNames(db, CHAR), { "Enchanting" })

  -- A dropped profession leaves with its recipes; other characters are untouched.
  db.characters["Alt-OwnRealm"] = {
    source = "local",
    enabled = true,
    realms = {},
    professions = { [BS] = { name = "Blacksmithing", primary = true, read = true } },
    recipes = { [1] = { name = "belt", prof = BS } },
  }
  state.slots = { slot("Enchanting", ENCH) }
  ProfessionList.Refresh(db, CHAR)
  Assert.falsy(ProfessionList.IsStored(db, CHAR, BS))
  Assert.equal(db.characters[CHAR].recipes[1], nil)
  Assert.truthy(db.characters[CHAR].recipes[2])
  Assert.truthy(db.characters["Alt-OwnRealm"].recipes[1])
  Assert.truthy(ProfessionList.IsStored(db, "Alt-OwnRealm", BS))
  Assert.same(ProfessionList.Order(), { ENCH })

  -- An alt's own refresh keeps its choice: primary = false stays false.
  db.characters["Alt-OwnRealm"].professions[BS].primary = false
  state.slots = { slot("Blacksmithing", BS) }
  ProfessionList.Refresh(db, "Alt-OwnRealm")
  Assert.equal(db.characters["Alt-OwnRealm"].professions[BS].primary, false)

  -- No profession API (or no crafting profession on a new character): nothing is written.
  local empty = Defaults.Db()
  Wow.stub("GetProfessions", nil)
  ProfessionList.Refresh(empty, CHAR)
  Assert.equal(empty.characters[CHAR], nil)
  ProfessionsRetail.install({ slots = { slot("Mining", MINING) } })
  ProfessionList.Refresh(empty, CHAR)
  Assert.equal(empty.characters[CHAR], nil)

  -- ...and a stored character keeps everything when the API is missing.
  Wow.stub("GetProfessions", nil)
  ProfessionList.Refresh(db, CHAR)
  Assert.truthy(db.characters[CHAR].recipes[2])

  -- Unknown data never deletes: no slot at all, or a slot whose skill line has not loaded.
  state = ProfessionsRetail.install({ slots = { slot("Enchanting", ENCH) } })
  ProfessionList.Refresh(db, CHAR)
  state.slots = {}
  ProfessionList.Refresh(db, CHAR)
  Assert.truthy(ProfessionList.IsStored(db, CHAR, ENCH))
  Assert.truthy(db.characters[CHAR].recipes[2])
  state.slots = { slot("Enchanting", nil) }
  ProfessionList.Refresh(db, CHAR)
  Assert.truthy(ProfessionList.IsStored(db, CHAR, ENCH))
  Assert.truthy(db.characters[CHAR].recipes[2])
  Assert.same(ProfessionList.Order(), { ENCH })

  -- At login the secondary slots may load before the profession slots: with both profession
  -- slots empty, a character with professions stored keeps them (a partial read).
  state.slots = { false, false, slot("Cooking", COOKING) }
  Assert.equal(ProfessionList.Refresh(db, CHAR), false)
  Assert.truthy(ProfessionList.IsStored(db, CHAR, ENCH))
  Assert.truthy(db.characters[CHAR].recipes[2])
  Assert.same(ProfessionList.Order(), { ENCH })

  -- A list of non-crafting professions only is real data: the crafting professions drop.
  state.slots = { slot("Mining", MINING) }
  ProfessionList.Refresh(db, CHAR)
  Assert.same(db.characters[CHAR].professions, {})
  Assert.same(db.characters[CHAR].recipes, {})
  Assert.same(ProfessionList.Order(), {})

  -- Unknown data at login (the first Refresh of a session) seeds the order from the stored
  -- professions, sorted; once the data is known (SKILL_LINES_CHANGED), Refresh says whether the
  -- order it set differs, so the index can be rebuilt.
  ProfessionList, Defaults = load()
  db = Defaults.Db()
  db.characters[CHAR] = {
    source = "local",
    enabled = true,
    realms = {},
    professions = {
      [ENCH] = { name = "Enchanting", primary = false, read = true },
      [BS] = { name = "Blacksmithing", primary = false, read = true },
    },
    recipes = { [1] = { name = "belt", prof = BS }, [2] = { name = "enchant bracer", prof = ENCH } },
  }
  state = ProfessionsRetail.install({ slots = { false, false, slot("Cooking", COOKING) } })
  Assert.equal(ProfessionList.Refresh(db, CHAR), false)
  Assert.same(ProfessionList.Order(), { BS, ENCH })
  Assert.same(db.characters[CHAR].recipes[1], { name = "belt", prof = BS })
  state.slots = { slot("Enchanting", ENCH), slot("Blacksmithing", BS), slot("Cooking", COOKING) }
  Assert.equal(ProfessionList.Refresh(db, CHAR), true)
  Assert.same(ProfessionList.Order(), { ENCH, BS })
  Assert.equal(ProfessionList.Refresh(db, CHAR), false, "the same list again changes nothing")
  -- A later partial read keeps the order the full read set.
  state.slots = { false, false, slot("Cooking", COOKING) }
  Assert.equal(ProfessionList.Refresh(db, CHAR), false)
  Assert.same(ProfessionList.Order(), { ENCH, BS })
  ProfessionList = load() -- Wow.reset drops the profession API stubs
  ProfessionList.Refresh(db, CHAR)
  Assert.same(ProfessionList.Order(), { BS, ENCH }, "a missing API seeds the order too")
end
