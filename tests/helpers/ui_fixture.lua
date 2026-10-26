-- Real addon modules for the UI tests: the Matcher fixture's core, the lead and greet chain,
-- then the UI files, each loaded fresh after Wow.reset. The player is Me-Realm, not AFK; time()
-- is UiFixture.T0 and GetTime() 50. Every send lands in `calls` as { api, args... }.
--   local ns, db, calls = UiFixture.load({ leads = 2 })   -- two leads, ids 1..2, newest last
--   UiFixture.lead(id, customer)                          -- one lead record
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")
local Fixture = require("tests.helpers.matcher_fixture")

local UiFixture = {}

UiFixture.T0 = 1000

local CHAIN = {
  "Core.Localization",
  "Core.ChatPrint",
  "Model.Greeting",
  "Model.SendGuard",
  "Model.RealmTag",
  "Model.CrafterRank",
  "Model.Leads",
  "Model.GreetAction",
  "Professions.ProfessionList",
  "Core.Status",
  "Core.ScanGate",
}
local UI = {
  "UI.Theme",
  "UI.FrameKit",
  "UI.ScrollBar",
  "UI.ScrollView",
  "UI.LeadText",
  "UI.ClickRouter",
  "UI.Tooltip",
  "UI.LinkHover",
  "UI.Dock",
  "UI.CardBody",
  "UI.MainCrafterMenu",
  "UI.CardTipText",
  "UI.LeadRow",
  "UI.DetailsBody",
  "UI.DetailsHeader",
  "UI.LeadDetails",
  "UI.LeadsList",
  "UI.LeadsView",
  "UI.WindowSize",
  "UI.GhostResize",
  "UI.SettingsGear",
  "UI.Settings.SettingsPane",
  "UI.LeadsWindow",
  "UI.LauncherArt",
  "UI.Launcher",
  "UI.ToastLayout",
  "UI.AlertToast",
  "UI.Settings.Column",
  "UI.Settings.Controls",
  "UI.Settings.RecipeMute",
  "UI.RecipeMarkers.MarkerState",
  "UI.RecipeMarkers.ModernRows",
  "UI.Settings.PageGeneral",
  "UI.Settings.PageAlerts",
  "UI.Settings.PageGreetings",
  "UI.Settings.PageKeywords",
  "UI.Settings.RecipeTooltip",
  "UI.Settings.RecipeRarity",
  "UI.Settings.RecipeList",
  "UI.Settings.PageCrafters",
  "UI.Settings.PageTest",
  "UI.BridgePanel",
  "UI.BridgeInfo",
  "UI.WhisperBridge",
  "Core.Bindings",
  "Core.Perf",
  "Core.TestReport",
  "Core.TestLine",
  "Core.SlashCommands",
}
-- Globals Core/Bindings.lua defines at load: stubbed first, so Wow.reset removes them again.
UiFixture.BINDING_GLOBALS = {
  "BINDING_HEADER_CRAFTALERT",
  "BINDING_NAME_CRAFTALERT_GREET",
  "BINDING_NAME_CRAFTALERT_DISMISS",
  "BINDING_NAME_CRAFTALERT_TOGGLE",
  "CraftAlert_GreetLatest",
  "CraftAlert_DismissLatest",
  "CraftAlert_ToggleLeads",
}

-- An unexpired Blacksmithing profession lead from `customer` (default Customer<id>-Draenor).
function UiFixture.lead(id, customer)
  return {
    id = id,
    customer = customer or ("Customer" .. id .. "-Draenor"),
    message = "  LF plate belt  ",
    channel = "trade",
    kind = "profession",
    prof = 164,
    profName = "Blacksmithing",
    why = "lf + blacksmith",
    crafter = "Me-Realm",
    time = UiFixture.T0,
    greeted = false,
    replied = false,
  }
end

local function stubPlayer()
  Wow.clock.time = UiFixture.T0
  Wow.clock.gettime = 50
  Wow.stub("UnitName", function()
    return "Me"
  end)
  Wow.stub("GetNormalizedRealmName", function()
    return "Realm"
  end)
  Wow.stub("UnitIsAFK", function()
    return false
  end)
end

local function stubSends(calls)
  local function record(api)
    return function(...)
      calls[#calls + 1] = { api, ... }
    end
  end
  Wow.stub("C_ChatInfo", { SendAddonMessage = record("addon"), SendChatMessage = record("chat") })
  Wow.stub("ChatFrameUtil", { SendTellWithMessage = record("prefill"), SendTell = record("empty") })
  Wow.stub("PlaySound", record("sound"))
  Wow.stub("FlashClientIcon", record("flash"))
end

-- The Blizzard UI table the window touches. The UI's tooltip is its own GameTooltipTemplate frame
-- (ns.Tooltip.Get(), faked in tests/helpers/templates.lua); the shared GameTooltip stays the
-- trap tests/helpers/wow.lua installs.
local function stubBlizzardUi()
  Wow.stub("UISpecialFrames", {})
end

-- opts.leads: how many lead records db.leads starts with; opts.db(db): edits before Restore;
-- opts.before(ns): runs after the chain loads and before the UI files do.
function UiFixture.load(opts)
  opts = opts or {}
  local ns = Fixture.load("retail")
  stubPlayer()
  local calls = {}
  stubSends(calls)
  stubBlizzardUi()
  ns.PlayerName.Init()
  local db = ns.Defaults.Db()
  Wow.stub("CraftAlertDB", db)
  for id = 1, opts.leads or 0 do
    db.leads[id] = UiFixture.lead(id)
  end
  if opts.db then
    opts.db(db)
  end
  for _, path in ipairs(CHAIN) do
    ns[string.match(path, "%.(%w+)$")] = Fresh.require(path)
  end
  ns.Leads.Restore(db)
  if opts.before then
    opts.before(ns)
  end
  for _, name in ipairs(UiFixture.BINDING_GLOBALS) do
    Wow.stub(name, nil)
  end
  for _, path in ipairs(UI) do
    ns[string.match(path, "%.(%w+)$")] = Fresh.require(path)
  end
  return ns, db, calls
end

-- The calls made to one api, in order.
function UiFixture.callsTo(calls, api)
  local found = {}
  for _, call in ipairs(calls) do
    if call[1] == api then
      found[#found + 1] = call
    end
  end
  return found
end

return UiFixture
