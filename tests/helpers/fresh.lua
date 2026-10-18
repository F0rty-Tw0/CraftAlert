-- Loads a module as if for the first time, so each test sees the stubs of its own setup.
--   local FlavorCompat = Fresh.require("Core.FlavorCompat")
local Fresh = {}

function Fresh.require(path)
  package.loaded[path] = nil
  package.loaded["CraftAlert." .. path] = nil
  return require("CraftAlert." .. path)
end

return Fresh
