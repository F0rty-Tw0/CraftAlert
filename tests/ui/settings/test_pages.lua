local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")
local SettingsFixture = require("tests.helpers.settings_fixture")

local open, row, take = SettingsFixture.open, SettingsFixture.row, SettingsFixture.take

local function testLazyWindow()
  local ns = SettingsFixture.load()
  -- §4.4 rule 5: no frame before the first open. The pane lives in the leads window.
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"), nil)
  ns.LeadsWindow.ToggleSettings()
  local window = SettingsFixture.window()
  Assert.truthy(window, "created on first open")
  Assert.equal(window.template, "ButtonFrameTemplate")
  Assert.equal(window:GetTitleText():GetText(), "Craft Alert — Settings")
  Assert.equal(window:IsShown(), true)
  Assert.equal(window.movable, true)
  Assert.equal(window.clamped, true)
  -- Opens on the first page; ESC closes it (own name in UISpecialFrames, once).
  Assert.truthy(SettingsFixture.texts():find("Enable Craft Alert", 1, true))
  ns.LeadsWindow.ToggleSettings()
  Assert.equal(window:IsShown(), false)
  ns.LeadsWindow.ToggleSettings()
  Assert.same(rawget(_G, "UISpecialFrames"), { "CraftAlertLeadsWindow" })
  -- One nav button per §9 page, in order (Linked accounts comes with Task 4.2).
  local titles = {}
  for _, frame in ipairs(Wow.frames) do
    if frame.pageId then
      titles[#titles + 1] = frame.label:GetText()
    end
  end
  Assert.same(titles, { "General", "Alerts", "Greetings", "Keywords", "Crafters", "Test" })
end

local function testAddPage()
  local ns = SettingsFixture.load()
  local built = 0
  local page = {
    id = "linked",
    title = "Linked accounts",
    Create = function(parent)
      built = built + 1
      local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      text:SetText("export box")
      return { Refresh = function() end }
    end,
  }
  -- Added before the window exists: listed once it is made, built on first selection.
  ns.SettingsPane.AddPage(page)
  ns.LeadsWindow.ToggleSettings()
  Assert.equal(built, 0, "a page is built when first shown")
  open(ns, "Linked accounts")
  open(ns, "General")
  open(ns, "Linked accounts")
  Assert.equal(built, 1)
  Assert.truthy(SettingsFixture.texts():find("export box", 1, true))
  Assert.falsy(SettingsFixture.texts():find("Enable Craft Alert", 1, true), "other pages hidden")
  -- Added after the window exists: gets its nav button at once.
  ns.SettingsPane.AddPage({ id = "late", title = "Late", Create = page.Create })
  open(ns, "Late")
  Assert.equal(built, 2)
end

-- Native-HUD spec §7.1: quest-log list art on the nav (selected and hover), the nav in an inset
-- at the top left of the leads window's inset, each page to its right.
local function testNavHighlight()
  local ns = SettingsFixture.load()
  local Theme, padding = ns.Theme, ns.Theme.LAYOUT.PADDING
  open(ns, "General")
  local function selectedPages()
    local shown = {}
    for _, title in ipairs({ "General", "Alerts", "Greetings", "Keywords", "Crafters", "Test" }) do
      if SettingsFixture.navButton(title).selected:IsShown() then
        shown[#shown + 1] = title
      end
    end
    return shown
  end
  Assert.same(selectedPages(), { "General" })
  local selected = SettingsFixture.navButton("General").selected
  Assert.equal(selected.texture, Theme.ART.LIST_SELECTED)
  Assert.equal(selected.blendMode, "ADD")
  Assert.equal(selected:GetAlpha(), 0.45)
  open(ns, "Alerts")
  Assert.same(selectedPages(), { "Alerts" }, "the highlight follows the page")
  for _, frame in ipairs(Wow.frames) do
    if frame.pageId then
      local hover
      for _, region in ipairs(frame.regions) do
        if region.layer == "HIGHLIGHT" then
          hover = region
        end
      end
      Assert.truthy(hover, frame.pageId .. " has a hover highlight")
      Assert.same({ hover.texture, hover:GetAlpha() }, { Theme.ART.LIST_HOVER, 0.18 })
    end
  end
  local window = SettingsFixture.window()
  local nav = SettingsFixture.navButton("General").parent
  Assert.equal(nav.template, "InsetFrameTemplate")
  Assert.same(nav.points[1], { "TOPLEFT", window.content, "TOPLEFT", padding, -padding })
  -- The Alerts page's content frame: the pane container's child that holds its rows.
  local content = SettingsFixture.row("Lead timeout")
  while content.parent ~= nav.parent do
    content = content.parent
  end
  local besideNav = false
  for _, point in ipairs(content.points) do
    besideNav = besideNav or point[2] == nav
  end
  Assert.truthy(besideNav, "a page sits right of the nav")
end

-- §6.1: enable and "Only where Trade chat exists" re-evaluate the gate; §6.2: channels, profession-word
-- alerts and unbound items rebuild the index (channels also re-evaluate the registered events).
local function testGeneralPage()
  local ns, db, refreshes = SettingsFixture.load()
  local settings = db.settings
  open(ns, "General")
  take(refreshes)
  local cases = {
    { "Enable Craft Alert", "enable", { "evaluate" } },
    { "Only where Trade chat exists", "onlyResting", { "evaluate" } },
    { "Profession-word alerts", "professionWordAlerts", { "rebuild:professionWordAlerts" } },
    { "Include unbound items", "includeUnbound", { "rebuild:includeUnbound" } },
    { "Bell markers on recipe rows", "recipeMarkers", {} },
  }
  for _, case in ipairs(cases) do
    local before = settings[case[2]]
    Widgets.click(row(case[1]).input)
    Assert.equal(settings[case[2]], not before, case[2])
    Assert.same(take(refreshes), case[3], case[2])
  end
  Widgets.click(row("General").input)
  Assert.equal(settings.channels.general, true)
  Assert.same(take(refreshes), { "rebuild:channels", "evaluate" })
  Widgets.click(row("Trade").input)
  Assert.equal(settings.channels.trade, false)
  for _, label in ipairs({ "Services", "LookingForGroup", "Guild", "Communities" }) do
    Assert.truthy(row(label), label .. " exists on Retail")
  end
  -- The page shows what the db holds each time it opens.
  settings.channels.guild = true
  ns.LeadsWindow.ToggleSettings()
  ns.LeadsWindow.ToggleSettings()
  Assert.equal(row("Guild").input:GetChecked(), true)
end

local function testChannelsPerFlavor()
  local ns = SettingsFixture.load({
    before = function(chain)
      -- TBC has no Services, LookingForGroup or Communities channel (Constants.flavors).
      chain.FlavorCompat.flavorKey = "tbc"
    end,
  })
  open(ns, "General")
  Assert.truthy(row("Trade"))
  Assert.truthy(row("Guild"))
  Assert.raises(function()
    row("Services")
  end, "no visible row")
  Assert.raises(function()
    row("Communities")
  end, "no visible row")
end

local function testAlertsPage()
  local ns, db, refreshes, calls = SettingsFixture.load()
  local settings = db.settings
  open(ns, "Alerts")
  take(refreshes)
  -- Sound: None or one of the flavor's kits; "Play" plays the chosen one.
  local sound = row("Alert sound").input
  Widgets.pick(sound, 0)
  Assert.equal(settings.sound, 0, "None")
  Widgets.click(SettingsFixture.button(SettingsFixture.window(), "Play"))
  Assert.equal(#UiFixture.callsTo(calls, "sound"), 0, "None plays nothing")
  Widgets.pick(sound, 3081)
  Assert.equal(settings.sound, 3081)
  Widgets.click(SettingsFixture.button(SettingsFixture.window(), "Play"))
  Assert.same(UiFixture.callsTo(calls, "sound"), { { "sound", 3081, "Master" } })
  Widgets.click(row("Flash the taskbar icon").input)
  Assert.equal(settings.flash, false)
  Assert.same(take(refreshes), {}, "sound and flash are read when an alert fires")

  -- Each slider counts its steps as (max - min) / step, rounded (§7.3).
  Assert.equal(row("Toast duration").input.initArgs[4], 23)
  Assert.equal(row("Lead timeout").input.initArgs[4], 59)
  Assert.equal(row("Opacity").input.initArgs[4], 14)
  Widgets.slide(row("Toast duration").input, 45)
  Assert.equal(settings.toastDuration, 45)
  Assert.same(take(refreshes), {})
  -- Lead timeout re-arms the expiry timer, so existing leads expire on the new timeout.
  Widgets.slide(row("Lead timeout").input, 3)
  Assert.equal(settings.leadTimeoutMin, 3)
  Assert.same(take(refreshes), { "rearm" })
  Widgets.click(row("Hide the launcher when there are no leads").input)
  Assert.equal(settings.hideLauncherWhenNoLeads, true)
  Assert.same(take(refreshes), { "launcher" })
  Widgets.slide(row("Opacity").input, 0.5)
  Assert.equal(settings.opacity, 0.5)
  Assert.same(take(refreshes), { "leadsWindow" })
end

local function character(professions)
  return { source = "local", enabled = true, realms = { "Realm" }, professions = professions, recipes = {} }
end

-- §7.4: templates and per-profession notes are written as typed; the preview is
-- Greeting.Build on a sample lead per template and follows every change. No refresh is
-- triggered: greetings are built when a lead is clicked.
local function testGreetingsPage()
  local ns, db, refreshes = SettingsFixture.load({
    db = function(accountDb)
      accountDb.characters["Me-Realm"] = character({ [333] = { name = "Enchanting", primary = false, read = true } })
      accountDb.characters["Alt-Realm"] = character({ [164] = { name = "Blacksmithing", primary = false, read = true } })
    end,
  })
  local settings = db.settings
  open(ns, "Greetings")
  take(refreshes)
  local texts = SettingsFixture.texts()
  Assert.truthy(texts:find("Item: Hi! I can craft Sample Item.", 1, true), texts)
  Assert.truthy(texts:find("Alt item: Hi! My alt Alt can craft Sample Item, send the order there.", 1, true), texts)
  Assert.truthy(texts:find("Profession: Hi! I have Blacksmithing, what do you need?", 1, true), texts)
  Assert.equal(row("Item").input:GetText(), "Hi! I can craft {item}.")

  Widgets.type(row("Item").input, "Yo {customer}, {item} here.")
  Assert.equal(settings.templates.item, "Yo {customer}, {item} here.")
  Assert.truthy(SettingsFixture.texts():find("Item: Yo Customer, Sample Item here.", 1, true))
  Widgets.type(row("Alt profession").input, "{crafter} does {profession}")
  Assert.equal(settings.templates.altProfession, "{crafter} does {profession}")
  -- An emptied template would whisper nothing: it goes back to the default, as the box shows.
  Widgets.type(row("Item").input, "   ")
  Assert.equal(settings.templates.item, "Hi! I can craft {item}.")
  Assert.equal(row("Item").input:GetText(), "Hi! I can craft {item}.")
  Widgets.type(row("Alt profession").input, "")
  Assert.equal(settings.templates.altProfession, ns.Defaults.Settings().templates.altProfession)
  -- Template and note boxes stop at 255 letters (SetMaxLetters counts characters, not bytes;
  -- Greeting.Build cuts the whisper to 255 bytes).
  Assert.equal(row("Item").input.maxLetters, 255)
  Assert.equal(row("Note").input.maxLetters, 255)

  -- Professions by name; the note goes to the one shown and joins its preview lines.
  Assert.equal(row("Note for").input.Text:GetText(), "Blacksmithing")
  Widgets.type(row("Note").input, "Bring mats.")
  Assert.same(settings.notes, { [164] = "Bring mats." })
  Assert.truthy(SettingsFixture.texts():find("what do you need? Bring mats.", 1, true))
  Widgets.pick(row("Note for").input, 333)
  Assert.equal(row("Note for").input.Text:GetText(), "Enchanting")
  Assert.equal(row("Note").input:GetText(), "", "the shown note follows the profession")
  Assert.truthy(SettingsFixture.texts():find("Profession: Hi! I have Enchanting, what do you need?", 1, true))
  Widgets.pick(row("Note for").input, 164)
  Widgets.type(row("Note").input, "")
  Assert.same(settings.notes, {}, "an emptied note is removed")
  Assert.same(take(refreshes), {})
end

return function()
  testLazyWindow()
  testAddPage()
  testNavHighlight()
  testGeneralPage()
  testChannelsPerFlavor()
  testAlertsPage()
  testGreetingsPage()
end
