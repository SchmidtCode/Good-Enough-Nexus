-- Emergency build must perform no catalog, DPS, UI, or transport work.
local H = dofile("tests/harness.lua")

local tocFile = assert(io.open("Nexus.toc", "r"))
local toc = tocFile:read("*a")
tocFile:close()
assert(toc:find("core\\EmergencyCommunity.lua", 1, true),
    "emergency facade is absent from the runtime manifest")
for _, forbidden in ipairs({
    "data\\BundledBuilds.lua", "core\\LoadoutEvidence.lua",
    "core\\DataCompaction.lua", "core\\BuildCatalog.lua",
    "core\\BuildHashCache.lua", "core\\Sync.lua",
    "core\\DpsCapture.lua", "core\\ViewProjections.lua",
    "ui\\CommunityBuilds.lua", "ui\\Leaderboard.lua", "ui\\Nameplate.lua",
}) do
    assert(not toc:find(forbidden, 1, true),
        "disabled runtime module remains in Nexus.toc: " .. forbidden)
end

local joined, sent, messages = 0, 0, 0
JoinChannelByName = function() joined = joined + 1; return 1 end
SendChatMessage = function() sent = sent + 1 end
DEFAULT_CHAT_FRAME = {
    AddMessage=function() messages = messages + 1 end,
}

NexusDB = {
    communityBuilds={keep={id="keep"}},
    dpsCapture={characterBest={dummy={keep={dps=1}}}},
}
local beforeBuilds = NexusDB.communityBuilds
local beforeDps = NexusDB.dpsCapture

dofile("core/EmergencyCommunity.lua")
local E, S, D = Nexus.Emergency, Nexus.Sync, Nexus.DpsCapture
assert(E and E.communityDisabled and E.leaderboardDisabled
    and E.dpsDisabled and E.syncDisabled,
    "emergency feature flags are incomplete")

assert(S.Init() and not S.IsConnected() and not S.IsReceiving())
assert(not S.EnsureChannel() and not S.RequestSync())
assert(not S.BroadcastBuild({id="blocked"}))
assert(not S.BroadcastDpsRecord({dps=1}))
assert(not S.HandleIncoming("WLRQ|hostile", "Peer"))
assert(not S.OnUpdate(999) and joined == 0 and sent == 0,
    "disabled Sync touched the channel transport")

assert(D.Init() and not D.IsEnabled())
assert(not D.OnCombatStart() and not D.OnCombatEnd() and not D.OnUpdate(999))
assert(not D.ReceiveRecord({dps=999}) and #D.GetDpsBoard("dummy") == 0,
    "disabled DPS capture accepted or exposed records")

assert(not Nexus.CommunityBuilds.Show())
assert(not Nexus.Leaderboard.Show())
assert(not Nexus.CommunityBuilds.IsShown() and not Nexus.Leaderboard.IsShown())
assert(messages == 2, "disabled UI did not provide bounded user feedback")
assert(NexusDB.communityBuilds == beforeBuilds and NexusDB.dpsCapture == beforeDps
    and NexusDB.communityBuilds.keep.id == "keep"
    and NexusDB.dpsCapture.characterBest.dummy.keep.dps == 1,
    "emergency shutdown mutated saved community or DPS data")

print("emergency community, leaderboard, DPS, catalog, and Sync shutdown -- OK")
