local Assert = require("tests.helpers.assert")
local LookFixture = require("tests.helpers.look_fixture")

-- The looks the Phase 2 painter tests apply, and the spec's "Looks" values for the row overlays.
local PainterLooks = {}

PainterLooks.COLORS = LookFixture.answer("off").colors
PainterLooks.SEQUENCE = { "native", "retail", "classic", "flat", "native" }

function PainterLooks.look(mode)
  local PanelLook = require("CraftAlert.UI.PanelLook")
  if mode == "native" then
    return PanelLook.NATIVE
  end
  return { mode = mode, colors = PainterLooks.COLORS }
end

local WHITE = { 1, 1, 1 }

local function rgb(color)
  return { color[1], color[2], color[3] }
end

-- Selected and hover overlay per look. `nativeTint`: a lead row's Theme.COLORS.selectedTint, nil for a nav button.
function PainterLooks.overlays(Theme, nativeTint)
  local art, colors = Theme.ART, PainterLooks.COLORS
  local selected, hover = colors.bg_contact_selected, colors.bg_contact_hover
  local function texture(path, tint, alpha)
    return { art = path, blend = "ADD", tint = tint, alpha = alpha }
  end
  local function fill(color)
    return { color = color, blend = "BLEND", tint = WHITE, alpha = 1 }
  end
  return {
    selected = {
      native = texture(art.LIST_SELECTED, nativeTint or WHITE, 0.45),
      retail = texture(art.LIST_SELECTED, rgb(selected), 0.45),
      classic = texture(art.LIST_SELECTED, rgb(selected), 0.45),
      flat = fill(selected),
    },
    hover = {
      native = texture(art.LIST_HOVER, WHITE, 0.18),
      retail = texture(art.LIST_HOVER, rgb(hover), 0.18),
      classic = texture(art.LIST_HOVER, rgb(hover), 0.18),
      flat = fill(hover),
    },
  }
end

function PainterLooks.checkOverlay(texture, want, label)
  Assert.same({ texture.blendMode, texture.vertexColor }, { want.blend, want.tint }, label .. ": blend, tint")
  if want.color then
    Assert.same(texture.color, want.color, label .. ": flat colour")
  else
    Assert.equal(texture.texture, want.art, label .. ": art")
  end
end

return PainterLooks
