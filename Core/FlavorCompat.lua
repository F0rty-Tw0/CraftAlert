local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- Which client is running, plus thin wrappers over APIs that differ per flavor.
-- Flags are mutually exclusive: Forever is neither isRetail nor isClassic, so code that
-- serves both modern clients writes `isRetail or isForever`. Wrappers pick the namespaced
-- API when it exists at call time (never assumed from the flavor).
local FlavorCompat = {}

local FOREVER_TOC_MIN = 16000
local FOREVER_TOC_MAX = 17000

-- WOW_PROJECT_ID -> flavorKey for the five classic clients.
local CLASSIC_PROJECTS = {
  { constant = "WOW_PROJECT_CLASSIC", key = "era" },
  { constant = "WOW_PROJECT_BURNING_CRUSADE_CLASSIC", key = "tbc" },
  { constant = "WOW_PROJECT_WRATH_CLASSIC", key = "wrath" },
  { constant = "WOW_PROJECT_CATACLYSM_CLASSIC", key = "cata" },
  { constant = "WOW_PROJECT_MISTS_CLASSIC", key = "mop" },
}

local CRAFT_FRAME_FLAVORS = { era = true, tbc = true }

local function tocVersion()
  local getBuildInfo = _G["GetBuildInfo"]
  if type(getBuildInfo) ~= "function" then
    return nil
  end
  return (select(4, getBuildInfo()))
end

-- WOW_PROJECT_CAMELOT exists only on Forever and equals WOW_PROJECT_ID there (Phase 0);
-- the TOC range is the fallback WhisperMessenger uses.
local function detectForever(projectId)
  local camelot = _G["WOW_PROJECT_CAMELOT"]
  if camelot ~= nil and camelot == projectId then
    return true
  end
  local toc = tocVersion()
  return type(toc) == "number" and toc >= FOREVER_TOC_MIN and toc < FOREVER_TOC_MAX
end

local function detectClassicKey(projectId)
  for _, project in ipairs(CLASSIC_PROJECTS) do
    local id = _G[project.constant]
    if id ~= nil and id == projectId then
      return project.key
    end
  end
  return nil
end

local function detectFlavorKey()
  local projectId = _G["WOW_PROJECT_ID"]
  if detectForever(projectId) then
    return "forever"
  end
  -- Unknown project ids (the bare test harness) count as Retail.
  return detectClassicKey(projectId) or "retail"
end

FlavorCompat.flavorKey = detectFlavorKey()
FlavorCompat.isRetail = FlavorCompat.flavorKey == "retail"
FlavorCompat.isForever = FlavorCompat.flavorKey == "forever"
FlavorCompat.isClassic = not FlavorCompat.isRetail and not FlavorCompat.isForever
FlavorCompat.hasCraftFrame = CRAFT_FRAME_FLAVORS[FlavorCompat.flavorKey] == true and type(_G["GetCraftDisplaySkillLine"]) == "function"

-- Calls namespace.name if it is a function, else the global of the same name.
local function callPreferred(namespaceName, name, ...)
  local namespace = _G[namespaceName]
  if type(namespace) == "table" and type(namespace[name]) == "function" then
    return namespace[name](...)
  end
  local fallback = _G[name]
  if type(fallback) == "function" then
    return fallback(...)
  end
  return nil
end

function FlavorCompat.GetItemInfoInstant(itemId)
  return callPreferred("C_Item", "GetItemInfoInstant", itemId)
end

function FlavorCompat.GetItemInfo(itemId)
  return callPreferred("C_Item", "GetItemInfo", itemId)
end

function FlavorCompat.SendChatMessage(message, chatType, language, target)
  return callPreferred("C_ChatInfo", "SendChatMessage", message, chatType, language, target)
end

function FlavorCompat.GetAutoCompleteRealms()
  return callPreferred("C_AutoComplete", "GetAutoCompleteRealms")
end

-- ChatFrameUtil is present on every flavor; returns false when it is missing.
local function callChatFrameUtil(name, ...)
  local util = _G["ChatFrameUtil"]
  if type(util) ~= "table" or type(util[name]) ~= "function" then
    return false
  end
  util[name](...)
  return true
end

function FlavorCompat.SendTellWithMessage(name, message)
  return callChatFrameUtil("SendTellWithMessage", name, message)
end

function FlavorCompat.SendTell(name)
  return callChatFrameUtil("SendTell", name)
end

-- Bound once at load: the hot path calls it on every chat line.
local function neverSecret(_)
  return false
end

local issecretvalue = _G["issecretvalue"]
FlavorCompat.issecretvalue = type(issecretvalue) == "function" and issecretvalue or neverSecret

ns.FlavorCompat = FlavorCompat
return FlavorCompat
