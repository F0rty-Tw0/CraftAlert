local Assert = require("tests.helpers.assert")
local TableKit = require("CraftAlert.Core.TableKit")

return function()
  local map = { belt = 1, helm = 2, boots = 3 }

  local keys = TableKit.KeysOf(map)
  table.sort(keys)
  Assert.same(keys, { "belt", "boots", "helm" }, "every key once")
  Assert.same(TableKit.KeysOf({}), {})

  Assert.same(TableKit.SortedKeys(map), { "belt", "boots", "helm" })
  Assert.same(TableKit.SortedKeys({ [3] = true, [1] = true, [2] = true }), { 1, 2, 3 })

  -- Copies are new tables: editing one leaves the source alone.
  local list = { "plate", "mail" }
  local listCopy = TableKit.CopyList(list)
  Assert.same(listCopy, { "plate", "mail" })
  listCopy[1] = "cloth"
  Assert.equal(list[1], "plate")

  local mapCopy = TableKit.CopyMap(map)
  Assert.same(mapCopy, map)
  mapCopy.belt = nil
  Assert.equal(map.belt, 1)
end
