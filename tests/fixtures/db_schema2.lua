-- Hand-edited CraftAlertDB from a newer Craft Alert (Review Focus 5): schema = 2, strings
-- where numbers belong, one field this version does not know, and 5,000 leads.
-- Lead times 1..5000 sit on the sim's clock of 0, so none is expired; the cap keeps 100.
local leads = {}
for i = 1, 5000 do
  leads[i] = { id = i, customer = "Customer" .. i .. "-OtherRealm", message = "LF plate belt", time = i }
end

return {
  schema = 2,
  settings = { toastDuration = "30", leadTimeoutMin = "60", futureSetting = true },
  characters = {
    ["Crafter-OwnRealm"] = {
      source = "local",
      enabled = true,
      realms = { "OwnRealm" },
      futureField = "kept",
      professions = { [164] = { name = "Blacksmithing", primary = true, read = true } },
      recipes = {
        [9001] = { item = 190001, name = "Sim Plate Belt", prof = 164, bind = 2, muted = true },
        [9002] = { item = "190002", name = "Sim Plate Boots", prof = 164 },
      },
    },
  },
  leads = leads,
  ledger = {},
  recentGreeted = {},
  ignored = {},
  ui = {},
}
