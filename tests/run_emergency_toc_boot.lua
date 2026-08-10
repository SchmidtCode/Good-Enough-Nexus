-- The exact emergency TOC boots the normal wishlist/automation shell while
-- all community backends remain absent and inert.
local H = dofile("tests/harness.lua")

for _, name in ipairs({
    "BundledBuilds", "LoadoutEvidence", "DataCompaction", "BuildCatalog",
    "BuildHashCache", "Sync", "DpsCapture", "ViewProjections",
    "CommunityBuilds", "Leaderboard", "Nameplate",
}) do
    Nexus[name] = nil
end

local joined, sent, messages = 0, 0, 0
JoinChannelByName = function() joined = joined + 1; return 1 end
SendChatMessage = function() sent = sent + 1 end
DEFAULT_CHAT_FRAME = {
    AddMessage=function() messages = messages + 1 end,
}

local tocFile = assert(io.open("Nexus.toc", "r"))
local tocText = tocFile:read("*a")
tocFile:close()
for line in (tocText .. "\n"):gmatch("(.-)\n") do
    local path = line:match("^%s*(.-)%s*$")
    if path ~= "" and not path:find("^##") then
        dofile((path:gsub("\\", "/")))
    end
end

NexusDB = {
    communityBuilds={keep={id="keep"}},
    dpsCapture={characterBest={dummy={keep={dps=1}}}},
}
local buildsRef, dpsRef = NexusDB.communityBuilds, NexusDB.dpsCapture
H.playerLevel = 5
H.wishlist = {name="Emergency Wishlist",class="MAGE",echoes={
    {spellId=200100,quality=3,stacks=1},
}}

H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("PLAYER_ENTERING_WORLD")
H.Advance(3)

assert(Nexus.Emergency and Nexus.Emergency.syncDisabled)
assert(Nexus.BundledBuilds == nil and Nexus.BuildCatalog == nil
    and Nexus.DataCompaction == nil and Nexus.ViewProjections == nil,
    "disabled catalog modules survived the exact TOC boot")
assert(joined == 0 and sent == 0 and not Nexus.Sync.IsConnected(),
    "exact TOC boot activated Sync transport")
assert(NexusDB.communityBuilds == buildsRef and NexusDB.dpsCapture == dpsRef
    and buildsRef.keep.id == "keep"
    and dpsRef.characterBest.dummy.keep.dps == 1,
    "exact TOC boot mutated disabled SavedVariables")

SlashCmdList.NEXUS("sync")
SlashCmdList.NEXUS("builds")
SlashCmdList.NEXUS("leaderboard")
assert(joined == 0 and sent == 0
    and _G.NexusCommunityBuildsFrame == nil
    and _G.NexusLeaderboardFrame == nil,
    "disabled commands activated community work")

SlashCmdList.NEXUS("editor")
assert(_G.NexusEditorFrame and _G.NexusEditorFrame:IsShown(),
    "emergency shutdown broke the wishlist editor")
assert(messages >= 4, "emergency boot did not report status to the user")

print("exact emergency TOC boot preserves wishlist UI with zero community work -- OK")
