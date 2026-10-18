-- Small assertion helpers. Every failure raises at the caller's level.
local Assert = {}

local function describe(value)
  if type(value) == "string" then
    return string.format("%q", value)
  end
  return tostring(value)
end

local function deepEqual(a, b, seen)
  if a == b then
    return true
  end
  if type(a) ~= "table" or type(b) ~= "table" then
    return false
  end
  if seen[a] == b then
    return true
  end
  seen[a] = b
  for key, value in pairs(a) do
    if not deepEqual(value, b[key], seen) then
      return false
    end
  end
  for key in pairs(b) do
    if a[key] == nil then
      return false
    end
  end
  return true
end

function Assert.equal(actual, expected, message)
  if actual ~= expected then
    error(message or string.format("expected %s, got %s", describe(expected), describe(actual)), 2)
  end
end

function Assert.truthy(value, message)
  if not value then
    error(message or string.format("expected a truthy value, got %s", describe(value)), 2)
  end
end

function Assert.falsy(value, message)
  if value then
    error(message or string.format("expected a falsy value, got %s", describe(value)), 2)
  end
end

-- Deep structural compare of two tables (cycles tolerated).
function Assert.same(actual, expected, message)
  if not deepEqual(actual, expected, {}) then
    error(message or "tables differ", 2)
  end
end

-- fn must raise an error whose text contains `pattern` (a Lua pattern).
function Assert.raises(fn, pattern, message)
  local ok, err = pcall(fn)
  if ok then
    error(message or "expected an error, none raised", 2)
  end
  if pattern and not string.find(tostring(err), pattern) then
    error(message or string.format("expected error matching %s, got %s", describe(pattern), describe(err)), 2)
  end
end

return Assert
