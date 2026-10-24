-- .luacheckrc for CraftAlert (WoW addon, all seven flavors)
-- Targets Lua 5.1 (WoW runtime)

std = "lua51"
max_line_length = false -- StyLua handles formatting; luacheck handles semantics
cache = true
jobs = 4

-- Exclude vendored/generated/test-infra files
exclude_files = {
  "Libs/",
  "libs/",
  "tools/",
  ".luacheckrc",
}

-- Warnings to suppress for common WoW addon patterns
ignore = {
  "11./BINDING_.*", -- keybinding globals are expected
  "11./SLASH_.*", -- slash command globals are expected
  "212/self", -- unused 'self' in method definitions
  "212/event", -- unused 'event' in OnEvent handlers
  "211/addonName", -- unused first return from `local addonName, ns = ...`
  "212/addonName", -- same when treated as argument
  "331/ns", -- ns is set (mutated) then exported, not read directly
  "122/_G", -- writing SavedVariables via _G.VarName is intentional
  "143/table", -- table.unpack exists in Lua 5.2+; WoW provides compat
}

-- Globals the addon WRITES (spec 4.3 rule 3: own names only)
globals = {
  -- SavedVariables (declared in .toc)
  "CraftAlertDB",

  -- Slash command registration (Blizzard pattern)
  "SlashCmdList",
  "SLASH_CRAFTALERT1",
  "SLASH_CRAFTALERT2",

  -- Keybinding handlers (called from Bindings.xml)
  "CraftAlert_GreetLatest",
  "CraftAlert_DismissLatest",
  "CraftAlert_ToggleLeads",

  -- Keybinding labels
  "BINDING_HEADER_CRAFTALERT",
  "BINDING_NAME_CRAFTALERT_GREET",
  "BINDING_NAME_CRAFTALERT_DISMISS",
  "BINDING_NAME_CRAFTALERT_TOGGLE",
}

-- Globals the addon READS (WoW API surface used by this addon)
read_globals = {
  -- Lua 5.1 extras provided by WoW
  "wipe",
  "tinsert",
  "tremove",
  "strjoin",
  "strsplit",
  "strtrim",
  "format",
  "date",
  "time",
  "unpack",
  "debugprofilestop",

  -- Frames and UI
  "CreateFrame",
  "UIParent",
  "UISpecialFrames",
  "DEFAULT_CHAT_FRAME",
  "Settings",
  "ScrollUtil",
  "FlashClientIcon",
  "PlaySound",

  -- Namespaced C_ APIs
  "C_ChatInfo",
  "C_Timer",
  "C_Item",
  "C_FriendList",
  "C_AutoComplete",
  "C_TradeSkillUI",
  "ChatFrameUtil",
  "Enum",

  -- Chat and items (global forms, deprecated on some flavors)
  "SendChatMessage",
  "GetItemInfo",
  "GetItemInfoInstant",
  "GetAutoCompleteRealms",
  "SendAddonMessage",
  "issecretvalue",

  -- Unit, realm and time
  "UnitName",
  "UnitFullName",
  "UnitIsAFK",
  "GetNormalizedRealmName",
  "GetRealmName",
  "GetTime",
  "GetServerTime",
  "IsResting",
  "InCombatLockdown",
  "hooksecurefunc",

  -- Crafting frames (Era/TBC Enchanting)
  "GetCraftDisplaySkillLine",

  -- Memory (`/ca perf`)
  "GetAddOnMemoryUsage",
  "UpdateAddOnMemoryUsage",

  -- Standard globals
  "_G",
  "print",

  -- Flavor detection
  "WOW_PROJECT_ID",
  "WOW_PROJECT_MAINLINE",
  "WOW_PROJECT_CLASSIC",
  "WOW_PROJECT_BURNING_CRUSADE_CLASSIC",
  "WOW_PROJECT_WRATH_CLASSIC",
  "WOW_PROJECT_CATACLYSM_CLASSIC",
  "WOW_PROJECT_MISTS_CLASSIC",
  "WOW_PROJECT_CAMELOT",
  "GetBuildInfo",
}

-- Test files: allow relaxed global access (tests stub WoW globals via _G)
files["tests/**/*.lua"] = {
  std = "+busted",
  globals = {
    "_G",
    "CreateFrame",
    "UIParent",
    "C_ChatInfo",
    "C_Timer",
    "C_Item",
    "C_FriendList",
    "SlashCmdList",
    "SLASH_CRAFTALERT1",
    "SLASH_CRAFTALERT2",
    "UnitName",
    "UnitFullName",
    "GetNormalizedRealmName",
    "GetRealmName",
    "CraftAlertDB",
    "print",
    "date",
    "time",
    "require",
  },
  ignore = {
    "111", -- setting undefined global (tests stub globals)
    "112", -- mutating undefined global
    "113", -- accessing undefined global
    "142", -- setting undefined field of global
    "143", -- accessing undefined field of global
    "211", -- unused local variable
    "212", -- unused argument
    "421", -- shadowing local variable
    "431", -- shadowing upvalue
    "432", -- shadowing upvalue argument
  },
}
