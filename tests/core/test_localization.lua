local Assert = require("tests.helpers.assert")
local Localization = require("CraftAlert.Core.Localization")

return function()
  -- English strings are the keys: no catalog, the text passes through.
  Assert.equal(Localization.Text("Greet"), "Greet")
  -- A literal percent sign survives when there is nothing to format.
  Assert.equal(Localization.Text("100% sure"), "100% sure")
  Assert.equal(Localization.Text("Hi %s, you have %d leads", "Bob", 3), "Hi Bob, you have 3 leads")
  Assert.equal(Localization.Text("%s", "%d"), "%d")
  -- One form for a count of 1, the other for 0 and many.
  Assert.equal(Localization.Plural(1, "%d recipe", "%d recipes"), "1 recipe")
  Assert.equal(Localization.Plural(0, "%d recipe", "%d recipes"), "0 recipes")
  Assert.equal(Localization.Plural(3, "%d recipe", "%d recipes"), "3 recipes")
  -- A wrong slot count is a bug in the caller, not something to hide.
  Assert.raises(function()
    Localization.Text("%s and %s", "one")
  end)
end
