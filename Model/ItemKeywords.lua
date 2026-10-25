local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Slang = ns.Slang or require("CraftAlert.Model.Slang")

-- Spec §6.4: the words a player may use for an item, from its equip location, class and
-- subclass. Runs at index build only (once per recipe), never per chat line, so it may
-- allocate and call the item API. Settings are not read here: the caller passes extraSlang.
local ItemKeywords = {}

local ipairs = ipairs
local pairs = pairs
local sort = table.sort
local lower = string.lower

local function addAll(words, seen, source)
  if not source then
    return
  end
  for _, word in ipairs(source) do
    if not seen[word] then
      seen[word] = true
      words[#words + 1] = word
    end
  end
end

-- extraSlang is { playerWord = "slot or type word" }: an item that has the target word
-- also answers to the player's word. Matched against the base words only, added in sorted
-- order so the index does not depend on pairs() order.
local function addExtras(words, seen, extraSlang)
  local extras = {}
  for extra, target in pairs(extraSlang) do
    extra, target = lower(extra), lower(target)
    if extra ~= "" and seen[target] and not seen[extra] then
      extras[#extras + 1] = extra
    end
  end
  sort(extras)
  for _, extra in ipairs(extras) do
    seen[extra] = true
    words[#words + 1] = extra
  end
end

-- The equip locations of items nobody wears: Classic "", retail "INVTYPE_NON_EQUIP_IGNORE"
-- (named "INVTYPE_NON_EQUIP" before 10.2.6).
local NOT_WORN = { [""] = true, INVTYPE_NON_EQUIP = true, INVTYPE_NON_EQUIP_IGNORE = true }

-- → a new array of lowercase words (slot words, then type words, then extras), empty when the
-- item is unknown or the item API is missing; and whether the item is worn (it has an equip
-- location, profession gear and trinkets too, whose slots have no words).
function ItemKeywords.WordsFor(itemID, extraSlang)
  local words, seen = {}, {}
  if itemID == nil then
    return words, false
  end
  local _, _, _, equipLoc, _, classID, subclassID = FlavorCompat.GetItemInfoInstant(itemID)
  local worn = equipLoc ~= nil and not NOT_WORN[equipLoc]
  addAll(words, seen, Slang.slots[equipLoc])
  if classID == Slang.CLASS_ARMOR then
    addAll(words, seen, Slang.armor[subclassID])
  elseif classID == Slang.CLASS_WEAPON then
    addAll(words, seen, Slang.weapons[subclassID])
  elseif classID == Slang.CLASS_CONTAINER then
    addAll(words, seen, Slang.containers)
  end
  if extraSlang then
    addExtras(words, seen, extraSlang)
  end
  return words, worn
end

-- → a new table: Slang.armorTags plus each extra slang word whose target has a tag, with that
-- tag. A static word keeps its own tag. Build time only.
function ItemKeywords.ArmorTags(extraSlang)
  local tags = {}
  for word, tag in pairs(Slang.armorTags) do
    tags[word] = tag
  end
  for extra, target in pairs(extraSlang or {}) do
    extra, target = lower(extra), lower(target)
    if extra ~= "" and Slang.armorTags[target] and not Slang.armorTags[extra] then
      tags[extra] = Slang.armorTags[target]
    end
  end
  return tags
end

ns.ItemKeywords = ItemKeywords
return ItemKeywords
