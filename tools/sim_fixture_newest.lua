-- Retail --db seed for the newest-expansion default: Blacksmithing holds an older line (2540,
-- recipes 8001/8002) and a newer one (2872, recipe 9010), so a window read mutes the older line.
return {
  schema = 1,
  settings = {},
  characters = {
    ["Crafter-OwnRealm"] = {
      source = "local",
      enabled = true,
      realms = { "OwnRealm" },
      professions = {
        [164] = { name = "Blacksmithing", primary = true, read = true },
        [333] = { name = "Enchanting", primary = true, read = true },
      },
      recipes = {
        [9001] = { item = 190001, name = "Sim Plate Belt", prof = 164, bind = 2 },
        [9003] = { item = 190003, name = "Sim Iron Reagent", prof = 164, bind = 0 },
        [8001] = { item = 190101, name = "Sim Old Belt", prof = 164, bind = 2, line = 2540 },
        [8002] = { item = 190102, name = "Sim Old Helm", prof = 164, bind = 2, line = 2540 },
        [9010] = { item = 190110, name = "Sim New Belt", prof = 164, bind = 2, line = 2872 },
        [9002] = { name = "Enchant Bracer - Sim Health", prof = 333 },
      },
    },
  },
  leads = {},
  ledger = {},
  recentGreeted = {},
  ui = {},
}
