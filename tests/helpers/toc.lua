-- Reads CraftAlert.toc: the ordered list of files the client loads.
local Toc = {}

local TOC_PATH = "CraftAlert.toc"

-- Returns the load-order list of entries (paths as written, forward slashes).
function Toc.entries()
  local entries = {}
  for line in io.lines(TOC_PATH) do
    line = string.gsub(line, "^%s+", "")
    line = string.gsub(line, "%s+$", "")
    if line ~= "" and string.sub(line, 1, 1) ~= "#" then
      entries[#entries + 1] = line
    end
  end
  return entries
end

-- Only the .lua entries (the client loads Bindings.xml itself; the TOC may omit it).
function Toc.luaFiles()
  local files = {}
  for _, entry in ipairs(Toc.entries()) do
    if string.match(entry, "%.lua$") then
      files[#files + 1] = entry
    end
  end
  return files
end

return Toc
