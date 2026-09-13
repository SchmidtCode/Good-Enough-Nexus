local H = dofile("tests/harness.lua")

GameTooltip = {
    lines = {},
    SetOwner = function(self) self.lines = {} end,
    AddLine = function(self, text) self.lines[#self.lines + 1] = tostring(text or "") end,
    Show = function() end,
    Hide = function() end,
}

dofile("ui/Panel.lua")
NexusDB = {}
Nexus.Panel.Init({ ToggleAuto = function() return true end })

local missing = {"Gamma Bolt x1 (Rare:x1)"}
for i = 2, 30 do
    missing[i] = string.format("Need Echo %02d x1 (Common:x1)", i)
end
local longCard = "Mind Expansion (Common) gives a long recommendation explanation"
local longRecommendation = "Forced least-harmful selection with the complete reason visible"
Nexus.Panel.Render({
    level = 80,
    progress = {
        wishlistName = "Quality target", activeSlot = 4,
        owned = 10, total = 40, missing = missing,
        shed = {"Spiteful Thorns (Epic)"}, toLock = {}, unknownTomes = {},
    },
    cards = {{ text = longCard }},
    recommendation = longRecommendation,
    auto = true,
    version = "test",
})

local panel = assert(NexusPanel, "panel was not created")
assert(panel._needText and panel._needText.text:find("Rare", 1, true)
    and panel._needText.text:find("|cff0070dd", 1, true),
    "visible Still Needed summary hid or failed to color exact quality")

assert(panel._needHit and panel._needHit:GetScript("OnEnter"),
    "Still Needed full-list tooltip is unavailable")
panel._needHit:GetScript("OnEnter")(panel._needHit)
local joined = table.concat(GameTooltip.lines, "\n")
assert(joined:find("Need Echo 30", 1, true),
    "Still Needed tooltip still cuts off entries after 25")
assert(not joined:find("+5 more", 1, true),
    "Still Needed tooltip still substitutes a cutoff summary")
assert(joined:find("|cff0070ddRare|r", 1, true),
    "Still Needed tooltip did not quality-color Rare demand")

local expectations = {
    { hit = panel._statusHit, text = "Roll recommendations active" },
    { hit = panel._cardHits and panel._cardHits[1], text = longCard },
    { hit = panel._recommendationHit, text = longRecommendation },
}
for _, expected in ipairs(expectations) do
    assert(expected.hit and expected.hit:GetScript("OnEnter"),
        "clipped HUD text has no full-text hover target")
    expected.hit:GetScript("OnEnter")(expected.hit)
    assert(table.concat(GameTooltip.lines, "\n"):find(expected.text, 1, true),
        "HUD hover did not expose the complete visible text")
end

print("HUD shows quality and exposes complete lists and clipped text -- OK")
