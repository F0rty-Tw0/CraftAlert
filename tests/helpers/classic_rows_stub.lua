-- Blizzard's Classic TradeSkill and Craft windows as the recipe markers (UI/RecipeMarkers/ClassicRows.lua)
-- see them: the row buttons TradeSkillSkill1..8 and Craft1..8, TRADE_SKILLS_DISPLAYED and
-- CRAFTS_DISPLAYED, the TradeSkillFrame_Update and CraftFrame_Update globals, and
-- C_AddOns.IsAddOnLoaded. The list rows come from ProfessionsClassic's stubs (GetNumTradeSkills,
-- GetTradeSkillInfo, GetNumCrafts, GetCraftInfo), so install those first.
--   local stub = ClassicRowsStub.install({ craft = true, loaded = false })
--   stub.tradeSkill:update(offset)   -- Blizzard's update scrolled to `offset` (default: the last one)
--   stub.tradeSkill.rows[i]          -- the row button TradeSkillSkill<i> (a proxy)
--   stub.tradeSkill.clicks           -- calls of the rows' own Click method and OnClick script
-- opts.craft: the Craft window exists too. opts.loaded: what IsAddOnLoaded answers for both
-- windows' addons. Before `defined` (set by opts.loaded, or by stub:define() as the addon's load
-- would), the update globals and the row buttons are missing. opts.skillUps: each row has its
-- <row name>NumSkillUps frame (Wrath to MoP).
-- As the client: update shows list rows offset + 1 .. on the buttons by SetID and hides the
-- buttons past the list, which keep their old ID; the hooks run after it. The globals are called
-- by name, so a hook installed with hooksecurefunc(name, hook) runs on every update.
-- Row buttons are RuntimeTraps proxies, so a write on one raises.
local Wow = require("tests.helpers.wow")
local RuntimeTraps = require("tests.helpers.runtime_traps")

local ClassicRowsStub = {}

ClassicRowsStub.DISPLAYED = 8

local Window = {}
Window.__index = Window

-- Blizzard's update, called by name as the scroll frame and the list events do.
function Window:update(offset)
  self.offset = offset or self.offset
  rawget(_G, self.updateName)()
end

local function newRow(window, name)
  local real = _G["CreateFrame"]("Button", nil, _G["UIParent"])
  real:SetSize(300, 16)
  real.id = 0
  function real:SetID(id)
    self.id = id
  end
  function real:GetID()
    return self.id
  end
  local clicks = window.clicks
  function real:Click()
    clicks.method = clicks.method + 1
  end
  real:SetScript("OnClick", function()
    clicks.script = clicks.script + 1
  end)
  return real, RuntimeTraps.proxy(real, name)
end

-- The window's buttons and update global, as its addon's load creates them.
function Window:define()
  for i = 1, ClassicRowsStub.DISPLAYED do
    local name = self.prefix .. i
    local real, row = newRow(self, name)
    self.real[i], self.rows[i] = real, row
    Wow.stub(name, row)
    if self.skillUps then
      local skillUps = _G["CreateFrame"]("Frame", nil, real)
      self.skillUps[i] = RuntimeTraps.proxy(skillUps, name .. "NumSkillUps")
      Wow.stub(name .. "NumSkillUps", self.skillUps[i])
    end
  end
  Wow.stub(self.displayedName, ClassicRowsStub.DISPLAYED)
  Wow.stub(self.updateName, function()
    local count = rawget(_G, self.countName)()
    for i, real in ipairs(self.real) do
      local index = self.offset + i
      if index <= count then
        real:SetID(index)
        real:Show()
      else
        real:Hide()
      end
    end
  end)
end

local function newWindow(opts, names)
  local window = setmetatable({ offset = 0, real = {}, rows = {}, skillUps = opts.skillUps and {} or nil }, Window)
  window.clicks = { method = 0, script = 0 }
  window.prefix, window.updateName, window.displayedName, window.countName = names[1], names[2], names[3], names[4]
  for _, name in ipairs({ window.updateName, window.displayedName }) do
    Wow.stub(name, nil)
  end
  if opts.loaded then
    window:define()
  end
  return window
end

function ClassicRowsStub.install(opts)
  opts = opts or {}
  local stub = {}
  stub.tradeSkill = newWindow(opts, { "TradeSkillSkill", "TradeSkillFrame_Update", "TRADE_SKILLS_DISPLAYED", "GetNumTradeSkills" })
  if opts.craft then
    stub.craft = newWindow(opts, { "Craft", "CraftFrame_Update", "CRAFTS_DISPLAYED", "GetNumCrafts" })
  end
  local addons = { Blizzard_TradeSkillUI = true, Blizzard_CraftUI = opts.craft == true }
  Wow.stub("C_AddOns", {
    IsAddOnLoaded = function(name)
      return addons[name] == true and opts.loaded == true
    end,
  })
  Wow.stub("IsAddOnLoaded", nil)
  return stub
end

return ClassicRowsStub
