local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local ChatPrint = ns.ChatPrint or require("CraftAlert.Core.ChatPrint")
local Matcher = ns.Matcher or require("CraftAlert.Model.Matcher")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local Greeting = ns.Greeting or require("CraftAlert.Model.Greeting")
local LeadText = ns.LeadText or require("CraftAlert.UI.LeadText")

-- What `/ca test` prints (§7.3). Listens to the lead events, but only records while a test line is
-- in flight (Begin..End), then says what the line did.
local TestReport = {}

local tostring = tostring

local MATCH = "match"

local delivering = false
local installed = false
local newLead, changed -- what the listeners saw while delivering

function TestReport.Say(text, ...)
  ChatPrint.Line(Localization.Text(text, ...))
end

local say = TestReport.Say

local function printLead(lead)
  if lead.kind == "item" then
    say("Item: %s", LeadText.What(lead))
  else
    say("Profession: %s", LeadText.What(lead))
  end
  say("Why: %s", lead.why)
  say("Crafter: %s", lead.crafter)
  say("Greeting: %s", Greeting.Build(lead, _G["CraftAlertDB"].settings))
end

-- Before a test line is delivered: forget the last one and start recording.
function TestReport.Begin()
  newLead, changed = nil, false
  delivering = true
end

function TestReport.End()
  delivering = false
end

-- After a test line: the lead it made or updated, or why it made none.
function TestReport.Print()
  if newLead then
    printLead(newLead)
  elseif changed then
    printLead(Leads.Latest())
    say("Updated the existing test lead (same customer asked again)")
  elseif Matcher.lastStop ~= MATCH then
    say("No match (stopped at: %s)", tostring(Matcher.lastStop))
  else
    say("Matched, but none of your enabled characters can answer it, or the customer is on your ignore list")
  end
end

-- Bootstrap, with the other lead listeners. Once.
function TestReport.Install()
  if installed then
    return
  end
  installed = true
  Leads.On("new", function(lead)
    if delivering then
      newLead = lead
    end
  end)
  Leads.On("change", function()
    if delivering then
      changed = true
    end
  end)
end

ns.TestReport = TestReport
return TestReport
