-- Active Sync and unchanged safety ticks never rebuild Community data.
local H = dofile("tests/harness.lua")
dofile("ui/Theme.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

UnitName = function() return "BudgetMage" end
GetNormalizedRealmName = function() return "Ebonhold" end
NexusDB = {
    communityBuilds={},buildFilters={sortMode="title"},
    dpsCapture={characterBest={dummy={},lk={}},personalBest={},buildBest={}},
}
for index = 1, 1000 do
    local id = string.format("budget-%04d", index)
    local fingerprint = "budget-fingerprint-" .. index
    NexusDB.communityBuilds[id] = {
        id=id,title=string.format("Build %04d", index),author="Peer",
        ownerKey="peer@ebonhold",class="MAGE",
        postedAt=index,lastModified=index,fingerprint=fingerprint,
        echoes={{spellId=720000+index,quality=3,stacks=1}},
    }
    if index <= 500 then
        local category = index % 2 == 0 and "dummy" or "lk"
        NexusDB.dpsCapture.characterBest[category]["player"..index] = {
            player="Player"..index,dps=100000+index,level=80,ts=index,
            duration=60,class="MAGE",buildId=id,fingerprint=fingerprint,
            echoes={{spellId=720000+index,count=1}},protocolVersion=7,
        }
    end
end
Nexus.Store.Init()
dofile("core/DpsCapture.lua")
Nexus.DpsCapture.Init({}, {})

local receiving, receiveCount = false, 0
Nexus.Sync = {
    IsReceiving=function() return receiving end,
    LastSyncNewCount=function() return receiveCount end,
    ReceiveTimeLeft=function() return receiving and 3 or 0 end,
    Stats=function() return {received=receiveCount} end,
}

dofile("ui/CommunityBuilds.lua")
local C, P = Nexus.CommunityBuilds, Nexus.ViewProjections
C.Init(nil,nil)
C.Show()
local frame = NexusCommunityBuildsFrame
local onUpdate = frame and frame:GetScript("OnUpdate")
assert(type(onUpdate) == "function", "Community frame did not install update handler")

local initialVirtual = C.VirtualStats()
local initialProjection = P.Stats().builds
local initialIdentity = Nexus.DpsCapture.IdentityLookupStats()
assert(initialIdentity.rebuilds == 1 and initialIdentity.rowsScanned == 500
    and initialIdentity.lookups == 2000
    and initialIdentity.candidateChecks <= 500,
    "Community projection repeated full DPS store scans per build")
onUpdate(frame, 8.1)
local unchangedVirtual = C.VirtualStats()
local unchangedProjection = P.Stats().builds
assert(unchangedVirtual.dataBinds == initialVirtual.dataBinds
    and unchangedVirtual.periodicSkips == initialVirtual.periodicSkips + 1
    and unchangedProjection.catalogWalks == initialProjection.catalogWalks
    and unchangedProjection.dpsReads == initialProjection.dpsReads
    and unchangedProjection.sorts == initialProjection.sorts
    and unchangedProjection.defensiveCopies == initialProjection.defensiveCopies
    and Nexus.DpsCapture.IdentityLookupStats().rowsScanned
        == initialIdentity.rowsScanned,
    "unchanged eight-second tick performed Community projection work")

receiving, receiveCount = true, 1
assert(C.MarkDataDirty())
Nexus.Revisions.Advance(Nexus.Revisions.BUILD_LIBRARY_CHANGED, {scope="record"})
onUpdate(frame, 8.1)
local activeVirtual = C.VirtualStats()
assert(activeVirtual.dataBinds == initialVirtual.dataBinds
    and activeVirtual.refreshDirty,
    "active Sync dirty state rebuilt Community data")

receiving = false
onUpdate(frame, 0.25)
local finalVirtual = C.VirtualStats()
local finalProjection = P.Stats().builds
local finalIdentity = Nexus.DpsCapture.IdentityLookupStats()
assert(finalVirtual.dataBinds == initialVirtual.dataBinds + 1
    and finalVirtual.deferredRefreshes == 1
    and not finalVirtual.refreshDirty
    and finalProjection.catalogWalks == initialProjection.catalogWalks + 1
    and finalProjection.sorts == initialProjection.sorts + 1
    and finalIdentity.rebuilds == initialIdentity.rebuilds
    and finalIdentity.rowsScanned == initialIdentity.rowsScanned
    and finalIdentity.lookups == initialIdentity.lookups + 2000,
    "post-Sync dirty data did not publish exactly one complete projection")

onUpdate(frame, 8.1)
local finalNoop = C.VirtualStats()
local finalNoopProjection = P.Stats().builds
assert(finalNoop.dataBinds == finalVirtual.dataBinds
    and finalNoop.periodicSkips == finalVirtual.periodicSkips + 1
    and finalNoopProjection.catalogWalks == finalProjection.catalogWalks
    and finalNoopProjection.dpsReads == finalProjection.dpsReads
    and finalNoopProjection.sorts == finalProjection.sorts
    and finalNoopProjection.defensiveCopies == finalProjection.defensiveCopies,
    "post-publish unchanged tick repeated Community work")

-- A failed cheap probe falls back to the established refresh path instead of
-- silently declaring an unknown cache state current forever.
local originalCurrent = P.BuildsCurrent
P.BuildsCurrent = function() error("dirty probe failure") end
onUpdate(frame, 8.1)
P.BuildsCurrent = originalCurrent
local fallbackVirtual = C.VirtualStats()
assert(fallbackVirtual.dataBinds == finalNoop.dataBinds + 1
    and fallbackVirtual.periodicSkips == finalNoop.periodicSkips,
    "failed dirty probe suppressed the periodic safety refresh")

print(string.format(
    "community refresh budget: rows=1000 dpsRows=%d lookups=%d scans=%d deferred=%d periodicSkips=%d -- OK",
    finalIdentity.indexedRows, finalIdentity.lookups,
    finalIdentity.rowsScanned,
    finalVirtual.deferredRefreshes,
    finalNoop.periodicSkips))
