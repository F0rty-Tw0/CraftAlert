-- Every addon .lua file must be listed in CraftAlert.toc, and every TOC entry must exist.
local Toc = require("tests.helpers.toc")

local ADDON_DIRS = { "Core", "Model", "Professions", "Persistence", "UI" }
local IS_WINDOWS = string.sub(package.config, 1, 1) == "\\"

local function readLines(command)
  local pipe = assert(io.popen(command))
  local lines = {}
  for line in pipe:lines() do
    line = string.gsub(line, "\r$", "")
    if line ~= "" then
      lines[#lines + 1] = line
    end
  end
  pipe:close()
  return lines
end

-- Lua files under dir as forward-slash paths relative to the repo root.
local function listLua(dir)
  if not IS_WINDOWS then
    return readLines("find " .. dir .. " -type f -name '*.lua' 2>/dev/null")
  end
  local root = readLines("cd")[1]
  local found = {}
  -- Unquoted on purpose: cmd.exe /c mangles a command holding several quotes.
  for _, absolute in ipairs(readLines("dir /b /s " .. dir .. "\\*.lua 2>nul")) do
    local relative = string.sub(absolute, #root + 2)
    found[#found + 1] = (string.gsub(relative, "\\", "/"))
  end
  return found
end

local function isFolderModuleStub(path)
  return string.match(path, "/init%.lua$") ~= nil
end

return function()
  local listed = {}
  for _, path in ipairs(Toc.luaFiles()) do
    listed[path] = true
    local handle = io.open(path, "r")
    assert(handle, "CraftAlert.toc lists a missing file: " .. path)
    handle:close()
  end

  -- A failed listing command returns nothing, which would pass vacuously.
  assert(#listLua("Core") > 0, "listing found no Lua files under Core")
  for _, dir in ipairs(ADDON_DIRS) do
    for _, path in ipairs(listLua(dir)) do
      if not isFolderModuleStub(path) then
        assert(listed[path], path .. " is not listed in CraftAlert.toc")
      end
    end
  end
end
