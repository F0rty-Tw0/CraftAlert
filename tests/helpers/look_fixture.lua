local LookFixture = {}

LookFixture.KEYS = {
  "bg_primary",
  "bg_secondary",
  "bg_header",
  "bg_input",
  "divider",
  "contacts_divider",
  "bg_contact_selected",
  "bg_contact_hover",
  "scrollbar",
  "scrollbar_hover",
}

-- A GetLook answer by the spec contract; every key a distinct colour, so a test sees which one was used.
function LookFixture.answer(hud)
  local colors = {}
  for i, key in ipairs(LookFixture.KEYS) do
    colors[key] = { i / 10, 0.2, 0.4, 0.5 + i / 20 }
  end
  return { hud = hud, colors = colors }
end

LookFixture.COLORS = LookFixture.answer("off").colors
LookFixture.NATIVE = { mode = "native" }

function LookFixture.flat()
  return { mode = "flat", colors = LookFixture.answer("off").colors }
end

-- Wraps module[name](target, look): records { target, look }, then runs the real one. -> the list
function LookFixture.spy(module, name)
  local seen = {}
  local real = module[name]
  module[name] = function(target, look, ...)
    seen[#seen + 1] = { target, look }
    return real(target, look, ...)
  end
  return seen
end

-- True when the spy recorded exactly this target and look.
function LookFixture.saw(seen, target, look)
  for _, call in ipairs(seen) do
    if call[1] == target and call[2] == look then
      return true
    end
  end
  return false
end

return LookFixture
