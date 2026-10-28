local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Constants = ns.Constants or require("CraftAlert.Core.Constants")
local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Index = ns.Index or require("CraftAlert.Model.Index")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local Controls = ns.SettingsControls or require("CraftAlert.UI.Settings.Controls")

-- Spec §9 Keywords: intent words, blocker words and extra slang (word → slot/type). Every
-- change rebuilds the index, which holds the word sets (§6.2).
local PageKeywords = { id = "keywords", title = Localization.Text("Keywords") }

local gmatch = string.gmatch
local lower = string.lower
local match = string.match

local function db()
  return _G["CraftAlertDB"]
end

-- Lowercase words split on spaces and commas, each once, in typed order.
local function splitWords(text)
  local words, seen = {}, {}
  for word in gmatch(lower(text), "[^%s,]+") do
    if not seen[word] then
      seen[word] = true
      words[#words + 1] = word
    end
  end
  return words
end

local function copy(list)
  local result = {}
  for i, value in ipairs(list) do
    result[i] = value
  end
  return result
end

-- "word=target" pairs; a part without both sides is dropped.
local function parseSlang(text)
  local slang = {}
  for _, part in ipairs(splitWords(text)) do
    local word, target = match(part, "^([^=]+)=([^=]+)$")
    if word then
      slang[word] = target
    end
  end
  return slang
end

local function sortedKeys(map)
  local keys = {}
  for key in pairs(map) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

local function formatSlang(slang)
  local parts = {}
  for _, word in ipairs(sortedKeys(slang)) do
    parts[#parts + 1] = word .. "=" .. slang[word]
  end
  return table.concat(parts, " ")
end

local function wordsInput(column, add, label, key, fallback, tip)
  local input
  input = Controls.Input(column, Localization.Text(label), function(text)
    local words = splitWords(text)
    if #words == 0 and fallback then
      words = copy(fallback)
    end
    db().settings[key] = words
    input.Set(table.concat(words, " "))
    Index.RequestRebuild("keywords")
  end, nil, Localization.Text(tip))
  add(function()
    local words = db().settings[key]
    input.Set(type(words) == "table" and table.concat(words, " ") or "")
  end)
end

local function slangInput(column, add)
  local input
  input = Controls.Input(column, Localization.Text("Extra slang (word=slot)"), function(text)
    db().settings.extraSlang = parseSlang(text)
    input.Set(formatSlang(db().settings.extraSlang))
    Index.RequestRebuild("keywords")
  end, nil, Localization.Text("Teach Craft Alert a word it does not know. Each word=target pair makes your word mean that slot or armor type."))
  add(function()
    input.Set(formatSlang(db().settings.extraSlang))
  end)
end

function PageKeywords.Create(parent)
  local column = Controls.Column(parent, Theme.LAYOUT.PAGE_PADDING)
  local add, refresh = Controls.Refresher()
  Controls.Section(column, Localization.Text("Request words"))
  local intentTip = "Words that mark a request, such as lf or wtb. A line needs one of them to count as a request. Emptied, the default list returns."
  wordsInput(column, add, "Intent words", "intentWords", Constants.intentWords, intentTip)
  local blockerTip = "Words that cancel a match, such as wts. A line with one of them never alerts."
  wordsInput(column, add, "Blocker words", "blockerWords", nil, blockerTip)
  slangInput(column, add)
  return { Refresh = refresh }
end

ns.PageKeywords = PageKeywords
return PageKeywords
