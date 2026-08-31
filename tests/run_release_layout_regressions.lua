local H = dofile("tests/harness.lua")

local fontStrings = {}
local realCreateFrame = CreateFrame
function CreateFrame(...)
    local created = realCreateFrame(...)
    local realCreateFontString = created.CreateFontString
    created.CreateFontString = function(...)
        local fontString = realCreateFontString(...)
        fontStrings[#fontStrings + 1] = fontString
        return fontString
    end
    return created
end

local function FindText(pattern)
    for _, fontString in ipairs(fontStrings) do
        if fontString:GetText():find(pattern, 1, true) then return fontString end
    end
    return nil
end

local failures = {}
local function Check(ok, message)
    if not ok then failures[#failures + 1] = message end
end

NexusDB = { hasSeenQuickStart=true }
dofile("ui/Changelog.lua")
Nexus.Changelog.ShowIfNeeded()

local changelog = _G.NexusChangelogPopup
local changelogBody = FindText("Reload safety")
assert(changelog and changelogBody, "release update window was not created")
Check(changelog:GetHeight() >= 360,
    "release update window is too short for its content")
Check(not changelogBody:GetText():find("Back up", 1, true),
    "release update window still asks the user to back up databases")

local hasBottomBound = false
for pointIndex = 1, #changelogBody.points do
    local point, relative, relativePoint, _, y = changelogBody:GetPoint(pointIndex)
    if point == "BOTTOMRIGHT" and relative == changelog
        and relativePoint == "BOTTOMRIGHT" and y >= 48 then
        hasBottomBound = true
    end
end
Check(hasBottomBound,
    "release update copy can extend through the button and below the window")

dofile("ui/Panel.lua")
Nexus.Panel.Init({ ToggleAuto=function() return false end })
Nexus.Panel.Render({
    progress={
        wishlistName="Wrand Fury Proc 85",
        owned=36,
        total=78,
        missing={"Arcane Cadence", "Archmage's Mark", "Constellations"},
        shed={"Agility Boost (Uncommon)", "Anger Management (Uncommon)"},
        unknownTomes={"Missing Tome"},
        toLock={"Target Lock"},
    },
    cards={},
    auto=false,
    level=80,
})

local stillNeeded = FindText("Arcane Cadence")
local toLock = FindText("TO LOCK")
assert(stillNeeded and toLock, "HUD progress regions were not created")
local _, _, _, _, stillNeededY = stillNeeded:GetPoint()
local _, _, _, _, toLockY = toLock:GetPoint()
Check(toLockY <= stillNeededY - 48,
    "TO LOCK overlaps the three-line STILL NEEDED list")

assert(#failures == 0, table.concat(failures, "\n"))
print("release update window and HUD vertical spacing -- OK")
