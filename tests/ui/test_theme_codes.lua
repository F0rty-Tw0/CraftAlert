local Assert = require("tests.helpers.assert")

-- Global Constraint: no hand-typed colour codes in new or touched code; codes come from Theme.COLORS.
local function source(path)
  local handle = assert(io.open(path, "r"))
  local text = handle:read("*a")
  handle:close()
  return text
end

return function()
  for _, path in ipairs({ "UI/LedgerStrip.lua", "UI/BridgeInfo.lua" }) do
    Assert.falsy(string.find(source(path), "|cff", 1, true), path .. " has a hand-typed colour code")
  end
end
