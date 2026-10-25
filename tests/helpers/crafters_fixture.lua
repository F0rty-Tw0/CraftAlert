-- The Crafters page's characters and its recipe rows, shared by the recipe list tests.
--   CraftersFixture.BS, CraftersFixture.ENCH       Blacksmithing and Enchanting skill-line IDs
--   SettingsFixture.load({ db = CraftersFixture.crafters })
--                                                  Me-Realm (BS and ENCH recipes), Alt-Realm (the BS
--                                                  main crafter) and the imported Far-Away
--   CraftersFixture.rowOf(key), .iconOf(key)       the visible recipe row showing recipe `key`, its icon
local Wow = require("tests.helpers.wow")
local SettingsFixture = require("tests.helpers.settings_fixture")

local CraftersFixture = {}

local BS, ENCH = 164, 333
CraftersFixture.BS, CraftersFixture.ENCH = BS, ENCH

function CraftersFixture.crafters(accountDb)
  accountDb.characters["Me-Realm"] = {
    source = "local",
    enabled = true,
    realms = { "Realm" },
    professions = { [BS] = { name = "Blacksmithing", primary = false, read = true }, [ENCH] = { name = "Enchanting", primary = false, read = true } },
    recipes = {
      [9001] = { item = 501, name = "Thick Plate Belt", prof = BS },
      [9002] = { item = 502, name = "Plate Greaves", prof = BS },
      [9003] = { name = "Enchant Bracer - Health", prof = ENCH },
    },
  }
  accountDb.characters["Alt-Realm"] = {
    source = "local",
    enabled = true,
    realms = { "Realm" },
    professions = { [BS] = { name = "Blacksmithing", primary = true, read = true } },
    recipes = { [9001] = { item = 501, name = "Thick Plate Belt", prof = BS } },
  }
  accountDb.characters["Far-Away"] = { source = "import", importedAt = 1, enabled = true, realms = {}, professions = {}, recipes = {} }
end

function CraftersFixture.rowOf(key)
  for _, frame in ipairs(Wow.frames) do
    if frame.icon and frame.item and frame.item.key == key and SettingsFixture.visible(frame) then
      return frame
    end
  end
  error("no visible recipe row " .. tostring(key))
end

function CraftersFixture.iconOf(key)
  return CraftersFixture.rowOf(key).icon
end

return CraftersFixture
