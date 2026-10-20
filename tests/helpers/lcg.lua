-- Deterministic random numbers for seeded tests: the same sequence under every runtime.
--   local rand, pick = require("tests.helpers.lcg")(1)
--   rand(1, 6)     -- integer in 1..6
--   pick(list)     -- a random element
return function(seed)
  local state = seed
  local function rand(lo, hi)
    -- Park-Miller: the product stays below 2^53, so doubles compute it exactly everywhere,
    -- and a prime modulus keeps the low bits as random as the high ones.
    state = state * 16807 % 2147483647
    return lo + state % (hi - lo + 1)
  end
  local function pick(list)
    return list[rand(1, #list)]
  end
  return rand, pick
end
