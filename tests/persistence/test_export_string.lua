local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

-- Spec §10.1, §13 "ExportString": round trip (with `muted`), re-import keeps A-side `enabled` and
-- `primary`, tampered / truncated / oversized / wrong-flavor strings rejected with storage unchanged.
local NOW = 1792000000
local BS, ENCH = 164, 333
-- A name with every reserved byte, a percent sign and UTF-8.
local ODD_NAME = "Enchant: Bracer; Sim, Health. ~100% Ünïcode"

local function load()
  Wow.reset()
  Wow.flavor("retail")
  Wow.clock.time = NOW
  Fresh.require("Core.FlavorCompat")
  Fresh.require("Core.Slicer")
  local BindLookup = Fresh.require("Professions.BindLookup")
  local Index = Fresh.require("Model.Index")
  Fresh.require("Persistence.Base36")
  local Fields = Fresh.require("Persistence.ExportFields")
  local ExportString = Fresh.require("Persistence.ExportString")
  local calls = { queued = {}, rebuilds = {} }
  BindLookup.Queue = function(item)
    calls.queued[#calls.queued + 1] = item
  end
  Index.RequestRebuild = function(reason)
    calls.rebuilds[#calls.rebuilds + 1] = reason
  end
  return ExportString, calls, Fields
end

local function sourceDb()
  return {
    characters = {
      ["Smith-Area52"] = {
        source = "local",
        enabled = true,
        class = "WARRIOR",
        realms = { "Area52", "Kel'Thuzad" },
        professions = {
          [BS] = { name = "Blacksmithing", primary = true, read = true },
          [ENCH] = { name = "Enchanting", primary = false, read = true },
        },
        recipes = {
          [9001] = { name = "Sim Plate Belt", prof = BS, item = 190001, ranks = { 190011, 190012 }, line = 2872, bind = 2 },
          [9002] = { name = ODD_NAME, prof = ENCH, muted = true },
          [123456] = { name = "Sim Plate Helm", prof = BS, item = 190004, reachRank = 2, reachCost = 1, reachConc = 0 },
          [9003] = { name = "Bad |cffff0000name", prof = BS }, -- never written: "|" is a UI escape
          [9004] = { name = "Orphan", prof = 999 }, -- profession not stored: left out
        },
      },
      ["First Last-OwnRealm"] = {
        source = "local",
        enabled = false,
        realms = {},
        professions = { [BS] = { name = "Blacksmithing", primary = false, read = false } },
        recipes = {},
      },
      ["Imported-Elsewhere"] = { source = "import", enabled = true, realms = {}, professions = {}, recipes = {} },
    },
  }
end

local function copy(value)
  if type(value) ~= "table" then
    return value
  end
  local result = {}
  for key, inner in pairs(value) do
    result[key] = copy(inner)
  end
  return result
end

-- The contract's checksum, computed here independently: Adler-32, 7 base-36 digits.
local function seal(head)
  local a, b = 1, 0
  for i = 1, #head do
    a = (a + head:byte(i)) % 65521
    b = (b + a) % 65521
  end
  local n, digits = b * 65536 + a, ""
  repeat
    local d = n % 36
    digits = ("0123456789abcdefghijklmnopqrstuvwxyz"):sub(d + 1, d + 1) .. digits
    n = math.floor(n / 36)
  until n == 0
  return head .. ":" .. string.rep("0", 7 - #digits) .. digits
end

local function testRoundTrip()
  local ExportString = load()
  local text = ExportString.Encode(sourceDb(), "retail")
  Assert.equal(text:sub(1, 11), "CA1:retail:")
  Assert.equal(seal(text:match("^(.*):")), text, "checksum as the contract pins it")
  Assert.falsy(text:find("Imported", 1, true), "imported characters are not passed on")
  Assert.falsy(text:find("|", 1, true))
  local data = assert(ExportString.Decode(text, "retail"))
  local target = { characters = {} }
  Assert.same(ExportString.Apply(target, data), { characters = 2, recipes = 3, skipped = 0 })
  Assert.same(target.characters["Smith-Area52"], {
    source = "import",
    importedAt = NOW,
    enabled = true,
    class = "WARRIOR",
    realms = { "Area52", "Kel'Thuzad" },
    professions = { [BS] = { name = "Blacksmithing", primary = false, read = true }, [ENCH] = { name = "Enchanting", primary = false, read = true } },
    recipes = {
      [9001] = { name = "Sim Plate Belt", prof = BS, item = 190001, ranks = { 190011, 190012 }, line = 2872 },
      [9002] = { name = ODD_NAME, prof = ENCH, muted = true },
      [123456] = { name = "Sim Plate Helm", prof = BS, item = 190004 },
    },
  })
  Assert.same(target.characters["First Last-OwnRealm"].professions, { [BS] = { name = "Blacksmithing", primary = false, read = true } })
  Assert.equal(target.characters["First Last-OwnRealm"].enabled, true, "B's enabled flag is not exported")
  -- A pasted newline or space around the string is ignored.
  Assert.truthy(ExportString.Decode("  " .. text .. "\n", "retail"))
end

local function testClassicNameKeys()
  local ExportString = load()
  local db = {
    characters = {
      ["Smith-Realm"] = {
        source = "local",
        realms = {},
        professions = { blacksmithing = { name = "Blacksmithing" } },
        recipes = {
          ["sim plate belt"] = { name = "Sim Plate Belt", prof = "blacksmithing", item = 190001 },
          ["~odd. key"] = { name = "Odd", prof = "blacksmithing" },
        },
      },
    },
  }
  local data = assert(ExportString.Decode(ExportString.Encode(db, "tbc"), "tbc"))
  Assert.same(data.characters[1].recipes, {
    ["sim plate belt"] = { name = "Sim Plate Belt", prof = "blacksmithing", item = 190001 },
    ["~odd. key"] = { name = "Odd", prof = "blacksmithing" },
  })
end

-- Records go out numbers ascending, then string keys ascending, sorted without a Lua comparator
-- (one took 20 ms in one slice for 5000 keys).
local function testKeyOrder()
  local sort, comparators = table.sort, 0
  rawset(table, "sort", function(list, comparator)
    comparators = comparators + (comparator and 1 or 0)
    return sort(list, comparator)
  end)
  local ExportString = load()
  local recipes = {}
  for _, key in ipairs({ 100, "b", 5, "a", 30 }) do
    recipes[key] = { name = "R" .. key, prof = BS }
  end
  local db = { characters = { ["Smith-Realm"] = { source = "local", realms = {}, professions = { [BS] = { name = "BS" } }, recipes = recipes } } }
  local text = ExportString.Encode(db, "retail")
  rawset(table, "sort", sort)
  Assert.equal(comparators, 0)
  Assert.truthy(text:find("r,5,4k,R5,,,,;r,p,4k,R30,,,,;r,1y,4k,R100,,,,;r,~a,4k,Ra,,,,;r,~b,4k,Rb,,,,", 1, true), text)
end

-- A re-import replaces recipes and realms, keeps A's enabled and main crafter choices, refreshes
-- importedAt, keeps a known bind for an unchanged item, and queues the rest for the bind lookup.
local function testReimportKeepsChoices()
  local ExportString, calls = load()
  local target = {
    characters = {
      ["Smith-Area52"] = {
        source = "import",
        importedAt = 1,
        enabled = false,
        realms = { "Old" },
        professions = { [BS] = { name = "Blacksmithing", primary = true, read = true } },
        recipes = { [9001] = { name = "Sim Plate Belt", prof = BS, item = 190001, bind = 2 }, [1] = { name = "Gone", prof = BS } },
      },
    },
  }
  local counts = ExportString.Apply(target, assert(ExportString.Decode(ExportString.Encode(sourceDb(), "retail"), "retail")))
  Assert.same(counts, { characters = 2, recipes = 3, skipped = 0 })
  local smith = target.characters["Smith-Area52"]
  Assert.equal(smith.enabled, false)
  Assert.equal(smith.importedAt, NOW)
  Assert.equal(smith.professions[BS].primary, true)
  Assert.equal(smith.professions[ENCH].primary, false)
  Assert.same(smith.realms, { "Area52", "Kel'Thuzad" })
  Assert.equal(smith.recipes[1], nil, "recipes replaced")
  Assert.equal(smith.recipes[9001].bind, 2, "same item keeps its bind")
  Assert.same(calls.queued, { 190004 })
end

local function testLocalCharacterSkipped()
  local ExportString = load()
  local mine = { source = "local", enabled = true, realms = {}, professions = {}, recipes = {} }
  local target = { characters = { ["Smith-Area52"] = mine } }
  local before = copy(target.characters["Smith-Area52"])
  local counts = ExportString.Apply(target, assert(ExportString.Decode(ExportString.Encode(sourceDb(), "retail"), "retail")))
  Assert.same(counts, { characters = 1, recipes = 0, skipped = 1 })
  Assert.same(target.characters["Smith-Area52"], before)
end

-- Every refused string leaves storage alone and gives one message.
local function testRejected()
  local ExportString, calls, Fields = load()
  local good = ExportString.Encode(sourceDb(), "retail")
  local head = good:match("^(.*):")
  local cases = {
    { good:sub(1, #good - 20), "damaged" }, -- truncated
    { head:gsub("Sim Plate Belt", "Sim Plate Bolt") .. good:sub(#head + 1), "checksum" }, -- tampered
    { "CA1:retail:" .. string.rep("x", Fields.MAX.length), "too long" },
    { (good:gsub("^CA1:retail:", "CA1:tbc:")), "made on tbc" },
    { seal("CA2:retail:"), "another Craft Alert version" },
    { "hello", "Not a Craft Alert" },
    { seal("CA1:retail:c,Smith-Realm,,;r,1,4k,Name%7Cr,,,,"), "recipe 2" }, -- "|" once unescaped
    { seal("CA1:retail:c,Smith-Realm,,;p,4k,BS;r,1,4k,A,,1.2.3.4.5.6,,"), "recipe 3" }, -- six ranks
    { seal("CA1:retail:c,Smith-Realm,,;p,4k,BS;r,5,4k,A,,,,;r,0,4k,B,,,,"), "recipe 4" }, -- no step
    { seal("CA1:retail:c,Smith-Realm,,;r,1,4k,A,,,,"), "recipe 2" }, -- profession not listed
    { seal("CA1:retail:c,Smith,,"), "character 1" }, -- no realm
    { seal("CA1:retail:c,Smith-Realm,,;c,Smith-Realm,,"), "character count 2" },
    { seal("CA1:retail:c,Smith-Realm,,;x,1"), "record 2" },
    { seal("CA1:retail:c,Smith-Realm,,;p,4k,B,S"), "profession 2" }, -- field count
  }
  local db = { characters = { ["Mine-Realm"] = { source = "local", enabled = true, realms = {}, professions = {}, recipes = {} } } }
  local before = copy(db)
  for i, case in ipairs(cases) do
    local data, err = ExportString.Decode(case[1], "retail")
    Assert.equal(data, nil, "case " .. i)
    Assert.truthy(err:find(case[2], 1, true), "case " .. i .. ": " .. err)
  end
  -- The sliced import writes nothing for a refused string and rebuilds nothing.
  local Slicer = require("CraftAlert.Core.Slicer")
  local result
  ExportString.StartImport(db, cases[2][1], function(counts, err)
    result = { counts = counts, err = err }
  end)
  Slicer.Drain()
  Assert.equal(result.counts, nil)
  Assert.truthy(result.err:find("checksum", 1, true))
  Assert.same(db, before, "storage unchanged")
  Assert.same(calls.rebuilds, {})
  ExportString.StartImport(db, good, function(counts)
    result = { counts = counts }
  end)
  Slicer.Drain()
  Assert.same(result.counts, { characters = 2, recipes = 3, skipped = 0 })
  Assert.same(calls.rebuilds, { "import" })
end

-- Damaged pastes are refused in one cheap pass: the length before the trim (spaces count past
-- MAX.length + 64), and a trim that stays linear on a long run of spaces (once 8.6 s for 16,000).
local function testDamagedIsCheap()
  local ExportString, _, Fields = load()
  local good = ExportString.Encode(sourceDb(), "retail")
  local _, err = ExportString.Decode(string.rep(" ", Fields.MAX.length) .. good, "retail")
  Assert.truthy(err and err:find("too long", 1, true), tostring(err))
  local started = os.clock()
  _, err = ExportString.Decode("CA1:retail:" .. string.rep(" ", 16000) .. "x", "retail")
  local seconds = os.clock() - started
  Assert.truthy(err:find("incomplete", 1, true), err)
  Assert.truthy(seconds < 0.5, "trim took " .. seconds .. " s")
end

-- The user's Retail account is 6 characters and 2,983 recipes: 3,000 synthetic recipes export
-- under MAX.length, and the sliced export and import take many short steps.
local function testLargeExportIsSliced()
  local ExportString, _, Fields = load()
  local Slicer = require("CraftAlert.Core.Slicer")
  Wow.stub("debugprofilestop", function()
    Wow.clock.profile = Wow.clock.profile + 0.05
    return Wow.clock.profile
  end)
  local db = { characters = {} }
  for c = 1, 6 do
    local recipes = {}
    for r = 1, 500 do
      local id = 400000 + c * 1000 + r
      recipes[id] =
        { name = "Sim Recipe Name Of Usual Length " .. id, prof = BS, item = 200000 + id, ranks = { 300000 + id, 300001 + id }, line = 2872 }
    end
    db.characters["Crafter" .. c .. "-Realm"] =
      { source = "local", realms = { "Realm" }, professions = { [BS] = { name = "Blacksmithing" } }, recipes = recipes }
  end
  local text
  Slicer.ResetStats()
  ExportString.StartExport(db, function(result)
    text = result
  end)
  Slicer.Drain()
  Assert.truthy(Slicer.stats.steps > 10, "export steps " .. Slicer.stats.steps)
  Assert.truthy(#text < Fields.MAX.length, "length " .. #text)
  local counts
  Slicer.ResetStats()
  ExportString.StartImport({ characters = {} }, text, function(result)
    counts = result
  end)
  Slicer.Drain()
  Assert.truthy(Slicer.stats.steps > 10, "import steps " .. Slicer.stats.steps)
  Assert.same(counts, { characters = 6, recipes = 3000, skipped = 0 })
end

return function()
  testRoundTrip()
  testClassicNameKeys()
  testKeyOrder()
  testReimportKeepsChoices()
  testLocalCharacterSkipped()
  testRejected()
  testDamagedIsCheap()
  testLargeExportIsSliced()
  Wow.reset()
end
