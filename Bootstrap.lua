local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- Single owner of cross-module wiring. Empty until Task 1.19.
local Bootstrap = {}

function Bootstrap.Install()
  return {}
end

ns.Bootstrap = Bootstrap
return Bootstrap
