local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local UiFixture = require("tests.helpers.ui_fixture")
local MainCrafter = require("CraftAlert.Model.MainCrafter")

-- Main-crafter spec §3: the menu a lead card's Crafters zone opens. One radio per enabled character
-- that knows the lead's profession, then None; choosing one writes the flag and re-picks that lead.
local BS = 164
local ENCH = 333

local function blacksmith(enabled)
  return { enabled = enabled, professions = { [BS] = { name = "Blacksmithing" } } }
end

-- Me, Alt, Zed and Off (disabled) know BS; Ench knows only ENCH. → ns, db, the Repick calls { id, result }.
local function load()
  local ns, db = UiFixture.load({
    leads = 1,
    db = function(accountDb)
      accountDb.characters["Me-Realm"] = blacksmith()
      accountDb.characters["Zed-Realm"] = blacksmith()
      accountDb.characters["Alt-Realm"] = blacksmith()
      accountDb.characters["Off-Realm"] = blacksmith(false)
      accountDb.characters["Ench-Realm"] = { professions = { [ENCH] = { name = "Enchanting" } } }
      accountDb.leads[1].crafters = { { key = "Me-Realm", prof = BS }, { key = "Alt-Realm", prof = BS }, { key = "Zed-Realm", prof = BS } }
    end,
  })
  local repicks = {}
  local repick = ns.Leads.Repick
  ns.Leads.Repick = function(id)
    local result = repick(id)
    repicks[#repicks + 1] = { id, result }
    return result
  end
  return ns, db, repicks
end

local function radios()
  local found = {}
  for _, entry in ipairs(Wow.menu.entries) do
    if entry.kind == "radio" then
      found[#found + 1] = entry
    end
  end
  return found
end

local function radioTexts()
  local texts = {}
  for _, entry in ipairs(radios()) do
    texts[#texts + 1] = entry.text
  end
  return texts
end

-- The texts of the radios the menu shows selected.
local function selected()
  local texts = {}
  for _, entry in ipairs(radios()) do
    if entry.isSelected(entry.data) then
      texts[#texts + 1] = entry.text
    end
  end
  return table.concat(texts, ",")
end

local function choose(text)
  for _, entry in ipairs(radios()) do
    if entry.text == text then
      entry.setSelected(entry.data)
      return
    end
  end
  error("no radio " .. text)
end

local function testEntries()
  local ns, db = load()
  local owner = {}
  ns.MainCrafterMenu.Open(owner, ns.Leads.List()[1])
  Assert.equal(Wow.menu.owner, owner)
  Assert.same({ Wow.menu.entries[1].kind, Wow.menu.entries[1].text }, { "title", "Main crafter for Blacksmithing" })
  Assert.same(radioTexts(), { "Alt", "Me", "Zed", "None" })
  Assert.equal(selected(), "None")
  -- Old data with two flags: the lowest key shows selected.
  db.characters["Zed-Realm"].professions[BS].primary = true
  db.characters["Alt-Realm"].professions[BS].primary = true
  Assert.equal(selected(), "Alt")
end

local function testClassColour()
  local ns, db = load()
  db.characters["Zed-Realm"].class = "MAGE"
  Wow.stub("RAID_CLASS_COLORS", { MAGE = { r = 0.25, g = 0.78, b = 0.92 } })
  ns.MainCrafterMenu.Open({}, ns.Leads.List()[1])
  Assert.same(radioTexts(), { "Alt", "Me", "|cff3fc6eaZed|r", "None" })
end

local function testChoose()
  local ns, db, repicks = load()
  local lead = ns.Leads.List()[1]
  ns.MainCrafterMenu.Open({}, lead)
  choose("Alt")
  Assert.equal(MainCrafter.Of(db, BS), "Alt-Realm")
  Assert.same(repicks, { { lead.id, true } })
  Assert.equal(lead.crafter, "Alt-Realm")
  -- Already the main: nothing written (Set would turn Me's nil into false), nothing re-picked.
  db.characters["Me-Realm"].professions[BS].primary = nil
  choose("Alt")
  Assert.same({ #repicks, db.characters["Me-Realm"].professions[BS].primary }, { 1, nil })
  -- None with two flags from old data clears both.
  db.characters["Zed-Realm"].professions[BS].primary = true
  choose("None")
  Assert.same({ MainCrafter.Of(db, BS), db.characters["Zed-Realm"].professions[BS].primary }, { nil, false })
  Assert.equal(#repicks, 2)
  Assert.equal(selected(), "None")
  -- None again: already selected.
  choose("None")
  Assert.equal(#repicks, 2)
  -- Old data with two flags shows the lowest key selected; choosing it clears the other flag.
  db.characters["Alt-Realm"].professions[BS].primary = true
  db.characters["Zed-Realm"].professions[BS].primary = true
  choose("Alt")
  Assert.same(
    { db.characters["Alt-Realm"].professions[BS].primary, db.characters["Zed-Realm"].professions[BS].primary, #repicks },
    { true, false, 3 }
  )
  choose("Alt")
  Assert.equal(#repicks, 3, "the only flag now: nothing to do")
end

-- Review Focus 2: the lead went (dismissed) while the menu was open; choosing neither errors nor revives it.
local function testLeadGone()
  local ns, db, repicks = load()
  local lead = ns.Leads.List()[1]
  ns.MainCrafterMenu.Open({}, lead)
  ns.Leads.Dismiss(lead.id)
  choose("Zed")
  Assert.equal(MainCrafter.Of(db, BS), "Zed-Realm")
  Assert.same(repicks, { { lead.id, false } })
  Assert.same(ns.Leads.List(), {})
end

local function testCanOpen()
  local ns = load()
  Assert.equal(ns.MainCrafterMenu.CanOpen({ prof = BS }), true)
  Assert.equal(ns.MainCrafterMenu.CanOpen({ prof = ENCH }), true)
  Assert.equal(ns.MainCrafterMenu.CanOpen({ prof = nil }), false)
  Assert.equal(ns.MainCrafterMenu.CanOpen({ prof = 999 }), false)
  -- Only a disabled character knows it.
  local db = _G["CraftAlertDB"]
  db.characters["Ench-Realm"].enabled = false
  Assert.equal(ns.MainCrafterMenu.CanOpen({ prof = ENCH }), false)
  -- No Blizzard menu API: nothing to open.
  Wow.stub("MenuUtil", nil)
  Assert.equal(ns.MainCrafterMenu.CanOpen({ prof = BS }), false)
end

local function testNoMenuUtil()
  local ns = load()
  Wow.stub("MenuUtil", nil)
  ns.MainCrafterMenu.Open({}, ns.Leads.List()[1])
  Assert.same(Wow.menu.entries, {})
end

return function()
  testEntries()
  testClassColour()
  testChoose()
  testLeadGone()
  testCanOpen()
  testNoMenuUtil()
  Wow.reset()
end
