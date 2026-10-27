-- Synthetic CraftAlertDB of a second account for the sim's --import proof: the player
-- (Crafter-OwnRealm) enchants only, so a plate belt request has no crafter until the first
-- account's export string (tools/sim_fixture.lua) brings Alt-OwnRealm in.
return {
  schema = 1,
  settings = {},
  characters = {
    ["Crafter-OwnRealm"] = {
      source = "local",
      enabled = true,
      realms = { "OwnRealm" },
      professions = { [333] = { name = "Enchanting", primary = true, read = true } },
      recipes = {
        [9002] = { name = "Enchant Bracer - Sim Health", prof = 333 },
      },
    },
  },
  leads = {},
  ledger = {},
  recentGreeted = {},
  ui = {},
}
