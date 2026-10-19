local Assert = require("tests.helpers.assert")
local Fixture = require("tests.helpers.matcher_fixture")

local BS = Fixture.BS

-- Every record in nameIndex by phrase.
local function records(index)
  local byPhrase = {}
  for _, list in pairs(index.nameIndex) do
    for _, record in ipairs(list) do
      byPhrase[record.phrase] = record
    end
  end
  return byPhrase
end

-- Records and itemIndex lists holding the same entries in the same order are one table (§4.4
-- index memory); lists with other entries stay apart.
local function testSharedEntryLists()
  local ns = Fixture.load()
  local index = Fixture.itemIndex(ns)
  local byPhrase = records(index)
  local belt = byPhrase["thick plate belt"].entries
  Assert.equal(#belt, 2)
  Assert.truthy(rawequal(byPhrase.thick.entries, belt))
  Assert.truthy(rawequal(byPhrase["thick plate"].entries, belt))
  Assert.truthy(rawequal(index.itemIndex[501], belt))
  Assert.truthy(rawequal(index.itemIndex[502], byPhrase["plate greaves"].entries))
  Assert.falsy(rawequal(index.itemIndex[502], belt))
  -- An alias of two recipes starts with the same entry as one of them but holds more.
  index = Fixture.itemIndex(ns, function(db)
    db.characters["Alt-Realm"].recipes[3] = { item = 503, name = "Thick Plate Treads", prof = BS }
  end)
  byPhrase = records(index)
  belt = byPhrase["thick plate belt"].entries
  local thickPlate = byPhrase["thick plate"].entries
  Assert.equal(#thickPlate, 3)
  Assert.truthy(rawequal(thickPlate[1], belt[1]) or rawequal(thickPlate[1], byPhrase["thick plate treads"].entries[1]))
  Assert.falsy(rawequal(thickPlate, belt))
  Assert.falsy(rawequal(thickPlate, byPhrase["thick plate treads"].entries))
  -- Same length and first entry, another second entry: item 501 is made by the belt and a ring,
  -- the "thick plate" alias names the belt and the treads.
  index = Fixture.itemIndex(ns, function(db)
    db.characters["Alt-Realm"] = nil
    local recipes = db.characters["Smith-Realm"].recipes
    recipes[3] = { item = 501, name = "Iron Ring", prof = BS }
    recipes[4] = { item = 503, name = "Thick Plate Treads", prof = BS }
  end)
  thickPlate = records(index)["thick plate"].entries
  local made = index.itemIndex[501]
  Assert.equal(#made, 2)
  Assert.equal(#thickPlate, 2)
  Assert.truthy(rawequal(made[1], thickPlate[1]), "the case needs a shared first entry")
  Assert.same({ made[1].group, made[2].group }, { 501, 501 })
  Assert.same({ thickPlate[1].group, thickPlate[2].group }, { 501, 503 })
end

return function()
  testSharedEntryLists()
  require("tests.helpers.wow").reset()
end
