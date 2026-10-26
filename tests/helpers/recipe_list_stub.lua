-- Blizzard's profession recipe list as the recipe markers (UI/RecipeMarkers/ModernRows.lua) see it:
-- ProfessionsFrame.CraftingPage.RecipeList.ScrollBox, ScrollUtil, the Professions rank helpers and
-- C_AddOns.IsAddOnLoaded, shared by the marker, bootstrap and runtime-rules tests.
--   local list = RecipeListStub.install({ recipes = { [101] = { learned = true } }, chains = { { 101, 102 } } })
--   local row, node = list:row(101)   -- a new row showing recipe 101 (nil: a category row)
--   list:init(row, 102)               -- the row re-initialized for recipe 102 (scroll, list change)
--   list.callbacks[1]                 -- { box, callback, owner, iterate } per AddInitializedFrameCallback
--   RecipeListStub.switchOf(row)      -- the mute switch the markers put on `row` (its child frame), or nil
--   RecipeListStub.SPEAKER, .MUTED    -- the atlases the switch's icon shows, from Theme.ART
-- opts.recipes: Blizzard recipe infos by recipe ID, each { learned, disabled }.
-- opts.chains: rank chains, each a list of recipe IDs, lowest rank first; any other recipe is a
-- single rank.
-- opts.loaded: what C_AddOns.IsAddOnLoaded("Blizzard_Professions") returns; nil leaves C_AddOns
-- and the global IsAddOnLoaded missing.
-- opts.noHelpers: Professions.GetHighestLearnedRecipe and EnumerateRecipes missing.
-- opts.noScrollBox / opts.noScrollUtil: that part of the client missing.
-- opts.onRegister(box): called after each AddInitializedFrameCallback is recorded.
-- list.box:ForEachFrame(fn) stops at the first truthy return of fn, as Blizzard's does.
-- Rows, nodes, node data and recipe infos are RuntimeTraps proxies made on first use, so a write
-- on any of them raises; call RuntimeTraps.install (which resets proxies) before list:row.
-- list.clicks counts calls of the rows' own Click method and OnClick script.
local Wow = require("tests.helpers.wow")
local RuntimeTraps = require("tests.helpers.runtime_traps")
local Theme = require("CraftAlert.UI.Theme")

local RecipeListStub = {}

RecipeListStub.SPEAKER = Theme.ART.SPEAKER_ATLAS
RecipeListStub.MUTED = Theme.ART.MUTED_ATLAS

-- The switch the markers put on `row`: its only child frame, or nil.
function RecipeListStub.switchOf(row)
  for _, frame in ipairs(Wow.frames) do
    if frame.parent == row then
      return frame
    end
  end
  return nil
end

local List = {}
List.__index = List

-- The proxied Blizzard recipe info for `id`, one per ID.
function List:info(id)
  if self.infos[id] == nil then
    local fields = self.recipes[id] or {}
    local real = { recipeID = id, learned = fields.learned == true, disabled = fields.disabled == true }
    self.infos[id] = RuntimeTraps.proxy(real, "recipeInfo" .. id)
  end
  return self.infos[id]
end

-- The proxied infos of the rank chain `id` belongs to, lowest rank first.
function List:chainOf(id)
  local found = {}
  for _, chain in ipairs(self.chains) do
    for _, rank in ipairs(chain) do
      if rank == id then
        for i, chainId in ipairs(chain) do
          found[i] = self:info(chainId)
        end
        return found
      end
    end
  end
  return { self:info(id) }
end

local function newNode(list, id)
  local data = id and { recipeInfo = list:info(id) } or { categoryInfo = { name = "Category" } }
  local dataProxy = RuntimeTraps.proxy(data, "nodeData")
  local real = {}
  function real:GetData()
    return dataProxy
  end
  return RuntimeTraps.proxy(real, "node")
end

-- A new row frame showing recipe `id` (nil: a category row) → row, node (both proxies).
function List:row(id)
  local real = _G["CreateFrame"]("Button", nil, _G["UIParent"])
  real:SetSize(300, 20)
  local clicks = self.clicks
  function real:Click()
    clicks.method = clicks.method + 1
  end
  real:SetScript("OnClick", function()
    clicks.script = clicks.script + 1
  end)
  local entry = { row = RuntimeTraps.proxy(real, "row"), node = newNode(self, id) }
  self.rows[#self.rows + 1] = entry
  return entry.row, entry.node
end

-- The row re-initialized by Blizzard for recipe `id`: a new node, then every registered callback.
function List:init(row, id)
  for _, entry in ipairs(self.rows) do
    if entry.row == row then
      entry.node = newNode(self, id)
      for _, call in ipairs(self.callbacks) do
        call.callback(call.owner, row, entry.node)
      end
    end
  end
end

local function stubProfessions(list)
  Wow.stub("Professions", {
    EnumerateRecipes = function(recipeInfo)
      return ipairs(list:chainOf(recipeInfo.recipeID))
    end,
    GetHighestLearnedRecipe = function(recipeInfo)
      local learned = nil
      for _, info in ipairs(list:chainOf(recipeInfo.recipeID)) do
        if not info.learned then
          break
        end
        learned = info
      end
      return learned
    end,
  })
end

local function stubScrollBox(list)
  local box = {}
  function box:ForEachFrame(fn)
    for _, entry in ipairs(list.rows) do
      if fn(entry.row, entry.node) then
        return
      end
    end
  end
  list.box = box
  Wow.stub("ProfessionsFrame", { CraftingPage = { RecipeList = { ScrollBox = box } } })
end

function RecipeListStub.install(opts)
  opts = opts or {}
  local list = setmetatable({
    recipes = opts.recipes or {},
    chains = opts.chains or {},
    infos = {},
    rows = {},
    callbacks = {},
    clicks = { method = 0, script = 0 },
  }, List)
  if opts.loaded ~= nil then
    Wow.stub("C_AddOns", {
      IsAddOnLoaded = function(name)
        return name == "Blizzard_Professions" and opts.loaded
      end,
    })
  else
    Wow.stub("C_AddOns", nil)
  end
  Wow.stub("IsAddOnLoaded", nil)
  Wow.stub("Professions", nil)
  if not opts.noHelpers then
    stubProfessions(list)
  end
  Wow.stub("ProfessionsFrame", nil)
  if not opts.noScrollBox then
    stubScrollBox(list)
  end
  Wow.stub("ScrollUtil", nil)
  if not opts.noScrollUtil then
    Wow.stub("ScrollUtil", {
      AddInitializedFrameCallback = function(box, callback, owner, iterate)
        list.callbacks[#list.callbacks + 1] = { box = box, callback = callback, owner = owner, iterate = iterate }
        if opts.onRegister then
          opts.onRegister(box)
        end
      end,
    })
  end
  return list
end

return RecipeListStub
