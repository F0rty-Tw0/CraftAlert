-- Classic profession API stubs (Era to MoP), shared by the Classic tests and tools/sim.lua.
--   local state = ProfessionsClassic.install({ skillLines = { { name = "Professions", header = true }, { name = "Blacksmithing" } } })
--   state.skillLines[1].collapsed = true   -- the player folded the header
-- state.skillLines: GetNumSkillLines/GetSkillLineInfo rows (Era, TBC, Wrath), each
-- { name, header, collapsed }. A collapsed header reports isExpanded false; the lines the client
-- would hide under it are the test's to leave out.
-- state.slots: when set, GetProfessions/GetProfessionInfo as on Cata and MoP (ProfessionsRetail's
-- slot shape) in place of the skill lines.
-- state.items, bind, cached, requests, autoCache: C_Item data as in ProfessionsRetail.installItems.
local Wow = require("tests.helpers.wow")
local ProfessionsRetail = require("tests.helpers.professions_retail")

local ProfessionsClassic = {}

local function installSkillLines(state)
  Wow.stub("GetNumSkillLines", function()
    return #state.skillLines
  end)
  Wow.stub("GetSkillLineInfo", function(index)
    local line = state.skillLines[index]
    if line == nil then
      return nil
    end
    local header = line.header == true
    return line.name, header, header and not line.collapsed, 1, 0, 0, 300
  end)
end

function ProfessionsClassic.install(state)
  state = state or {}
  state.skillLines = state.skillLines or {}
  if state.slots then
    ProfessionsRetail.installSlots(state)
  else
    installSkillLines(state)
  end
  ProfessionsRetail.installItems(state)
  return state
end

return ProfessionsClassic
