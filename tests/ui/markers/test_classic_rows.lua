local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")
local MarkerFixture = require("tests.helpers.marker_fixture")
local RecipeListStub = require("tests.helpers.recipe_list_stub")
local ProfessionsClassic = require("tests.helpers.professions_classic")
local ClassicRowsStub = require("tests.helpers.classic_rows_stub")

-- The mute switches on the Classic TradeSkill and Craft rows (UI/RecipeMarkers/ClassicRows.lua,
-- plan 03-markers Revision 2026-10-27): when the update hooks install, which rows show a switch
-- and how it looks, the gates, what a click mutes, and repaints on scroll and Refresh. Rows are
-- write-trapping proxies, so any field written on a Blizzard row fails the test.

local look, switchOf = MarkerFixture.look, RecipeListStub.switchOf
local SPEAKER, MUTED = RecipeListStub.SPEAKER, RecipeListStub.MUTED

-- The Blacksmithing list, 10 rows: one more screen than the 8 buttons show.
local function blacksmithing()
  return {
    line = "Blacksmithing",
    rows = {
      { name = "Plate", kind = "header" },
      { name = "Sim Plate Belt" },
      { name = "Sim Plate Helm" },
      { name = "Sim Iron Bar" },
      { name = "Sim Plate Boots" },
      { name = "Mail", kind = "subheader" },
      { name = "Enchant Bracer - Sim Health" },
      { name = "Sim Mail Gloves" },
      { name = "Sim Mail Boots" },
      { name = "Sim Mail Chest" },
    },
  }
end

local function enchanting()
  return { line = "Enchanting", rows = { { name = "Bracer", kind = "header" }, { name = "Enchant Bracer - Sim Health" } } }
end

-- Me-Realm's stored records, by lowercase name: Sim Plate Boots is not stored, the helm and the
-- mail boots are muted, the iron bar has no binding, the bracer enchant is Enchanting's, and
-- "Plate" and "Mail" share a header's and a subheader's name.
local function stored()
  local function record(name, prof, fields)
    fields = fields or {}
    fields.name, fields.prof, fields.bind = name, prof, fields.bind or 4
    return fields
  end
  return {
    ["sim plate belt"] = record("Sim Plate Belt", "blacksmithing"),
    ["sim plate helm"] = record("Sim Plate Helm", "blacksmithing", { muted = true }),
    ["sim iron bar"] = record("Sim Iron Bar", "blacksmithing", { bind = 0 }),
    ["enchant bracer - sim health"] = record("Enchant Bracer - Sim Health", "enchanting"),
    ["sim mail gloves"] = record("Sim Mail Gloves", "blacksmithing"),
    ["sim mail boots"] = record("Sim Mail Boots", "blacksmithing", { muted = true }),
    ["sim mail chest"] = record("Sim Mail Chest", "blacksmithing"),
    ["plate"] = record("Plate", "blacksmithing"),
    ["mail"] = record("Mail", "blacksmithing"),
  }
end

-- Me-Realm on `opts.flavor` (default tbc) with Blacksmithing and Enchanting stored and both
-- windows open. opts.loaded (default true), opts.skillUps: ClassicRowsStub's; opts.db(db): edits
-- before the modules load. → ns, db, stub, state (ProfessionsClassic's).
local function load(opts)
  opts = opts or {}
  local flavor = opts.flavor or "tbc"
  local state, stub
  local ns, db = UiFixture.load({
    flavor = flavor,
    db = function(accountDb)
      accountDb.characters["Me-Realm"] = {
        source = "local",
        enabled = true,
        realms = { "Realm" },
        professions = { blacksmithing = { name = "Blacksmithing", read = true }, enchanting = { name = "Enchanting", read = true } },
        recipes = stored(),
      }
      if opts.db then
        opts.db(accountDb)
      end
    end,
    before = function(chain)
      state = ProfessionsClassic.install({ tradeSkill = blacksmithing(), craft = enchanting() })
      chain.FlavorCompat = Fresh.require("Core.FlavorCompat") -- hasCraftFrame reads the Craft stubs at load
      stub = ClassicRowsStub.install({ craft = true, loaded = opts.loaded ~= false, skillUps = opts.skillUps })
    end,
  })
  return ns, db, stub, state
end

local function looks(window, first, last)
  local found = {}
  for i = first, last do
    found[#found + 1] = look(window.rows[i])
  end
  return found
end

local ON, OFF_MUTED, GREYED = { SPEAKER, false }, { MUTED, false }, { SPEAKER, true }

-- Only a shown row whose recipe we store for the window's profession gets a switch; headers,
-- subheaders, unstored recipes and another profession's record get none. 14 × 14 at the row's
-- right end, our record behind its tooltip.
local function testPaint()
  local ns, db, stub = load()
  ns.ClassicRows.Install(db)
  stub.tradeSkill:update(0)
  Assert.same(looks(stub.tradeSkill, 1, 8), { "none", ON, OFF_MUTED, GREYED, "none", "none", "none", ON })
  local row = stub.tradeSkill.rows[2]
  local switch = assert(switchOf(row))
  Assert.same({ switch:GetWidth(), switch:GetHeight() }, { 14, 14 })
  Assert.same(switch.points[1], { "RIGHT", row, "RIGHT", 0, 0 })
  Assert.equal(switch.recipe, db.characters["Me-Realm"].recipes["sim plate belt"], "the tooltip's recipe is our record")

  stub.craft:update(0)
  Assert.same(looks(stub.craft, 1, 2), { "none", ON }, "the Craft window: Enchanting's records")
  Assert.same(looks(stub.craft, 3, 8), { "none", "none", "none", "none", "none", "none" }, "buttons past the list")
end

-- Scrolling calls Blizzard's update by name: the hook repaints the buttons for their new rows.
-- A list that shrinks hides its last buttons with their old IDs; those get no switch, also on a
-- Refresh after the list grew back and before Blizzard's next update.
local function testScrollRepaints()
  local ns, db, stub, state = load()
  ns.ClassicRows.Install(db)
  stub.tradeSkill:update(0)
  stub.tradeSkill:update(2)
  Assert.same(looks(stub.tradeSkill, 1, 8), { OFF_MUTED, GREYED, "none", "none", "none", ON, OFF_MUTED, ON })

  local full = state.tradeSkill.rows
  state.tradeSkill.rows = { { name = "Plate", kind = "header" }, { name = "Sim Plate Belt" } }
  stub.tradeSkill:update(0)
  local shrunk = { "none", ON, "none", "none", "none", "none", "none", "none" }
  Assert.same(looks(stub.tradeSkill, 1, 8), shrunk)
  state.tradeSkill.rows = full
  ns.ClassicRows.Refresh()
  Assert.same(looks(stub.tradeSkill, 1, 8), shrunk, "hidden buttons with stale IDs")
end

-- A click mutes or unmutes the row's recipe, repaints at once and requests a rebuild; it never
-- reaches the row (no select).
local function testClickMutes()
  local ns, db, stub = load()
  ns.ClassicRows.Install(db)
  stub.tradeSkill:update(0)
  local recipes = db.characters["Me-Realm"].recipes
  local row = stub.tradeSkill.rows[2]
  ns.Index.lastReason = nil
  Widgets.click(switchOf(row))
  Assert.equal(recipes["sim plate belt"].muted, true)
  Assert.same(look(row), OFF_MUTED, "repainted at once")
  Assert.equal(ns.Index.lastReason, "mute")
  Widgets.click(switchOf(stub.tradeSkill.rows[3]))
  Assert.equal(recipes["sim plate helm"].muted, nil, "muted → unmuted")
  Assert.same(stub.tradeSkill.clicks, { method = 0, script = 0 }, "the row's own click never ran")

  -- The same button scrolled to another row mutes that row's recipe.
  stub.tradeSkill:update(2)
  Widgets.click(switchOf(stub.tradeSkill.rows[6]))
  Assert.equal(recipes["sim mail gloves"].muted, true)
  Assert.equal(recipes["sim plate belt"].muted, true, "the old recipe is untouched")
end

-- Each gate hides every switch on Refresh (no update needed); once cleared, Refresh shows them
-- again. Refresh only reads: it never calls Blizzard's update.
local function testGates()
  local ns, db, stub, state = load()
  ns.ClassicRows.Install(db)
  stub.tradeSkill:update(0)
  stub.craft:update(0)
  local belt, enchant = stub.tradeSkill.rows[2], stub.craft.rows[2]
  local function both()
    return { look(belt), look(enchant) }
  end
  Assert.same(both(), { ON, ON })
  local updates = 0
  for _, name in ipairs({ "TradeSkillFrame_Update", "CraftFrame_Update" }) do
    local update = rawget(_G, name)
    Wow.stub(name, function(...)
      updates = updates + 1
      return update(...)
    end)
  end

  local function gate(label, set, clear)
    set()
    ns.ClassicRows.Refresh()
    Assert.same(both(), { "none", "none" }, label)
    clear()
    ns.ClassicRows.Refresh()
    Assert.same(both(), { ON, ON }, label .. " cleared")
  end
  gate("setting off", function()
    db.settings.recipeMarkers = false
  end, function()
    db.settings.recipeMarkers = true
  end)
  gate("instance", function()
    Wow.stub("IsInInstance", function()
      return true, "party"
    end)
  end, function()
    Wow.stub("IsInInstance", nil)
  end)
  gate("window closed", function()
    state.tradeSkill.open, state.craft.open = false, false
  end, function()
    state.tradeSkill.open, state.craft.open = nil, nil
  end)
  gate("profession not stored", function()
    state.tradeSkill.line, state.craft.line = "Tailoring", "Tailoring"
  end, function()
    state.tradeSkill.line, state.craft.line = "Blacksmithing", "Enchanting"
  end)

  state.tradeSkill.linked = true
  ns.ClassicRows.Refresh()
  Assert.same(both(), { "none", ON }, "another player's TradeSkill list")
  state.tradeSkill.linked = false
  state.craft.line = "Beast Training"
  ns.ClassicRows.Refresh()
  Assert.same(both(), { ON, "none" }, "the Craft window showing Beast Training")
  Assert.equal(updates, 0, "Refresh never calls Blizzard's update")
end

-- Hooks at once when the windows' addons are loaded, else on each addon's ADDON_LOADED, then
-- stops listening. Refresh before Install does nothing.
local function testInstall()
  local ns, db, stub = load({ loaded = false })
  ns.ClassicRows.Refresh()
  ns.ClassicRows.Install(db)
  Assert.equal(rawget(_G, "TradeSkillFrame_Update"), nil, "not loaded: nothing to hook yet")
  stub.tradeSkill:define()
  local blizzardUpdate = rawget(_G, "TradeSkillFrame_Update")
  Wow.fireEvent("ADDON_LOADED", "SomeOtherAddon")
  Assert.equal(rawget(_G, "TradeSkillFrame_Update"), blizzardUpdate)
  Wow.fireEvent("ADDON_LOADED", "Blizzard_TradeSkillUI")
  Assert.truthy(rawget(_G, "TradeSkillFrame_Update") ~= blizzardUpdate, "hooked")
  stub.tradeSkill:update(0)
  Assert.same(look(stub.tradeSkill.rows[2]), ON)

  stub.craft:define()
  Wow.fireEvent("ADDON_LOADED", "Blizzard_CraftUI")
  stub.craft:update(0)
  Assert.same(look(stub.craft.rows[2]), ON)
  for _, frame in ipairs(Wow.frames) do
    Assert.falsy(frame.events.ADDON_LOADED, "stopped listening")
  end
end

-- Setting off at login: nothing hooked; turned on, Refresh hooks and paints the shown rows.
local function testSettingOffHooksNothing()
  local ns, db, stub = load({
    db = function(accountDb)
      accountDb.settings.recipeMarkers = false
    end,
  })
  local blizzardUpdate = rawget(_G, "TradeSkillFrame_Update")
  ns.ClassicRows.Install(db)
  Assert.equal(rawget(_G, "TradeSkillFrame_Update"), blizzardUpdate, "setting off: not hooked")
  stub.tradeSkill:update(0)
  db.settings.recipeMarkers = true
  ns.ClassicRows.Refresh()
  Assert.same(look(stub.tradeSkill.rows[2]), ON, "the rows already shown")
  Assert.truthy(rawget(_G, "TradeSkillFrame_Update") ~= blizzardUpdate, "hooked")
end

-- No Craft window off Era and TBC: Blizzard_CraftUI's update is never hooked. On Wrath to MoP the
-- switch sits left of the row's skill-up count (R2).
local function testWrath()
  local ns, db, stub = load({ flavor = "wrath", skillUps = true })
  local craftUpdate = rawget(_G, "CraftFrame_Update")
  ns.ClassicRows.Install(db)
  Assert.equal(rawget(_G, "CraftFrame_Update"), craftUpdate, "no Craft hook on Wrath")
  stub.tradeSkill:update(0)
  local switch = assert(switchOf(stub.tradeSkill.rows[2]))
  Assert.same(switch.points[1], { "RIGHT", stub.tradeSkill.skillUps[2], "LEFT", 0, 0 })
end

return function()
  testPaint()
  testScrollRepaints()
  testClickMutes()
  testGates()
  testInstall()
  testSettingOffHooksNothing()
  testWrath()
  Wow.reset()
end
