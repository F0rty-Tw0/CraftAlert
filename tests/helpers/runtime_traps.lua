-- Stubs that trap what spec §4.3 forbids, for tests/integration/test_runtime_rules.lua:
--   RuntimeTraps.install(opts) -> restore()
--     opts.isScanActive   fn -> bool; public chat events may be registered only while true
--     opts.blizzard       names of Blizzard globals to put behind a proxy; default BLIZZARD_GLOBALS
--   Blizzard tables become empty proxies: reads fall through to the real stub, every write
--   raises (only SlashCmdList.CRAFTALERT is allowed), so overwriting an existing field traps
--   too. Methods run on the real table, so stub frames keep their own state.
--   _G rejects new globals outside the own-globals list; CreateFrame rejects frame names outside
--   it; frames reject an OnUpdate script and public chat events while the scan is inactive.
-- Stubs the test installs with Wow.stub (rawset) before install() are never trapped on creation.
local Wow = require("tests.helpers.wow")

local RuntimeTraps = {}

-- Spec §4.3 rule 3: the only global names the addon may create. Frame names and the
-- CraftAlert_* functions share the CraftAlert prefix.
local OWN_GLOBALS = {
  SlashCmdList = true,
  SLASH_CRAFTALERT1 = true,
  SLASH_CRAFTALERT2 = true,
  BINDING_HEADER_CRAFTALERT = true,
  BINDING_NAME_CRAFTALERT_GREET = true,
  BINDING_NAME_CRAFTALERT_DISMISS = true,
  BINDING_NAME_CRAFTALERT_TOGGLE = true,
}
local OWN_PREFIX = "^CraftAlert"

-- Fields the addon may write on a Blizzard table, by global name (rule 3).
local ALLOWED_FIELDS = { SlashCmdList = { CRAFTALERT = true } }

RuntimeTraps.BLIZZARD_GLOBALS = {
  "UIParent",
  "GameTooltip",
  "ProfessionsFrame",
  "ChatFrameUtil",
  "C_Timer",
  "C_ChatInfo",
  "C_Item",
  "C_TradeSkillUI",
  "C_FriendList",
  "C_AutoComplete",
  "SlashCmdList",
  "UISpecialFrames",
  "Settings",
  "DEFAULT_CHAT_FRAME",
}

-- Rule 4: the events a frame may register while the scan is inactive.
local PUBLIC_CHAT_EXCEPTIONS = { CHAT_MSG_WHISPER = true, CHAT_MSG_WHISPER_INFORM = true, CHAT_MSG_SYSTEM = true }

local function isOwnGlobal(name)
  return OWN_GLOBALS[name] == true or (type(name) == "string" and string.find(name, OWN_PREFIX) ~= nil)
end

-- An empty table whose reads fall through to `real` and whose writes raise.
function RuntimeTraps.proxy(real, name, allowedFields)
  local proxy
  local children, wrappers = {}, {}
  proxy = setmetatable({}, {
    __index = function(_, key)
      local value = real[key]
      if type(value) == "table" then
        children[value] = children[value] or RuntimeTraps.proxy(value, name .. "." .. tostring(key))
        return children[value]
      end
      if type(value) == "function" then
        wrappers[value] = wrappers[value]
          or function(first, ...)
            if first == proxy then
              first = real
            end
            return value(first, ...)
          end
        return wrappers[value]
      end
      return value
    end,
    __newindex = function(_, key, value)
      if allowedFields and allowedFields[key] then
        real[key] = value
        return
      end
      error(string.format("write to Blizzard table %s.%s", name, tostring(key)), 2)
    end,
  })
  return proxy
end

local function guardFrame(frame, isScanActive)
  local setScript, hookScript, registerEvent = frame.SetScript, frame.HookScript, frame.RegisterEvent
  function frame:SetScript(scriptName, fn)
    if scriptName == "OnUpdate" then
      error('SetScript("OnUpdate"): rule 1 forbids OnUpdate', 2)
    end
    return setScript(self, scriptName, fn)
  end
  function frame:HookScript(scriptName, fn)
    if scriptName == "OnUpdate" then
      error('HookScript("OnUpdate"): rule 1 forbids OnUpdate', 2)
    end
    return hookScript(self, scriptName, fn)
  end
  function frame:RegisterEvent(event)
    if string.find(event, "^CHAT_MSG_") and not PUBLIC_CHAT_EXCEPTIONS[event] and not isScanActive() then
      error("public chat event " .. event .. " registered while the scan is inactive (rule 4)", 2)
    end
    return registerEvent(self, event)
  end
  return frame
end

local function guardCreateFrame(isScanActive)
  local create = rawget(_G, "CreateFrame")
  Wow.stub("CreateFrame", function(frameType, name, ...)
    if name ~= nil and not isOwnGlobal(name) then
      error("frame name " .. tostring(name) .. " is not one of ours (rule 3)", 2)
    end
    return guardFrame(create(frameType, name, ...), isScanActive)
  end)
end

local function guardGlobals()
  local previous = getmetatable(_G)
  setmetatable(_G, {
    __newindex = function(globals, name, value)
      if not isOwnGlobal(name) then
        error("write to global " .. tostring(name) .. " (rule 3)", 2)
      end
      rawset(globals, name, value)
    end,
  })
  return function()
    setmetatable(_G, previous)
  end
end

function RuntimeTraps.install(opts)
  local names = opts.blizzard or RuntimeTraps.BLIZZARD_GLOBALS
  for _, name in ipairs(names) do
    local real = rawget(_G, name)
    if type(real) == "table" then
      Wow.stub(name, RuntimeTraps.proxy(real, name, ALLOWED_FIELDS[name]))
    end
  end
  guardCreateFrame(opts.isScanActive)
  return guardGlobals()
end

return RuntimeTraps
