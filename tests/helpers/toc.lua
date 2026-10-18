-- Reads CraftAlert.toc: the ordered list of files the client loads.
local Toc = {}

local TOC_PATH = "CraftAlert.toc"

-- Returns the load-order list of entries (paths as written, forward slashes).
-- root: repo root when not running from it (tools/sim.lua); default is the current directory.
function Toc.entries(root)
  local entries = {}
  local path = root and (root .. "/" .. TOC_PATH) or TOC_PATH
  for line in io.lines(path) do
    line = string.gsub(line, "^%s+", "")
    line = string.gsub(line, "%s+$", "")
    if line ~= "" and string.sub(line, 1, 1) ~= "#" then
      entries[#entries + 1] = line
    end
  end
  return entries
end

-- Only the .lua entries (the client loads Bindings.xml itself; the TOC may omit it).
function Toc.luaFiles(root)
  local files = {}
  for _, entry in ipairs(Toc.entries(root)) do
    if string.match(entry, "%.lua$") then
      files[#files + 1] = entry
    end
  end
  return files
end

return Toc
