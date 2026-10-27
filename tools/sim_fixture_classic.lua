-- Synthetic CraftAlertDB for tools/sim.lua on Classic flavors: tools/sim_fixture.lua with the
-- Classic keys (spec §5.1, §5.2): professions by lowercase name, recipes by lowercase recipe name.
local function crafter(professions)
  return {
    source = "local",
    enabled = true,
    realms = { "OwnRealm" },
    professions = professions,
    recipes = {
      ["sim plate belt"] = { item = 190001, name = "Sim Plate Belt", prof = "blacksmithing", bind = 2 },
      ["enchant bracer - sim health"] = { name = "Enchant Bracer - Sim Health", prof = "enchanting" },
      ["sim iron reagent"] = { item = 190003, name = "Sim Iron Reagent", prof = "blacksmithing", bind = 0 },
    },
  }
end

return {
  schema = 1,
  settings = {},
  characters = {
    ["Crafter-OwnRealm"] = crafter({
      blacksmithing = { name = "Blacksmithing", primary = true, read = true },
      enchanting = { name = "Enchanting", primary = true, read = true },
    }),
    ["Alt-OwnRealm"] = crafter({
      blacksmithing = { name = "Blacksmithing", primary = false, read = true },
      enchanting = { name = "Enchanting", primary = false, read = true },
    }),
  },
  leads = {},
  ledger = {},
  recentGreeted = {},
  ui = {},
}
