local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Constants = ns.Constants or require("CraftAlert.Core.Constants")
local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local ChatPrint = ns.ChatPrint or require("CraftAlert.Core.ChatPrint")
local EventRouter = ns.EventRouter or require("CraftAlert.Core.EventRouter")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local SavedState = ns.SavedState or require("CraftAlert.Persistence.SavedState")
local Schema = ns.Schema or require("CraftAlert.Persistence.Schema")
local Index = ns.Index or require("CraftAlert.Model.Index")
local Matcher = ns.Matcher or require("CraftAlert.Model.Matcher")
local RealmTag = ns.RealmTag or require("CraftAlert.Model.RealmTag")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local Ledger = ns.Ledger or require("CraftAlert.Model.Ledger")
local OrdersFilled = ns.OrdersFilled or require("CraftAlert.Model.OrdersFilled")
local AwaySummary = ns.AwaySummary or require("CraftAlert.Model.AwaySummary")
local WhisperTracker = ns.WhisperTracker or require("CraftAlert.Model.WhisperTracker")
local ProfessionList = ns.ProfessionList or require("CraftAlert.Professions.ProfessionList")
local ModernReader = ns.ModernReader or require("CraftAlert.Professions.ModernReader")
local ClassicReader = ns.ClassicReader or require("CraftAlert.Professions.ClassicReader")
local CraftReader = ns.CraftReader or require("CraftAlert.Professions.CraftReader")
local QualityReach = ns.QualityReach or require("CraftAlert.Professions.QualityReach")
local LearnWatcher = ns.LearnWatcher or require("CraftAlert.Professions.LearnWatcher")
local Status = ns.Status or require("CraftAlert.Core.Status")
local ScanGate = ns.ScanGate or require("CraftAlert.Core.ScanGate")
local AlertToast = ns.AlertToast or require("CraftAlert.UI.AlertToast")
local WhisperBridge = ns.WhisperBridge or require("CraftAlert.UI.WhisperBridge")
local LeadsWindow = ns.LeadsWindow or require("CraftAlert.UI.LeadsWindow")
local CraftScanPrompt = ns.CraftScanPrompt or require("CraftAlert.UI.CraftScanPrompt")
local ModernRows = ns.ModernRows or require("CraftAlert.UI.RecipeMarkers.ModernRows")
local ClassicRows = ns.ClassicRows or require("CraftAlert.UI.RecipeMarkers.ClassicRows")
local Launcher = ns.Launcher or require("CraftAlert.UI.Launcher")
local PageAlerts = ns.PageAlerts or require("CraftAlert.UI.Settings.PageAlerts")
local Perf = ns.Perf or require("CraftAlert.Core.Perf")
local TestLine = ns.TestLine or require("CraftAlert.Core.TestLine")
local SlashCommands = ns.SlashCommands or require("CraftAlert.Core.SlashCommands")

-- Single owner of cross-module wiring: ADDON_LOADED loads the account DB, PLAYER_LOGIN
-- installs every module in dependency order and prints the login lines (spec §7.6). A task
-- that adds a module with an Install adds its line here.
local Bootstrap = {}

local concat = table.concat
local ipairs = ipairs
local pcall = pcall

local ADDON = "CraftAlert"
local ADDON_LOADED = "ADDON_LOADED"
local PLAYER_LOGIN = "PLAYER_LOGIN"
local SKILL_LINES_CHANGED = "SKILL_LINES_CHANGED"

---@type table
local db = nil
local ownKey = nil
local bridged = false -- WhisperMessenger's API is there (WhisperBridge.Activate)
local loadMs = 0 -- SavedState.Load at ADDON_LOADED, added into Perf.loginMs

-- At login the profession slots may not have loaded yet (ProfessionList keeps what is stored
-- then); once they change, a new profession order rebuilds the index and refreshes the
-- launcher's idle icon (the first profession; Launcher.Refresh is a no-op before Create).
local function onSkillLinesChanged()
  if ProfessionList.Refresh(db, ownKey) then
    Index.RequestRebuild("professions")
    Launcher.Refresh()
  end
end

local function installProfessions()
  ProfessionList.Refresh(db, ownKey)
  EventRouter.On(SKILL_LINES_CHANGED, onSkillLinesChanged)
end

-- Classic reads the TradeSkill window and, on Era and TBC, Enchanting's Craft window.
local function installReaders()
  if FlavorCompat.isClassic then
    ClassicReader.Install(db)
    CraftReader.Install(db)
    LearnWatcher.InstallClassic(Constants.flavors[FlavorCompat.flavorKey].learnSignal)
    return
  end
  ModernReader.Install(db)
  LearnWatcher.Install()
end

local function installQualityReach()
  if FlavorCompat.isClassic then
    return
  end
  QualityReach.Install(db)
end

-- Before wireLeads, which picks the "new" subscriber by the answer.
local function activateBridge()
  bridged = WhisperBridge.Activate()
end

-- Before wireLeads: Leads.Restore fires no "new", "greeted" or "replied".
local function installLedger()
  Ledger.Install(db)
end

-- Retail only: the other flavors have no crafting orders.
local function installOrdersFilled()
  if FlavorCompat.isRetail then
    OrdersFilled.Install(db)
  end
end

-- After activateBridge: the summary shows where the leads do (WM's preview, else the own toast).
local function installAwaySummary()
  AwaySummary.Install(bridged and WhisperBridge.ShowSummary or AlertToast.ShowSummary)
end

-- AlertToast and WhisperTracker subscribe themselves to "change", TestReport to "new" and "change".
local function wireLeads()
  Leads.Restore(db)
  EventRouter.On("IGNORELIST_UPDATE", Leads.DismissIgnored)
  Leads.On("new", bridged and WhisperBridge.ShowLead or AlertToast.Show)
  Leads.On("change", Launcher.Refresh)
  Leads.On("change", LeadsWindow.Refresh)
  PageAlerts.SetOnLauncherToggle(Launcher.Refresh)
  PageAlerts.SetOnOpacity(LeadsWindow.Refresh)
  WhisperTracker.Install()
  TestLine.Install()
end

-- §7.6 and §5.2: the newer-schema warning of the load, the status line, the professions not read
-- yet, and on a fresh DB the first-run hint. The gate prints the status line on its first
-- activation, so an active scan at login has printed it already. A login or /reload inside an
-- instance prints nothing (no addon line in the chat frame there).
local function printLoginLines()
  if FlavorCompat.InInstance() then
    return
  end
  Schema.WarnNewer()
  if not ScanGate.IsActive() then
    ChatPrint.Line(Status.Text(ScanGate.State()))
  end
  local unread = ProfessionList.UnreadNames(db, ownKey)
  if #unread > 0 then
    ChatPrint.Line(Localization.Text("Open %s once to start listening.", concat(unread, ", ")))
  end
  if SavedState.isFirstRun then
    ChatPrint.Line(Localization.Text("After opening a profession, try /ca test LF <profession> crafter"))
  end
end

-- After the login lines: CraftScan's one-time offer (Retail; CraftScanPrompt checks the rest).
local function promptCraftScan()
  CraftScanPrompt.MaybeShow(db)
end

local function storeRealms()
  RealmTag.Store(db, ownKey)
end

local function wireIndex()
  Index.Configure(db, { professionOrder = ProfessionList.Order, ownKey = ownKey })
  Index.OnRebuilt(Matcher.SetIndex)
  Index.OnRebuilt(ScanGate.Evaluate)
end

local function installScanGate()
  ScanGate.Install(db)
end

-- The mute switches on Blizzard's recipe rows (the Classic TradeSkill and Craft windows, else
-- Retail and Forever's profession window) repaint on every rebuild and gate change.
local function installMarkers()
  local rows = FlavorCompat.isClassic and ClassicRows or ModernRows
  rows.Install(db)
  Index.OnRebuilt(rows.Refresh)
  ScanGate.OnChange(rows.Refresh)
end

local function createLauncher()
  Launcher.Create()
  Launcher.OnMoved(AlertToast.Dock)
  ScanGate.OnChange(Launcher.Refresh)
  ScanGate.OnChange(AlertToast.OnGate)
  ScanGate.OnChange(WhisperBridge.OnGate)
  ScanGate.OnChange(LeadsWindow.OnGate)
  ScanGate.OnChange(WhisperTracker.Refresh)
end

local function buildIndex()
  Index.Rebuild()
end

-- In dependency order. Each step runs on its own: one that raises is reported and the rest
-- still run. ScanGate and Leads bind the db last, so a raising install leaves its module
-- unbound and fail-closed: only ScanGate.Evaluate registers the chat events, and only once the
-- resting events are registered, Leads holds its db and the index is built.
local LOGIN_STEPS = {
  installProfessions,
  storeRealms,
  wireIndex,
  activateBridge,
  installLedger,
  installOrdersFilled,
  installAwaySummary,
  wireLeads,
  WhisperBridge.SyncInfo,
  installReaders,
  installQualityReach,
  installScanGate,
  installMarkers,
  createLauncher,
  buildIndex,
  printLoginLines,
  promptCraftScan,
}

-- → whether the step ran without raising.
local function runStep(step)
  local ok, err = pcall(step)
  if not ok then
    EventRouter.ReportError(err)
  end
  return ok
end

local function readOwnKey()
  ownKey = PlayerName.Own()
end

-- `/ca` is registered first, so it works whatever a later step does; it reads the player's
-- name only when used. Without a db (the load raised at ADDON_LOADED and was reported there)
-- or the player's name, no step can work, so none runs.
local function onLogin()
  EventRouter.Off(PLAYER_LOGIN, onLogin)
  runStep(SlashCommands.Register)
  if db == nil or not runStep(PlayerName.Init) then
    return
  end
  local clock = _G["debugprofilestop"]
  local started = clock()
  if not runStep(readOwnKey) then
    return
  end
  for _, step in ipairs(LOGIN_STEPS) do
    runStep(step)
  end
  Perf.loginMs = loadMs + clock() - started
end

-- No PlayerName call here: the realm is not known before PLAYER_LOGIN on every flavor. The
-- load and schema check count toward the login time (§4.4).
local function onAddonLoaded(name)
  if name ~= ADDON then
    return
  end
  EventRouter.Off(ADDON_LOADED, onAddonLoaded)
  local clock = _G["debugprofilestop"]
  local started = clock()
  db = SavedState.Load()
  loadMs = clock() - started
end

EventRouter.On(ADDON_LOADED, onAddonLoaded)
EventRouter.On(PLAYER_LOGIN, onLogin)

ns.Bootstrap = Bootstrap
return Bootstrap
