local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- Whole numbers as lowercase base-36 digits (spec §10.1: the export string's numbers). Decode
-- reads only what Encode writes, at most MAX_DIGITS digits, so a value stays exact.
local Base36 = {}

local byte = string.byte
local concat = table.concat
local floor = math.floor
local find = string.find
local sub = string.sub
local tonumber = tonumber

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

Base36.MAX_DIGITS = 7

-- n: a whole number ≥ 0.
function Base36.Encode(n)
  if n == 0 then
    return "0"
  end
  local digits = {}
  while n > 0 do
    local digit = n % 36
    digits[#digits + 1] = sub(DIGITS, digit + 1, digit + 1)
    n = floor(n / 36)
  end
  -- Reversed in place: the last digit found is the most significant.
  local count = #digits
  for i = 1, floor(count / 2) do
    digits[i], digits[count + 1 - i] = digits[count + 1 - i], digits[i]
  end
  return concat(digits)
end

-- → the number, or nil for anything Encode would not write (empty, upper case, a sign, a
-- space, more than MAX_DIGITS digits). A leading zero is refused too: one number, one spelling.
function Base36.Decode(text)
  if type(text) ~= "string" or #text == 0 or #text > Base36.MAX_DIGITS or find(text, "[^0-9a-z]") then
    return nil
  end
  if #text > 1 and byte(text, 1) == 48 then
    return nil
  end
  return tonumber(text, 36)
end

ns.Base36 = Base36
return Base36
