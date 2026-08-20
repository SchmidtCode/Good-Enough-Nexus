-- Saved Build relationship metadata must be selected by verified canonical
-- owner authority before exact-fingerprint, title, or subset similarity.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

UnitName = function() return "Twin" end
GetNormalizedRealmName = function() return "RealmA" end

local function Echoes(first, count)
    local rows = {}
    for offset = 0, count - 1 do
        rows[#rows + 1] = {
            spellId=first + offset,quality=3,stacks=1,
        }
    end
    return rows
end

local exactEchoes = Echoes(970001, 6)
NexusDB = {
    communityBuilds={
        ["realm-b-exact"]={
            id="realm-b-exact",title="Saved Target",author="Twin",
            ownerKey="twin@realmb",ownerVerified=true,realm="realmb",
            class="ROGUE",postedAt=10,lastModified=10,
            echoes=exactEchoes,
        },
        ["realm-a-exact"]={
            id="realm-a-exact",title="Saved Target",author="Twin",
            ownerKey="twin@realma",ownerVerified=true,realm="realma",
            class="MAGE",postedAt=11,lastModified=11,
            echoes=exactEchoes,
        },
        ["saved-twin-1"]={
            id="saved-twin-1",title="Old Mirror",serverTitle="Old Mirror",
            author="Twin",ownerKey="twin@realma",ownerVerified=true,
            realm="realma",class="MAGE",postedAt=12,lastModified=12,
            echoes=exactEchoes,importedSavedBuild=true,isMine=true,
            serverSlot=1,recordBuildId="realm-b-exact",
            _savedSignature="stale",
        },
    },
    syncTombstones={},buildFilters={},
}

Nexus.Store.Init()
dofile("core/DpsCapture.lua")
Nexus.DpsCapture.Init({}, {})

local slots = {activeSlot=1,bySlot={
    [1]={name="Saved Target",class="MAGE",echoes=exactEchoes},
}}
local function NewController()
    local owner = Nexus.CommunityInternals.Controller.New({})
    owner.Initialize({
        Slots=function() return slots end,
        EchoReconcileStats=function()
            return {generations={slots=1}}
        end,
        GetLoadoutWishlist=function() return nil end,
    }, nil)
    return owner
end
local controller = NewController()

local function ImportAll(owner)
    assert(owner.BeginSavedLoadoutImport(true),
        "Saved Build import did not start")
    local changed, pending, total = 0, true, 0
    local pumps = 0
    while pending do
        changed, pending = owner.PumpSavedLoadoutImport(25)
        total = total + changed
        pumps = pumps + 1
        assert(pumps < 50, "Saved Build import did not converge")
    end
    return total
end

assert(ImportAll(controller) == 1,
    "Saved Build import did not refresh the stale related relationship")
local mirror = assert(Nexus.BuildCatalog.Get("saved-twin-1"))
assert(mirror.recordBuildId == "realm-a-exact" and mirror.class == "MAGE",
    "EXPECTED RED: same-name RealmB record outranked exact RealmA owner authority")

-- Durable IDs are only hints. A later stale/corrupt relationship must be
-- revalidated when detail and DPS readers consume it, even before the next
-- server-slot reconciliation runs.
mirror.recordBuildId = "realm-b-exact"
mirror.lastModified = mirror.lastModified + 1
assert(Nexus.BuildCatalog.Put(mirror),
    "stale related-ID fixture did not enter the represented catalog")
local stale = assert(Nexus.BuildCatalog.Get("saved-twin-1"))
local originalLeaderboard = Nexus.DpsCapture.GetLeaderboard
local originalEchoLeaderboard = Nexus.DpsCapture.GetLeaderboardForEchoes
Nexus.DpsCapture.GetLeaderboard = function(buildId)
    if buildId == "realm-b-exact" then
        return {{player="Twin",dps=990000}}
    elseif buildId == stale.id then
        return {{player="Twin",dps=970000}}
    end
    return {}
end
Nexus.DpsCapture.GetLeaderboardForEchoes = function()
    return {{player="Other",dps=980000}}
end
assert(controller.RecordBuildId(stale) == nil
    and controller.DpsSummary(stale).best == 0,
    "EXPECTED RED: stale cross-realm ID/fingerprint supplied Community DPS identity")
Nexus.DpsCapture.GetLeaderboard = originalLeaderboard
Nexus.DpsCapture.GetLeaderboardForEchoes = originalEchoLeaderboard

-- A valid source-bound publication is also a durable read relation. It must
-- remain usable before the next slot reconciliation even when recordBuildId
-- is absent, while an arbitrary same-owner published pointer remains invalid.
local publishedOnlyId = "published-only-local"
assert(Nexus.BuildCatalog.Put({
    id=publishedOnlyId,title="Saved Target",author="Twin",
    ownerKey="twin@realma",ownerVerified=true,realm="realma",
    class="MAGE",postedAt=18,lastModified=18,echoes=exactEchoes,
    sourceSavedBuildId=stale.id,
}), "published-only relation fixture did not initialize")
stale.recordBuildId = nil
stale.publishedBuildId = publishedOnlyId
stale.lastModified = stale.lastModified + 1
assert(Nexus.BuildCatalog.Put(stale),
    "published-only Saved relationship did not initialize")
stale = assert(Nexus.BuildCatalog.Get("saved-twin-1"))
Nexus.DpsCapture.GetLeaderboard = function(buildId)
    if buildId == publishedOnlyId then
        return {{player="Twin",dps=345000}}
    end
    return {}
end
assert(controller.RecordBuildId(stale) == publishedOnlyId
    and controller.DpsSummary(stale).best == 345000,
    "EXPECTED RED: verified source-bound published-only relation was ignored")
Nexus.DpsCapture.GetLeaderboard = originalLeaderboard
stale.publishedBuildId = nil
stale.lastModified = stale.lastModified + 1
assert(Nexus.BuildCatalog.Put(stale),
    "published-only relationship cleanup failed")

assert(Nexus.BuildCatalog.Put({
    id="realm-a-unrelated",title="Different Local Build",author="Twin",
    ownerKey="twin@realma",ownerVerified=true,realm="realma",
    class="MAGE",postedAt=20,lastModified=20,
    echoes=Echoes(975001, 6),
}), "same-owner stale relationship fixture did not initialize")
stale.recordBuildId = "realm-a-unrelated"
stale.lastModified = stale.lastModified + 1
assert(Nexus.BuildCatalog.Put(stale),
    "same-owner stale related ID did not enter the catalog")
stale = assert(Nexus.BuildCatalog.Get("saved-twin-1"))
assert(controller.RecordBuildId(stale) == nil,
    "EXPECTED RED: owner equality bypassed related content revalidation")

stale.recordBuildId = "realm-b-exact"
stale.publishedBuildId = "realm-b-exact"
stale.lastModified = stale.lastModified + 1
assert(Nexus.BuildCatalog.Put(stale),
    "projection stale related-ID fixture did not initialize")
stale = assert(Nexus.BuildCatalog.Get("saved-twin-1"))

local requestedIds = {}
local projection = Nexus.CommunityInternals.Projection.New({
    builds=function() return {}, {} end,
    buildsCurrent=function() return false end,
    loadBuild=function(id) return Nexus.BuildCatalog.Get(id) end,
    revisionSnapshot=function() return controller.RevisionSnapshot() end,
    recordBuildId=function(build) return controller.RecordBuildId(build) end,
    publishedBuildId=function(build)
        return controller.PublishedBuildId(build)
    end,
    leaderboard=function(buildId)
        requestedIds[#requestedIds + 1] = buildId
        if buildId == "realm-b-exact" then
            return {{player="Twin",dps=990000}}
        elseif buildId == stale.id then
            return {{player="Twin",dps=970000}}
        end
        return {}
    end,
    personalBest=function() return nil end,
})
local detail = assert(projection.Detail("saved-twin-1", {
    ownerKey="twin@realma",player="Twin",detailsAvailable=true,
}))
for _, buildId in ipairs(requestedIds) do
    assert(buildId ~= "realm-b-exact",
        "EXPECTED RED: Community projection bypassed related-owner validation")
end
assert(#detail.dummyRows == 0 and #detail.lkRows == 0,
    "cross-realm related DPS remained visible in Saved Build detail")
assert(detail.actionText == "Upload Build"
    and detail.editState
    and detail.editState:find("Local server loadout", 1, true),
    "EXPECTED RED: invalid published relationship remained visible as uploaded")

-- A stale publishedBuildId must not become write authority. Keep the occupied
-- foreign record intact and publish the valid local mirror to a safe identity.
local occupiedId = "published-saved-twin-1"
assert(Nexus.BuildCatalog.Put({
    id=occupiedId,title="RealmB Publication",author="Twin",
    ownerKey="twin@realmb",ownerVerified=true,realm="realmb",
    class="ROGUE",postedAt=30,lastModified=30,
    echoes=Echoes(980001, 6),sourceSavedBuildId="saved-twin-1",
}), "foreign publication collision fixture did not initialize")
stale = assert(Nexus.BuildCatalog.Get("saved-twin-1"))
stale.publishedBuildId = occupiedId
stale.lastModified = stale.lastModified + 1
assert(Nexus.BuildCatalog.Put(stale),
    "stale published-ID relationship did not initialize")
Nexus.Sync = {BroadcastBuildSummary=function() return true end}
local published, publishedId = controller.PublishImportedBuild("saved-twin-1")
local occupied = assert(Nexus.BuildCatalog.Get(occupiedId))
local publishedRecord = publishedId and Nexus.BuildCatalog.Get(publishedId)
local savedAfterPublish = assert(Nexus.BuildCatalog.Get("saved-twin-1"))
assert(published and publishedId ~= occupiedId
    and occupied.title == "RealmB Publication"
    and occupied.ownerKey == "twin@realmb"
    and publishedRecord and publishedRecord.sourceSavedBuildId == stale.id
    and Nexus.Identity.VerifiedOwnerKey(publishedRecord) == "twin@realma"
    and savedAfterPublish.publishedBuildId == publishedId,
    "EXPECTED RED: stale published ID overwrote another canonical owner")
local publishedAgain, samePublishedId =
    controller.PublishImportedBuild("saved-twin-1")
assert(publishedAgain and samePublishedId == publishedId
    and Nexus.Identity.VerifiedOwnerKey(
        Nexus.BuildCatalog.Get(occupiedId)) == "twin@realmb",
    "collision-safe publication identity was not stable on re-upload")

-- Once the stable publication relationship is reflected in the mirror's
-- signature, a later stale ID must still be cleared during reload/import.
ImportAll(controller)
local stable = assert(Nexus.BuildCatalog.Get("saved-twin-1"))
assert(stable.publishedBuildId == publishedId
    and stable.recordBuildId == publishedId,
    "valid publication did not become the Saved Build relation")
assert(Nexus.BuildCatalog.Put({
    id="000-equal-local",title="Saved Target",author="Twin",
    ownerKey="twin@realma",ownerVerified=true,realm="realma",
    class="MAGE",postedAt=35,lastModified=35,echoes=exactEchoes,
}), "lexically earlier equal relation fixture did not initialize")
ImportAll(controller)
stable = assert(Nexus.BuildCatalog.Get("saved-twin-1"))
assert(stable.publishedBuildId == publishedId
    and stable.recordBuildId == publishedId,
    "source-bound publication was displaced by an equal candidate")
local publicationReload = NewController()
ImportAll(publicationReload)
stable = assert(Nexus.BuildCatalog.Get("saved-twin-1"))
assert(stable.publishedBuildId == publishedId
    and stable.recordBuildId == publishedId,
    "source-bound publication changed after a fresh controller reload")
stable.publishedBuildId = occupiedId
stable.lastModified = stable.lastModified + 1
assert(Nexus.BuildCatalog.Put(stable),
    "post-publication stale ID fixture did not initialize")
ImportAll(controller)
local reloadedPublishedId = Nexus.BuildCatalog.Get("saved-twin-1").publishedBuildId
assert(reloadedPublishedId == publishedId,
    "EXPECTED RED: invalid published ID survived unchanged Saved Build import"
        .. " (expected=" .. tostring(publishedId)
        .. ", actual=" .. tostring(reloadedPublishedId) .. ")")

-- The historical mirror ID contains only the short character name. A RealmB
-- mirror occupying that ID must neither be overwritten by RealmA's live slot
-- nor be swept as an obsolete RealmA mirror during cleanup.
local foreignMirrorId = "saved-twin-2"
local foreignOrphanId = "saved-twin-3"
assert(Nexus.BuildCatalog.Put({
    id=foreignMirrorId,title="RealmB Saved Slot",serverTitle="RealmB Saved Slot",
    author="Twin",ownerKey="twin@realmb",ownerVerified=true,realm="realmb",
    class="ROGUE",postedAt=40,lastModified=40,echoes=Echoes(985001, 6),
    importedSavedBuild=true,isMine=false,serverSlot=2,
}), "foreign Saved mirror collision fixture did not initialize")
assert(Nexus.BuildCatalog.Put({
    id=foreignOrphanId,title="RealmB Orphan",serverTitle="RealmB Orphan",
    author="Twin",ownerKey="twin@realmb",ownerVerified=true,realm="realmb",
    class="ROGUE",postedAt=41,lastModified=41,echoes=Echoes(986001, 6),
    importedSavedBuild=true,isMine=false,serverSlot=3,
}), "foreign Saved mirror cleanup fixture did not initialize")
slots.bySlot[2] = {
    name="RealmA Saved Slot",class="MAGE",echoes=Echoes(987001, 6),
}
ImportAll(controller)
local foreignMirror = assert(Nexus.BuildCatalog.Get(foreignMirrorId))
local localSlotTwo
for id, build in pairs(Nexus.BuildCatalog.All()) do
    if build.importedSavedBuild and build.serverSlot == 2
        and Nexus.Identity.VerifiedOwnerKey(build) == "twin@realma" then
        localSlotTwo = id
    end
end
assert(Nexus.Identity.VerifiedOwnerKey(foreignMirror) == "twin@realmb"
    and foreignMirror.title == "RealmB Saved Slot"
    and Nexus.BuildCatalog.Get(foreignOrphanId) ~= nil
    and localSlotTwo and localSlotTwo ~= foreignMirrorId,
    "EXPECTED RED: short-name Saved mirror collision overwrote or deleted RealmB")
assert(Nexus.BuildCatalog.RemoveOverlay(foreignMirrorId),
    "foreign base mirror removal failed")
ImportAll(controller)
local stableLocalSlotTwo
for id, build in pairs(Nexus.BuildCatalog.All()) do
    if build.importedSavedBuild and build.serverSlot == 2
        and Nexus.Identity.VerifiedOwnerKey(build) == "twin@realma" then
        stableLocalSlotTwo = id
    end
end
assert(stableLocalSlotTwo == localSlotTwo,
    "EXPECTED RED: vacated short-name ID changed the established local mirror identity")

local ambiguousMirrorId = "saved-twin-4"
local ambiguousOrphanId = "saved-twin-8"
assert(Nexus.BuildCatalog.Put({
    id=ambiguousMirrorId,title="Ambiguous Private",userTitle="Ambiguous Private",
    serverTitle="Ambiguous Private",author="Twin",isMine=true,
    class="ROGUE",postedAt=45,lastModified=45,echoes=Echoes(987501, 6),
    importedSavedBuild=true,serverSlot=4,
}), "ambiguous Saved mirror collision fixture did not initialize")
assert(Nexus.BuildCatalog.Put({
    id=ambiguousOrphanId,title="Ambiguous Orphan",author="Twin",isMine=true,
    class="ROGUE",postedAt=46,lastModified=46,echoes=Echoes(987601, 6),
    importedSavedBuild=true,serverSlot=8,
}), "ambiguous Saved mirror cleanup fixture did not initialize")
slots.bySlot[4] = {
    name="RealmA Slot Four",class="MAGE",echoes=Echoes(987701, 6),
}
ImportAll(controller)
local ambiguousMirror = assert(Nexus.BuildCatalog.Get(ambiguousMirrorId))
local localSlotFour
for id, build in pairs(Nexus.BuildCatalog.All()) do
    if build.importedSavedBuild and build.serverSlot == 4
        and Nexus.Identity.VerifiedOwnerKey(build) == "twin@realma" then
        localSlotFour = id
    end
end
assert(ambiguousMirror.ownerVerified ~= true
    and ambiguousMirror.userTitle == "Ambiguous Private"
    and Nexus.BuildCatalog.Get(ambiguousOrphanId) ~= nil
    and localSlotFour and localSlotFour ~= ambiguousMirrorId,
    "EXPECTED RED: ambiguous short-name mirror was adopted or cleaned as RealmA")

-- A valid persisted relation remains the stable winner across equal candidates.
-- With no persisted winner, equal authority/content candidates resolve by ID
-- so hash-table traversal order cannot change a cold relationship.
local tieEchoes = Echoes(988001, 6)
for _, id in ipairs({"tie-z", "tie-a"}) do
    assert(Nexus.BuildCatalog.Put({
        id=id,title="Tie Target",author="Twin",
        ownerKey="twin@realma",ownerVerified=true,realm="realma",
        class="MAGE",postedAt=50,lastModified=50,echoes=tieEchoes,
    }), "deterministic tie candidate did not initialize: " .. id)
end
assert(Nexus.BuildCatalog.Put({
    id="saved-twin-5",title="Old Tie Mirror",serverTitle="Old Tie Mirror",
    author="Twin",ownerKey="twin@realma",ownerVerified=true,realm="realma",
    class="MAGE",postedAt=51,lastModified=51,echoes=tieEchoes,
    importedSavedBuild=true,isMine=true,serverSlot=5,
    recordBuildId="tie-z",_savedSignature="stale",
}), "deterministic tie mirror did not initialize")
slots.bySlot[5] = {name="Tie Target",class="MAGE",echoes=tieEchoes}
ImportAll(controller)
assert(Nexus.BuildCatalog.Get("saved-twin-5").recordBuildId == "tie-z",
    "valid persisted relation was displaced by an equal candidate")
slots.bySlot[7] = {name="Tie Target",class="MAGE",echoes=tieEchoes}
ImportAll(controller)
assert(Nexus.BuildCatalog.Get("saved-twin-7").recordBuildId == "tie-a",
    "cold equal related candidates did not resolve deterministically")

-- Content similarity never repairs missing authority. The verified RealmA
-- title/subset candidate is the only admissible relation; a realm-less exact
-- match and a verified RealmB title/subset match remain ambient evidence.
local subsetEchoes = Echoes(989001, 8)
assert(Nexus.BuildCatalog.Put({
    id="unverified-exact",title="Subset Target",author="Twin",
    ownerKey="twin@realma",ownerVerified=false,realm="realma",
    class="ROGUE",postedAt=60,lastModified=60,
    echoes=subsetEchoes,
}), "explicitly unverified exact candidate did not initialize")
assert(Nexus.BuildCatalog.Put({
    id="realm-less-exact",title="Subset Target",author="Twin",
    ownerVerified=true,class="ROGUE",postedAt=60,lastModified=60,
    echoes=subsetEchoes,
}), "realm-less exact candidate did not initialize")
assert(Nexus.BuildCatalog.Put({
    id="realm-b-subset",title="Subset Target",author="Twin",
    ownerKey="twin@realmb",ownerVerified=true,realm="realmb",
    class="ROGUE",postedAt=61,lastModified=61,
    echoes=Echoes(989001, 10),
}), "RealmB subset candidate did not initialize")
assert(Nexus.BuildCatalog.Put({
    id="realm-a-subset",title="Subset Target",author="Twin",
    ownerKey="twin@realma",ownerVerified=true,realm="realma",
    class="MAGE",postedAt=62,lastModified=62,
    echoes=Echoes(989001, 10),
}), "RealmA subset candidate did not initialize")
slots.bySlot[6] = {name="Subset Target",class="MAGE",echoes=subsetEchoes}
ImportAll(controller)
local subsetMirror = assert(Nexus.BuildCatalog.Get("saved-twin-6"))
assert(subsetMirror.recordBuildId == "realm-a-subset"
    and subsetMirror.class == "MAGE",
    "verified exact-owner title/subset relation was not selected")

-- A catalog revision must invalidate the warm relation cache. Once the only
-- verified local candidate changes owner, the durable relationship clears;
-- recreating the controller must not resurrect it from persisted metadata.
assert(Nexus.BuildCatalog.RemoveOverlay("realm-a-subset"),
    "valid subset candidate removal failed")
assert(Nexus.BuildCatalog.Put({
    id="realm-a-subset",title="Subset Target",author="Twin",
    ownerKey="twin@realmb",ownerVerified=true,realm="realmb",
    class="ROGUE",postedAt=62,lastModified=63,
    echoes=Echoes(989001, 10),
}), "subset owner-change fixture did not initialize")
ImportAll(controller)
subsetMirror = assert(Nexus.BuildCatalog.Get("saved-twin-6"))
assert(subsetMirror.recordBuildId == nil and subsetMirror.class ~= "ROGUE",
    "EXPECTED RED: cache retained a relation after canonical owner changed")
local reloadedController = NewController()
ImportAll(reloadedController)
assert(Nexus.BuildCatalog.Get("saved-twin-6").recordBuildId == nil,
    "stale persisted relation returned after controller reload")

assert(Nexus.BuildCatalog.RemoveOverlay("realm-a-subset"),
    "wrong-owner subset candidate removal failed")
assert(Nexus.BuildCatalog.Put({
    id="realm-a-subset",title="Subset Target",author="Twin",
    ownerKey="twin@realma",ownerVerified=true,realm="realma",
    class="MAGE",postedAt=62,lastModified=64,
    echoes=Echoes(989001, 10),
}), "restored exact-owner subset candidate did not initialize")
ImportAll(reloadedController)
assert(Nexus.BuildCatalog.Get("saved-twin-6").recordBuildId == "realm-a-subset",
    "later verified exact-owner evidence did not restore the relation")

print("saved build related owner: exact-owner-first stale-read-denial projection collision-safe-publish -- OK")
