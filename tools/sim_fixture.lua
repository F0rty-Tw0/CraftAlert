-- Synthetic CraftAlertDB for tools/sim.lua: two Retail characters on the player's realm.
-- Both know a plate belt (item), an itemless enchant, and a reagent with bind 0.
local function crafter(professions)
  return {
    source = "local",
    enabled = true,
    realms = { "OwnRealm" },
    professions = professions,
    recipes = {
      [9001] = { item = 190001, name = "Sim Plate Belt", prof = 164, bind = 2 },
      [9002] = { name = "Enchant Bracer - Sim Health", prof = 333 },
      [9003] = { item = 190003, name = "Sim Iron Reagent", prof = 164, bind = 0 },
    },
  }
end

return {
  schema = 1,
  settings = {},
  characters = {
    ["Crafter-OwnRealm"] = crafter({
      [164] = { name = "Blacksmithing", primary = true, read = true },
      [333] = { name = "Enchanting", primary = true, read = true },
    }),
    ["Alt-OwnRealm"] = crafter({
      [164] = { name = "Blacksmithing", primary = false, read = true },
      [333] = { name = "Enchanting", primary = false, read = true },
    }),
  },
  leads = {},
  ledger = {},
  recentGreeted = {},
  ignored = {},
  ui = {},
}
