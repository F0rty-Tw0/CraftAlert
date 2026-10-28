local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- Small table helpers shared by Model, Persistence and UI. Each returns a new table the caller may
-- edit; none copies deeper than one level.
local TableKit = {}

local pairs = pairs
local sort = table.sort

-- The keys of `map`, in pairs order.
function TableKit.KeysOf(map)
  local keys = {}
  for key in pairs(map) do
    keys[#keys + 1] = key
  end
  return keys
end

-- The keys of `map`, sorted with `<` (so of one comparable type).
function TableKit.SortedKeys(map)
  local keys = TableKit.KeysOf(map)
  sort(keys)
  return keys
end

-- The array part of `list`, 1 to #list.
function TableKit.CopyList(list)
  local copy = {}
  for i = 1, #list do
    copy[i] = list[i]
  end
  return copy
end

-- Every key and value of `map`.
function TableKit.CopyMap(map)
  local copy = {}
  for key, value in pairs(map) do
    copy[key] = value
  end
  return copy
end

ns.TableKit = TableKit
return TableKit
