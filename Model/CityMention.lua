local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Tokenizer = ns.Tokenizer or require("CraftAlert.Model.Tokenizer")

-- Other-capital filter spec §3-§4 (Forever + Classic): which capital the player stands in
-- (ForMap) and whether the last tokenized line names only other capitals (OnlyOther). Reads the
-- Tokenizer buffers the Matcher just filled; creates no table or closure per line.
-- Short names count only right after a cue word ("in org", no punctuation between, per
-- .claude/rules/matcher-adjacent-words.md) or after a lone "@" ("@SW"): if, darn, sw, tb and org
-- are everyday chat words or abbreviations ("if anyone can", "darn"), so a bare short name would
-- hide real requests (R6). Full names count anywhere, and so does the player's own capital's
-- short name (R3): a doubtful own mention keeps the line, never hides it.
local CityMention = {}

local strLower = string.lower
local type = type
local tokens, BreakBefore, AtBefore = Tokenizer.tokens, Tokenizer.BreakBefore, Tokenizer.AtBefore

-- Spec §4. A missing map ID means "not in a capital", so a wrong ID only disables the filter.
local FULL = {
  stormwind = "stormwind",
  ironforge = "ironforge",
  darnassus = "darnassus",
  exodar = "exodar",
  orgrimmar = "orgrimmar",
  orgrimar = "orgrimmar",
  orgri = "orgrimmar",
  undercity = "undercity",
  thunderbluff = "thunderbluff",
  silvermoon = "silvermoon",
}

local SHORT = {
  sw = "stormwind",
  ["if"] = "ironforge",
  darn = "darnassus",
  exo = "exodar",
  org = "orgrimmar",
  og = "orgrimmar",
  uc = "undercity",
  tb = "thunderbluff",
  smc = "silvermoon",
}

local CUES = { ["in"] = true, at = true, to = true, from = true, near = true }

local MAPS = {
  [1453] = "stormwind",
  [84] = "stormwind",
  [1455] = "ironforge",
  [87] = "ironforge",
  [1457] = "darnassus",
  [89] = "darnassus",
  [1947] = "exodar",
  [103] = "exodar",
  [1454] = "orgrimmar",
  [85] = "orgrimmar",
  [1458] = "undercity",
  [90] = "undercity",
  [1456] = "thunderbluff",
  [88] = "thunderbluff",
  [1954] = "silvermoon",
  [110] = "silvermoon",
}

-- GetWhoInfo's `area` (English), lowercased.
local ZONES = {
  ["stormwind city"] = "stormwind",
  ironforge = "ironforge",
  darnassus = "darnassus",
  ["the exodar"] = "exodar",
  orgrimmar = "orgrimmar",
  undercity = "undercity",
  ["thunder bluff"] = "thunderbluff",
  ["silvermoon city"] = "silvermoon",
}

-- The capital key for a uiMapID, or nil.
function CityMention.ForMap(uiMapID)
  return uiMapID ~= nil and MAPS[uiMapID] or nil
end

-- The capital key for a /who zone name (any case), or nil.
function CityMention.ForZoneName(name)
  return type(name) == "string" and ZONES[strLower(name)] or nil
end

-- The capital token k names (R2), or nil. The player's own capital's short name needs no cue
-- (R3, decision 2026-11-06): "in org or uc" while in Undercity is kept, and a doubtful own
-- mention only ever keeps a line.
local function capitalAt(k, ownKey)
  local token = tokens[k]
  local key = FULL[token]
  if key then
    return key
  end
  if token == "thunder" and tokens[k + 1] == "bluff" and not BreakBefore(k + 1) then
    return "thunderbluff"
  end
  key = SHORT[token]
  if key and (key == ownKey or (k > 1 and CUES[tokens[k - 1]] and not BreakBefore(k)) or AtBefore(k)) then
    return key
  end
  return nil
end

-- R3: whether the last tokenized line names at least one capital and none equal to ownKey.
function CityMention.OnlyOther(ownKey)
  local other = false
  for k = 1, Tokenizer.tokenCount do
    local key = capitalAt(k, ownKey)
    if key then
      if key == ownKey then
        return false
      end
      other = true
    end
  end
  return other
end

ns.CityMention = CityMention
return CityMention
