local H = dofile("tests/harness.lua")
dofile("ui/Theme.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

UnitName = function() return "SearchMage" end
GetNormalizedRealmName = function() return "Ebonhold" end
NexusDB = {
    communityBuilds={},buildFilters={sortMode="title"},
    dpsCapture={characterBest={dummy={},lk={}},personalBest={},buildBest={}},
}
for index = 1, 200 do
    local id = string.format("search-%04d", index)
    NexusDB.communityBuilds[id] = {
        id=id,title=string.format("Search Build %04d", index),author="Peer",
        ownerKey="peer@ebonhold",class="MAGE",postedAt=index,
        lastModified=index,fingerprint="search-fingerprint-" .. index,
        echoes={{spellId=720000+index,quality=3,stacks=1}},
    }
end
Nexus.Store.Init()
dofile("core/DpsCapture.lua")
Nexus.DpsCapture.Init({}, {})
Nexus.Sync = {
    IsReceiving=function() return false end,
    LastSyncNewCount=function() return 0 end,
    ReceiveTimeLeft=function() return 0 end,
    Stats=function() return {received=0} end,
}
dofile("ui/CommunityBuilds.lua")
local Builds = Nexus.CommunityBuilds
Builds.Init(nil, nil)
Builds.Show()

local before = Builds.VirtualStats().dataBinds
local searchRefreshes = Builds.VirtualStats().searchRefreshes
for _, text in ipairs({"B", "Bu", "Build", "Build 019"}) do
    NexusBuildsSearch:SetText(text)
    NexusBuildsSearch:GetScript("OnTextChanged")(NexusBuildsSearch)
end
assert(Builds.VirtualStats().dataBinds == before,
    "Community search rebuilt the projection for every keystroke")
assert(Nexus.Scheduler.Pending("ui.community-builds.search"),
    "Community search did not schedule one debounced refresh")

H.Advance(0.3, 0.05)
local after = Builds.VirtualStats()
assert(after.dataBinds == before + 1
    and after.searchRefreshes == searchRefreshes + 1 and after.results > 0,
    "Community search did not publish one coalesced refresh")

print("Community search coalesces rapid keystrokes into one refresh -- OK")
