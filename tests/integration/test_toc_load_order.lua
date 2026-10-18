-- The live client exposes a global `require` that throws for unknown modules,
-- so every file's `ns.X or require(...)` fallback must never be reached:
-- each dependency has to load earlier in the TOC.
local Wow = require("tests.helpers.wow")
local Toc = require("tests.helpers.toc")

return function()
  Wow.reset()

  local files = Toc.luaFiles()
  assert(#files > 0, "CraftAlert.toc lists no .lua files")
  assert(files[#files] == "Bootstrap.lua", "Bootstrap.lua must be the last file, got " .. tostring(files[#files]))

  local savedRequire = require
  _G.require = function(moduleName)
    error("Invalid import: No module with that name exists (" .. tostring(moduleName) .. ")")
  end

  local ns = {}
  local ok, err = pcall(function()
    for _, path in ipairs(files) do
      local chunk = assert(loadfile(path))
      local loaded, loadErr = pcall(chunk, "CraftAlert", ns)
      assert(loaded, path .. ": " .. tostring(loadErr))
    end
  end)

  _G.require = savedRequire
  Wow.reset()

  assert(ok, tostring(err))
end
