local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local Fixture = require("tests.helpers.matcher_fixture")
local SettingsFixture = require("tests.helpers.settings_fixture")

local CraftersFixture = require("tests.helpers.crafters_fixture")

local open, row, take, texts = SettingsFixture.open, SettingsFixture.row, SettingsFixture.take, SettingsFixture.texts
local BS, ENCH, crafters, rowOf, iconOf =
  CraftersFixture.BS, CraftersFixture.ENCH, CraftersFixture.crafters, CraftersFixture.rowOf, CraftersFixture.iconOf

-- §6.2: keyword changes rebuild the index (the hot path reads copies).
local function testKeywordsPage()
  local ns, db, refreshes = SettingsFixture.load({ leads = 2 })
  local settings = db.settings
  open(ns, "Keywords")
  take(refreshes)
  local shown = SettingsFixture.texts()
  Assert.truthy(shown:find('Example: kicks=boots makes "LF kicks" find boots.', 1, true), shown)
  local targets = "Targets are slot words (belt, boots, helm, chest) or type words (plate, mail, leather, cloth)."
  Assert.truthy(shown:find(targets, 1, true), shown)
  Assert.equal(row("Intent words").input:GetText(), "lf lfc lfrc wtb wtc need needs looking any any1 anyone who recraft")
  Widgets.type(row("Intent words").input, "LF  need, wtb lf")
  Assert.same(settings.intentWords, { "lf", "need", "wtb" }, "lowercase, once each")
  Assert.same(take(refreshes), { "rebuild:keywords" })
  Widgets.type(row("Intent words").input, "  ")
  Assert.same(settings.intentWords, { "lf", "lfc", "lfrc", "wtb", "wtc", "need", "needs", "looking", "any", "any1", "anyone", "who", "recraft" })
  Assert.equal(row("Intent words").input:GetText(), "lf lfc lfrc wtb wtc need needs looking any any1 anyone who recraft", "empty → defaults")
  take(refreshes)
  Widgets.type(row("Blocker words").input, "")
  Assert.same(settings.blockerWords, {}, "no blocker words is allowed")
  Assert.same(take(refreshes), { "rebuild:keywords" })

  -- Extra slang: word=target pairs; anything else is dropped.
  Widgets.type(row("Extra slang (word=slot)").input, "Pauldron=shoulders, hat=helm junk =x y=")
  Assert.same(settings.extraSlang, { pauldron = "shoulders", hat = "helm" })
  Assert.same(take(refreshes), { "rebuild:keywords" })
  Assert.equal(row("Extra slang (word=slot)").input:GetText(), "hat=helm pauldron=shoulders")

  -- A word list longer than a chat line is kept whole, also through a reopen and a focus loss
  -- (a capped box would commit its cut text).
  local long, slang = {}, {}
  for i = 1, 60 do
    long[i] = "word" .. i
    slang[i] = "w" .. i .. "=belt"
  end
  Widgets.type(row("Intent words").input, table.concat(long, " "))
  Widgets.type(row("Extra slang (word=slot)").input, table.concat(slang, " "))
  ns.LeadsWindow.ToggleSettings()
  open(ns, "Keywords")
  for _, label in ipairs({ "Intent words", "Extra slang (word=slot)" }) do
    local box = row(label).input
    box:SetFocus()
    box:ClearFocus()
  end
  Assert.truthy(#table.concat(long, " ") > 255)
  Assert.same(settings.intentWords, long)
  local slangCount = 0
  for _ in pairs(settings.extraSlang) do
    slangCount = slangCount + 1
  end
  Assert.equal(slangCount, 60)
end

-- §6.2: crafter enable/disable, removal and mute rebuild the index; the primary crafter is
-- read when a lead picks its crafter (§6.3 step 5), so it rebuilds nothing.
local function testCraftersPage()
  local ns, db, refreshes = SettingsFixture.load({ db = crafters })
  local me = db.characters["Me-Realm"]
  open(ns, "Crafters")
  take(refreshes)
  local page = texts()
  Assert.truthy(page:find("This character", 1, true), "the first section is named for the group, not the dropdown")
  Assert.truthy(page:find("Recipes", 1, true), page)
  Assert.falsy(page:find("Professions", 1, true), "no heading that echoes the Profession dropdown")
  local character = row("Character").input
  Assert.equal(character.Text:GetText(), "Me-Realm (this character)", "opens on the current character")
  Widgets.pick(character, "Alt-Realm")
  Assert.equal(character.Text:GetText(), "Alt-Realm (same account)")
  Widgets.pick(character, "Far-Away")
  Assert.equal(character.Text:GetText(), "Far-Away (imported)")
  Widgets.pick(character, "Me-Realm")

  Widgets.click(row("Listen for this character").input)
  Assert.equal(me.enabled, false)
  Assert.same(take(refreshes), { "rebuild:crafter" })

  -- Primary: one crafter per profession; it is the shown character's for the shown profession.
  Assert.equal(row("Profession").input.Text:GetText(), "Blacksmithing")
  Widgets.click(row("Main crafter for this profession").input)
  Assert.equal(me.professions[BS].primary, true)
  Assert.equal(db.characters["Alt-Realm"].professions[BS].primary, false, "the other primary is cleared")
  Widgets.click(row("Main crafter for this profession").input)
  Assert.equal(me.professions[BS].primary, false, "switched off again")
  Assert.equal(db.characters["Alt-Realm"].professions[BS].primary, false, "nobody else gains it")
  Widgets.click(row("Main crafter for this profession").input)
  Assert.same(take(refreshes), {})

  -- Recipes of that profession by name, with search; the mute icon toggles and rebuilds.
  local shown = texts()
  Assert.truthy(shown:find("Plate Greaves / Thick Plate Belt", 1, true), shown)
  Assert.falsy(shown:find("Enchant Bracer", 1, true))
  local recipe = rowOf(9002)
  local nameEnd = { "RIGHT", recipe.mute, "LEFT", -ns.Theme.LAYOUT.PADDING, 0 }
  Assert.same(recipe.name.points[2], nameEnd, "a long name stops short of the mute icon on a narrow page")
  local search = row("Search recipes").input
  Assert.same({ search.template, search.Instructions:GetText() }, { "SearchBoxTemplate", "Search recipes" }, "the native search box")
  Widgets.type(search, "BELT")
  Assert.falsy(texts():find("Plate Greaves", 1, true))
  Widgets.type(search, "")
  Assert.truthy(texts():find("Plate Greaves", 1, true), "an emptied search lists every recipe")
  search.text = "belt"
  Widgets.fire(search, "OnTextChanged", true)
  Assert.falsy(texts():find("Plate Greaves", 1, true), "narrowed without Enter")
  -- The speaker, swapped for the crossed-out speaker while muted (one texture, never greyed).
  local mute = rowOf(9001).mute
  Assert.same({ #mute.regions, mute.icon.atlas, mute.icon.desaturated }, { 1, "voicechat-icon-speaker", false }, "not muted: the speaker")
  Widgets.click(mute)
  Assert.equal(me.recipes[9001].muted, true)
  Assert.same(take(refreshes), { "rebuild:mute" })
  mute = rowOf(9001).mute
  Assert.same({ mute.icon.atlas, mute.icon.desaturated }, { "voicechat-icon-speaker-mute", false }, "muted: the crossed-out speaker")
  Assert.equal(iconOf(9001).desaturated, true, "a muted recipe's icon is grey")
  Widgets.click(mute)
  Assert.equal(me.recipes[9001].muted, nil)
  Assert.equal(mute.icon.atlas, "voicechat-icon-speaker")
  Assert.equal(iconOf(9001).desaturated, false)
  -- The clear button empties the search and lists every recipe again.
  Widgets.fire(search.clearButton, "OnClick")
  Assert.truthy(texts():find("Plate Greaves / Thick Plate Belt", 1, true), texts())
  Assert.same(take(refreshes), { "rebuild:mute" })
  Widgets.pick(row("Profession").input, ENCH)
  Assert.truthy(texts():find("Enchant Bracer - Health", 1, true), "the search clears with the profession")

  -- Remove asks for a second click, then drops the character and shows the next one.
  local remove = SettingsFixture.button(SettingsFixture.window(), "Remove character")
  Widgets.click(remove)
  Assert.truthy(db.characters["Me-Realm"], "not on the first click")
  Assert.same(take(refreshes), {})
  Widgets.click(SettingsFixture.button(SettingsFixture.window(), "Click again to remove"))
  Assert.equal(db.characters["Me-Realm"], nil)
  Assert.same(take(refreshes), { "rebuild:crafter" })
  Assert.equal(character.Text:GetText(), "Alt-Realm (same account)")
end

-- A mute made outside the page (the profession window) shows when the index rebuilds: the open
-- list repaints in place, a hidden one does nothing until it is shown.
local function testCraftersRepaintsOnRebuild()
  local ns, db = SettingsFixture.load({ db = crafters })
  ns.Index.Configure(db)
  open(ns, "Crafters")
  local recipes = db.characters["Me-Realm"].recipes
  Assert.equal(rowOf(9001).mute.icon.atlas, "voicechat-icon-speaker")
  recipes[9001].muted = true
  ns.Index.Rebuild()
  Assert.equal(rowOf(9001).mute.icon.atlas, "voicechat-icon-speaker-mute", "the open list repaints")
  Assert.equal(iconOf(9001).desaturated, true)

  local muteRow = rowOf(9001)
  ns.LeadsWindow.ToggleSettings()
  recipes[9001].muted = nil
  ns.Index.Rebuild()
  Assert.equal(muteRow.mute.icon.atlas, "voicechat-icon-speaker-mute", "hidden: no repaint")
  open(ns, "Crafters")
  Assert.equal(rowOf(9001).mute.icon.atlas, "voicechat-icon-speaker", "shown again: current")
end

-- The recipe keys of the visible recipe rows, top to bottom.
local function shownRecipeKeys()
  local keys = {}
  for _, frame in ipairs(Wow.frames) do
    if frame.icon and frame.item and SettingsFixture.visible(frame) then
      keys[#keys + 1] = frame.item.key
    end
  end
  return keys
end

-- Names stored lowercase (read before the client spelling was kept) sort among the others, not
-- after them; names equal but for case keep one order, by recipe key.
local function testCraftersRecipeOrder()
  local ns = SettingsFixture.load({
    db = function(accountDb)
      crafters(accountDb)
      accountDb.characters["Me-Realm"].recipes = {
        [9001] = { name = "Thick Plate Belt", prof = BS },
        [9002] = { name = "plate greaves", prof = BS },
        [9003] = { name = "Iron Rivet", prof = BS },
        [9004] = { name = "iron rivet", prof = BS },
        [10] = { name = "Copper Bar", prof = BS },
        [9] = { name = "copper bar", prof = BS },
        -- Name keys (as Classic stores recipes) among the IDs: text order alone would loop
        -- (9 < 10 by number, 10 < "1x" and "1x" < 9 as text).
        ["1x"] = { name = "Copper Bar", prof = BS },
        ["25y"] = { name = "Copper Bar", prof = BS },
      }
    end,
  })
  open(ns, "Crafters")
  -- Equal names: recipe IDs in number order (9 before 10), then name keys. The page shows 8 rows.
  Assert.same(shownRecipeKeys(), { 9, 10, "1x", "25y", 9003, 9004, 9002, 9001 })
end

-- Unmuted recipes first, then muted ones, then unbound ones (they never alert, muted or not), each
-- group by name. A speaker click repaints in place; the next refresh moves the row to its group.
local function testCraftersRecipeGroups()
  local ns = SettingsFixture.load({
    db = function(accountDb)
      crafters(accountDb)
      accountDb.characters["Me-Realm"].recipes = {
        [9001] = { name = "A Bar", prof = BS, bind = 0 },
        [9002] = { name = "B Belt", prof = BS, muted = true },
        [9003] = { name = "C Belt", prof = BS },
        [9004] = { name = "D Flask", prof = BS, bind = 0, muted = true },
        [9005] = { name = "E Belt", prof = BS },
      }
    end,
  })
  open(ns, "Crafters")
  Assert.same(shownRecipeKeys(), { 9003, 9005, 9002, 9001, 9004 }, "unmuted, muted, unbound")
  Widgets.click(rowOf(9003).mute)
  Assert.same(shownRecipeKeys(), { 9003, 9005, 9002, 9001, 9004 }, "a speaker click keeps the order")
  -- Every name holds a space: a search that lists them all, as a refresh.
  Widgets.type(row("Search recipes").input, " ")
  Assert.same(shownRecipeKeys(), { 9005, 9002, 9003, 9001, 9004 }, "the next refresh regroups")
end

-- Recipe rows show the crafted item's icon, else the recipe spell's (number keys), else the
-- addon icon (a name key from Classic has neither); a muted row is grey and dim.
local function testCraftersRecipeIcons()
  local ns, db = SettingsFixture.load({
    db = function(accountDb)
      crafters(accountDb)
      accountDb.characters["Me-Realm"].recipes = {
        [9001] = { item = 501, name = "Belt", prof = BS },
        [9002] = { name = "Bracer", prof = BS },
        ["Old Recipe"] = { name = "Old Recipe", prof = BS },
      }
    end,
  })
  Wow.stub("GetItemInfoInstant", function(id)
    return id, nil, nil, nil, "item-icon"
  end)
  Wow.stub("C_Spell", {
    GetSpellTexture = function(id)
      return id == 9002 and "spell-icon" or nil
    end,
  })
  open(ns, "Crafters")
  Assert.equal(iconOf(9001).texture, "item-icon", "item recipe")
  Assert.equal(iconOf(9002).texture, "spell-icon", "no item: the spell")
  Assert.equal(iconOf("Old Recipe").texture, ns.Theme.ICON, "name key: the addon icon")
  Assert.equal(iconOf(9001).desaturated, false)
  db.characters["Me-Realm"].recipes[9001].muted = true
  Widgets.pick(row("Profession").input, ENCH)
  Widgets.pick(row("Profession").input, BS)
  Assert.equal(iconOf(9001).desaturated, true, "muted: grey")
  Assert.equal(iconOf(9001).alpha, ns.Theme.DIM_ALPHA, "muted: dim")
  Assert.equal(iconOf(9001).texture, "item-icon", "muted keeps its icon")
  Assert.same(rowOf(9001).name.textColor, { 1, 1, 1, ns.Theme.DIM_ALPHA }, "no C_Item: white, dim while muted")
  Assert.same(rowOf(9002).name.textColor, { 1, 1, 1, 1 }, "no C_Item: white")
end

-- The recipe list's own scroll bar: hidden and the wheel left to the page while the recipes fit;
-- shown over the rows the list cannot show, the wheel taken, when they do not. A drag pages the
-- rows to the nearest whole recipe; the rows end 5 px short of the bar, shown or not.
local function testCraftersRecipeBar()
  local ns = SettingsFixture.load({ db = crafters })
  open(ns, "Crafters")
  local list = rowOf(9001).parent
  local bar
  for _, frame in ipairs(Wow.frames) do
    if frame.frameType == "Slider" and frame.parent == list then
      bar = frame
    end
  end
  Assert.truthy(bar, "the list has its bar")
  Assert.same(bar.points, { { "TOPRIGHT", list, "TOPRIGHT", 0, 0 }, { "BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0 } })
  Assert.equal(bar:IsShown(), false, "two recipes fit: no bar")
  Assert.equal(list.mouseWheelEnabled, false, "the wheel falls through to the page")
  local right = rowOf(9001).points[2]
  Assert.same({ right[1], right[2], right[3], right[4] }, { "TOPRIGHT", list, "TOPRIGHT", -(bar:GetWidth() + 5) })

  ns = SettingsFixture.load({
    db = function(accountDb)
      crafters(accountDb)
      local recipes = {}
      for id = 1, 11 do
        recipes[9200 + id] = { name = string.format("R %02d", id), prof = BS }
      end
      accountDb.characters["Me-Realm"].recipes = recipes
    end,
  })
  open(ns, "Crafters")
  list = rowOf(9201).parent
  for _, frame in ipairs(Wow.frames) do
    if frame.frameType == "Slider" and frame.parent == list then
      bar = frame
    end
  end
  Assert.equal(bar:IsShown(), true, "11 recipes, 8 rows: the bar shows")
  Assert.same({ bar:GetMinMaxValues() }, { 0, 3 })
  Assert.equal(list.mouseWheelEnabled, true)
  bar:SetValue(2.6)
  Assert.equal(shownRecipeKeys()[1], 9204, "a drag to 2.6 shows from the 4th recipe")
  Assert.equal(bar:GetValue(), 3, "the bar settles on the row")
  Widgets.fire(list, "OnMouseWheel", 1)
  Assert.equal(shownRecipeKeys()[1], 9203)
  Assert.equal(bar:GetValue(), 2, "the bar follows the wheel")
  Widgets.type(row("Search recipes").input, "R 1")
  Assert.same(shownRecipeKeys(), { 9210, 9211 }, "a search that fits shows from the top")
  Assert.equal(bar:IsShown(), false, "the list fits again: no bar")
  Assert.equal(list.mouseWheelEnabled, false)
end

-- An empty list says why: nothing read yet (also with no profession shown), or the search found none.
local function testCraftersEmptyList()
  local readYet = "No recipes read yet. Open this profession's window in the game to read them."
  local ns = SettingsFixture.load({ db = crafters })
  open(ns, "Crafters")
  Assert.falsy(texts():find("No recipes read yet", 1, true), "recipes listed: no empty line")
  Widgets.pick(row("Character").input, "Far-Away")
  Assert.truthy(texts():find("No professions read for this character yet.", 1, true), texts())
  Assert.falsy(texts():find("No recipes read yet", 1, true), "no profession: no advice to open its window")
  Widgets.pick(row("Character").input, "Me-Realm")
  Assert.falsy(texts():find("No recipes read yet", 1, true), "recipes listed: no empty line")
  Widgets.type(row("Search recipes").input, "zzz")
  Assert.truthy(texts():find("No recipe matches your search.", 1, true), texts())
  Assert.falsy(texts():find("No recipes read yet", 1, true), "a search with no match is not the unread line")
  Widgets.type(row("Search recipes").input, "")
  Assert.falsy(texts():find("No recipe matches", 1, true), "search cleared: recipes listed again")

  -- A profession known but never read.
  local unread = SettingsFixture.load({
    db = function(accountDb)
      crafters(accountDb)
      accountDb.characters["Me-Realm"].professions[171] = { name = "Alchemy", primary = false, read = false }
    end,
  })
  open(unread, "Crafters")
  Widgets.pick(row("Profession").input, 171)
  Assert.truthy(texts():find(readYet, 1, true), texts())
end

-- A tooltip hidden by the client (no OnLeave) while a row is hovered comes back when the scroll
-- puts an item recipe under the cursor; after OnLeave the scroll shows none.
local function testCraftersRecipeHoverAfterHide()
  local ns = SettingsFixture.load({
    db = function(accountDb)
      crafters(accountDb)
      local recipes = { ["Old Recipe"] = { name = "A Old Recipe", prof = BS } }
      for id = 1, 8 do
        recipes[9100 + id] = { item = 600 + id, name = "B " .. id, prof = BS }
      end
      accountDb.characters["Me-Realm"].recipes = recipes
    end,
  })
  open(ns, "Crafters")
  local tooltip, first = ns.Tooltip.Get(), rowOf("Old Recipe")
  Widgets.fire(first, "OnEnter")
  Assert.equal(tooltip.lines[1], "A Old Recipe")
  tooltip:Hide()
  Widgets.fire(first.parent, "OnMouseWheel", -1)
  Assert.equal(first.item.key, 9101)
  Assert.same({ tooltip.shown, tooltip.owner }, { true, first }, "the hovered row shows its new recipe")
  Assert.equal(tooltip.hyperlinks[#tooltip.hyperlinks], "item:601")
  Widgets.fire(first, "OnLeave")
  Widgets.fire(first.parent, "OnMouseWheel", 1)
  Assert.equal(tooltip.shown, false, "not hovered: no tooltip")

  -- A row hidden while hovered (the settings closed under the cursor) forgets the hover.
  Widgets.fire(first, "OnEnter")
  tooltip:Hide()
  ns.LeadsWindow.ToggleSettings()
  open(ns, "Crafters")
  Assert.equal(tooltip.shown, false, "hidden while hovered: no tooltip on reopen")
end

-- Hovering a recipe row that makes an item shows the item's tooltip; one without an item shows
-- our own: the recipe name in gold and its profession. Under either: who knows it, and a grey
-- note when it is muted. Rows are reused by the scroll: the tooltip reads the row's recipe at
-- hover time, and a tooltip a row owns follows the repaint.
local function testCraftersRecipeTooltip()
  local ns, db = SettingsFixture.load({
    db = function(accountDb)
      crafters(accountDb)
      accountDb.characters["Alt-Other"] = {
        source = "local",
        enabled = true,
        realms = { "Other" },
        professions = { [BS] = { name = "Blacksmithing" } },
        recipes = { [9001] = { item = 501, name = "A Belt", prof = BS } },
      }
      -- Two more owners, added so pairs() order is not already sorted (the sort is what the line shows).
      accountDb.characters["Bob-Other"] = accountDb.characters["Alt-Other"]
      accountDb.characters["Zed-Other"] = accountDb.characters["Alt-Other"]
      local recipes = {
        [9001] = { item = 501, name = "A Belt", prof = BS },
        -- Muted once the list is sorted (below), so it keeps its place between A and C.
        [9002] = { name = "B Bracer", prof = BS },
        ["Old Recipe"] = { name = "C Old Recipe", prof = BS },
      }
      for id = 1, 8 do
        recipes[9100 + id] = { item = 600 + id, name = "D " .. id, prof = BS }
      end
      accountDb.characters["Me-Realm"].recipes = recipes
    end,
  })
  open(ns, "Crafters")
  local tooltip = ns.Tooltip.Get()
  local itemRow, mutedRow = rowOf(9001), rowOf(9002)
  db.characters["Me-Realm"].recipes[9002].muted = true

  Widgets.fire(itemRow, "OnEnter")
  Assert.equal(tooltip.owner, itemRow)
  Assert.equal(tooltip.anchor, "ANCHOR_RIGHT")
  Assert.same(tooltip.hyperlinks, { "item:501" }, "the crafted item's tooltip")
  Assert.same(tooltip.lines, { " ", "Known by: Alt, Alt-Other, Bob-Other, Me, Zed-Other" })
  Assert.same(tooltip.colors[2], { 1, 1, 1 })
  Assert.equal(tooltip.shown, true)
  Widgets.fire(itemRow, "OnLeave")
  Assert.equal(tooltip.shown, false)
  db.characters["Me-Realm"].recipes[9001].muted = true
  Widgets.fire(itemRow, "OnEnter")
  Assert.same(tooltip.lines, { " ", "Known by: Alt, Alt-Other, Bob-Other, Me, Zed-Other", "Muted" })
  Assert.same(tooltip.colors[3], { 0.5, 0.5, 0.5 })
  Widgets.fire(itemRow, "OnLeave")
  db.characters["Me-Realm"].recipes[9001].muted = nil

  Widgets.fire(mutedRow, "OnEnter")
  Assert.same(tooltip.lines, { "B Bracer", "Blacksmithing", " ", "Known by: Me", "Muted" }, "no item: our own lines")
  Assert.same(tooltip.colors[1], { 1, 0.82, 0 })
  Assert.equal(#tooltip.hyperlinks, 2, "no item: no item tooltip")
  Assert.equal(tooltip.owner, mutedRow)
  Widgets.fire(mutedRow, "OnLeave")

  -- 11 recipes, 8 rows: each wheel step moves the rows one recipe. A row that owns the tooltip repaints it.
  local list = itemRow.parent
  Widgets.fire(itemRow, "OnEnter")
  Widgets.fire(list, "OnMouseWheel", -1)
  Assert.equal(itemRow.item.key, 9002)
  Assert.equal(tooltip.owner, itemRow)
  Assert.equal(tooltip.lines[1], "B Bracer", "repainted to the row's new recipe")
  Assert.equal(tooltip.lines[#tooltip.lines], "Muted")
  Widgets.fire(list, "OnMouseWheel", -1)
  Assert.equal(itemRow.item.key, "Old Recipe")
  Assert.equal(tooltip.lines[1], "C Old Recipe", "repainted onto a name key: shows")

  -- No tooltip open: the scroll shows none, the next hover shows the row's new recipe.
  Widgets.fire(itemRow, "OnLeave")
  Widgets.fire(list, "OnMouseWheel", -1)
  Assert.equal(tooltip.shown, false)
  Assert.equal(itemRow.item.key, 9101)
  Widgets.fire(itemRow, "OnEnter")
  Assert.equal(tooltip.hyperlinks[#tooltip.hyperlinks], "item:601")
  Assert.equal(tooltip.shown, true)
end

-- Classic keys a recipe by its name: the tooltip title is the recipe's name, and its owners are
-- the characters that hold that key.
local function testRecipeTooltipNameKey()
  local ns = SettingsFixture.load({
    db = function(accountDb)
      crafters(accountDb)
      accountDb.characters["Me-Realm"].recipes = {
        ["Old Recipe"] = { name = "C Old Recipe", prof = BS },
      }
    end,
  })
  open(ns, "Crafters")
  Widgets.fire(rowOf("Old Recipe"), "OnEnter")
  Assert.same(ns.Tooltip.Get().lines, { "C Old Recipe", "Blacksmithing", " ", "Known by: Me" })
end

-- GameTooltip_OnUpdate (Blizzard GameTooltip.lua): the owner's UpdateTooltip when it has one;
-- else, once an item load flagged the tooltip (TOOLTIP_DATA_UPDATE), the rebuild from the item
-- data, which drops lines added after SetHyperlink. Only that rebuild clears the flag.
local function clientUpdate(tooltip)
  local owner = tooltip.owner
  if owner.UpdateTooltip then
    owner:UpdateTooltip()
  elseif tooltip.shouldRefreshData then
    tooltip.shouldRefreshData = false
    tooltip:ClearLines()
  end
end

-- An item that loads while its tooltip shows: the client's rebuild would drop our lines, so the
-- recipe row has an UpdateTooltip that shows our tooltip again on every update, lines included
-- and read anew. A link the client rejects gets our own tooltip.
local function testRecipeTooltipItemLoads()
  local ns, db = SettingsFixture.load({
    db = function(accountDb)
      crafters(accountDb)
      accountDb.characters["Me-Realm"].recipes = { [9001] = { item = 501, name = "A Belt", prof = BS } }
    end,
  })
  open(ns, "Crafters")
  local tooltip, itemRow = ns.Tooltip.Get(), rowOf(9001)
  Widgets.fire(itemRow, "OnEnter")
  local ours = tooltip.lines[2] -- lines[1] is the blank above it
  Assert.truthy(ours:find("^Known by: "), ours)
  tooltip.shouldRefreshData = true -- the item loaded
  for _ = 1, 3 do
    clientUpdate(tooltip)
    Assert.same(tooltip.lines, { " ", ours }, "every update keeps our lines")
  end
  Assert.same(tooltip.hyperlinks, { "item:501", "item:501", "item:501", "item:501" })
  db.characters["Me-Realm"].recipes[9001].muted = true
  clientUpdate(tooltip)
  Assert.same(tooltip.lines, { " ", ours, "Muted" }, "read anew")

  tooltip.badLinks = { ["item:501"] = true }
  Widgets.fire(itemRow, "OnEnter")
  Assert.same(tooltip.lines, { "A Belt", "Blacksmithing", " ", ours, "Muted" }, "rejected link: our own tooltip")
end

-- Removing the current character stores it again from the client at once (as at login), so its
-- profession windows keep recording instead of waiting for the next login.
local function testRemoveOwnCharacter()
  local ns, db = SettingsFixture.load({ db = crafters })
  Wow.stub("GetProfessions", function()
    return 1
  end)
  Wow.stub("GetProfessionInfo", function()
    return "Blacksmithing", nil, 1, 100, nil, nil, BS
  end)
  Wow.stub("C_AutoComplete", {
    GetAutoCompleteRealms = function()
      return { "Realm", "Twisting Nether" }
    end,
  })
  open(ns, "Crafters")
  Widgets.click(SettingsFixture.button(SettingsFixture.window(), "Remove character"))
  Widgets.click(SettingsFixture.button(SettingsFixture.window(), "Click again to remove"))
  local me = db.characters["Me-Realm"]
  Assert.truthy(me, "stored again")
  Assert.same(me.recipes, {}, "its recipes are gone")
  Assert.same(me.professions, { [BS] = { name = "Blacksmithing", primary = false, read = false } })
  Assert.equal(ns.ProfessionList.IsStored(db, "Me-Realm", BS), true)
  -- Its connected realms are stored again too, as at login, so the realm tag knows them now.
  Assert.same(me.realms, { "Realm", "TwistingNether" })
  Assert.equal(ns.RealmTag.CannotOrder(db, "Me-Realm", "Bob-Draenor"), true)
  Assert.truthy(db.characters["Alt-Realm"].recipes[9001], "other characters are untouched")

  -- Another character is not the client's: it stays removed.
  local character = row("Character").input
  Widgets.pick(character, "Alt-Realm")
  Assert.equal(character.Text:GetText(), "Alt-Realm (same account)")
  Widgets.click(SettingsFixture.button(SettingsFixture.window(), "Remove character"))
  Widgets.click(SettingsFixture.button(SettingsFixture.window(), "Click again to remove"))
  Assert.equal(db.characters["Alt-Realm"], nil, "an alt is not stored again")
end

-- §9 Test: a line → result and "why", through Matcher.MatchUngated (no gate, no lead, no
-- ignore check); a line that stops says where.
local function testTestPage()
  local fixtureDb
  local ns, db = SettingsFixture.load({
    db = function(accountDb)
      fixtureDb = accountDb
      -- The fixture's three crafters (Fixture.db only needs Defaults, loaded by now).
      for key, character in pairs(Fixture.db({ Defaults = require("CraftAlert.Persistence.Defaults") }).characters) do
        accountDb.characters[key] = character
      end
    end,
    before = function(chain)
      chain.Matcher.SetIndex(Fixture.index(chain, fixtureDb))
    end,
  })
  Wow.stub("C_FriendList", {
    IsIgnored = function()
      return true
    end,
  })
  open(ns, "Test")
  Widgets.type(row("Test a line").input, "lf lion heart")
  local shown = texts()
  Assert.truthy(shown:find("Item: Lionheart Helm", 1, true), shown)
  Assert.truthy(shown:find("Why: lf + lion + heart", 1, true), shown)
  Assert.truthy(shown:find("Crafter: Smith-Realm", 1, true), shown)
  Widgets.type(row("Test a line").input, "Any Enchaters in ORG?")
  shown = texts()
  Assert.truthy(shown:find("Profession: 333", 1, true), shown)
  Assert.truthy(shown:find("Crafter: Ench-Realm", 1, true), shown)
  Assert.falsy(shown:find("Lionheart", 1, true), "the last result is replaced")
  -- A profession stored without a name (a CraftScan import) shows its ID.
  db.characters["Ench-Realm"].professions[333].name = ""
  Widgets.type(row("Test a line").input, "Any Enchaters in ORG??")
  shown = texts()
  Assert.truthy(shown:find("Profession: 333", 1, true), shown)
  Widgets.type(row("Test a line").input, "hello there")
  Assert.truthy(texts():find("No match: the line does not look like a request", 1, true), texts())
  Assert.same(db.leads, {}, "no lead")
end

return function()
  testKeywordsPage()
  testCraftersPage()
  testCraftersRepaintsOnRebuild()
  testCraftersRecipeOrder()
  testCraftersRecipeGroups()
  testCraftersRecipeIcons()
  testCraftersRecipeBar()
  testCraftersEmptyList()
  testCraftersRecipeTooltip()
  testCraftersRecipeHoverAfterHide()
  testRecipeTooltipNameKey()
  testRecipeTooltipItemLoads()
  testRemoveOwnCharacter()
  testTestPage()
end
