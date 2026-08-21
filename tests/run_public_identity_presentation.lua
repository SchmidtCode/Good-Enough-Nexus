-- Public identity presentation keeps authoritative realms distinct, shadows
-- ambiguous duplicates without erasing them, and uses the same labels for
-- Leaderboard and Community projections.
local H = dofile("tests/harness.lua")

Nexus = {}
dofile("core/Revisions.lua")
dofile("core/Identity.lua")
dofile("core/LoadoutEvidence.lua")
Nexus.LoadoutEvidence.Init({})
dofile("core/CandidateEvidence.lua")
dofile("core/DiagnosticHistory.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua")
dofile("core/SyncTransport.lua")
dofile("core/SyncCompatibility.lua")
dofile("core/SyncReconciler.lua")
dofile("core/SyncInbound.lua")
dofile("core/SyncDiagnostics.lua")
dofile("core/SyncSession.lua")
dofile("core/Sync.lua")
dofile("core/DpsCapture.lua")

UnitName = function(unit) return unit == "player" and "Viewer" or nil end
UnitClass = function() return "Mage", "MAGE" end
GetNormalizedRealmName = function() return "ViewerRealm" end

local DPS, Codec, Sync = Nexus.DpsCapture, Nexus.Codec, Nexus.Sync
local function Echoes(spellId)
    return {{spellId=spellId,quality=3,stacks=1}}
end
local function Row(player, ownerKey, realm, spellId, dps, stamp, category)
    local echoes = Echoes(spellId)
    return {
        player=player,ownerKey=ownerKey,realm=realm,
        ownerVerified=ownerKey and true or false,
        dps=dps,level=80,ts=stamp,duration=category == "lk" and 240 or 65,
        class="MAGE",category=category,
        echoes=echoes,fingerprint=DPS.GetEchoKey(echoes),
        loadoutHash=DPS.GetEchoHash(echoes),
        lockedEchoes={{spellId=spellId+1000,quality=4,stacks=1}},
        buildId="build-"..spellId,protocolVersion=7,
    }
end

local aDummy = Row("Twin", "twin@realma", "realma", 810001,
    25000000, 10, "dummy")
local aBetter = Row("Twin", "twin@realma", "realma", 810002,
    27000000, 11, "dummy")
local bDummy = Row("Twin", "twin@realmb", "realmb", 810003,
    26000000, 12, "dummy")
local aLk = Row("Twin", "twin@realma", "realma", 810002,
    19000000, 13, "lk")
local bLk = Row("Twin", "twin@realmb", "realmb", 810003,
    21000000, 14, "lk")

NexusDB = {
    communityBuilds={},syncTombstones={},
    dpsCapture={characterBest={
        dummy={
            ["twin@realma"]=aBetter,
            ["legacy-case-alias"]=aDummy,
            ["twin@realmb"]=bDummy,
        },
        lk={
            ["twin@realma"]=aLk,
            ["twin@realmb"]=bLk,
        },
    }},
}

Sync.Init(Codec, {})
DPS.Init({}, Sync)

-- Two stored rows with the same proven owner reconcile through the existing
-- per-category better-row rule and retain the exact winning evidence.
local dummy = DPS.GetDpsBoard("dummy")
assert(#dummy == 2, "same canonical owner did not reconcile to one row")
local byOwner = {}
for _, row in ipairs(dummy) do byOwner[row.ownerKey] = row end
assert(byOwner["twin@realma"] and byOwner["twin@realma"].dps == 27000000
        and byOwner["twin@realma"].fingerprint == aBetter.fingerprint
        and byOwner["twin@realma"].lockedEchoes[1].spellId == 811002,
    "canonical reconciliation did not retain the strongest historical row")
local storedA = NexusDB.dpsCapture.characterBest.dummy["twin@realma"]
assert(storedA and storedA.buildId == aBetter.buildId
        and storedA.fingerprint == aBetter.fingerprint
        and storedA.lockedEchoes[1].spellId == 811002,
    "canonical reconciliation rewrote the winning stored evidence")
assert(byOwner["twin@realma"].displayPlayer ~= byOwner["twin@realmb"].displayPlayer
        and byOwner["twin@realma"].displayPlayer:find("realma",1,true)
        and byOwner["twin@realmb"].displayPlayer:find("realmb",1,true),
    "different verified realms are not visibly distinguishable")

local function WireRecord(player, spellId, dps, stamp, category,
        ownerKey, realm)
    local echoes = Echoes(spellId)
    return {
        v=7,f=DPS.GetEchoKey(echoes),h=DPS.GetEchoHash(echoes),e=echoes,
        c=category,d=dps,u=category == "lk" and 240 or 65,t=stamp,
        p=player,l=80,k="MAGE",o=ownerKey,r=realm,
        lk={{spellId=spellId+1000,quality=4,stacks=1}},
    }
end
local function Deliver(sender, transferId, record)
    local encoded = Codec.Base64Encode(Codec.JSONEncode(record))
    local chunkSize, result = 120, false
    local total = math.ceil(#encoded/chunkSize)
    for index=1,total do
        local packet=string.format("WLD2|%s|%s|%d/%d|%s",sender,
            transferId,index,total,encoded:sub(
                (index-1)*chunkSize+1,index*chunkSize))
        assert(#packet <= 255, "identity fixture exceeded wire limit")
        result = Sync.HandleIncoming(packet,sender) or result
    end
    return result
end

-- A stronger realm-less Sync record remains durable evidence but cannot
-- displace or visually duplicate either proven Twin.
local ambiguous = WireRecord("Twin", 810004, 40000000, 20, "dummy",
    "twin@realma", "realma")
assert(Deliver("Twin", "ambiguous-twin", ambiguous),
    "realm-less Sync evidence was not retained")
assert(NexusDB.dpsCapture.characterBest.dummy.twin
        and NexusDB.dpsCapture.characterBest.dummy.twin.dps == 40000000,
    "ambiguous stronger evidence was erased or assigned")
dummy = DPS.GetDpsBoard("dummy")
assert(#dummy == 2, "ambiguous Twin was counted as a public duplicate")
for _, row in ipairs(dummy) do
    assert(row.ownerVerified == true and row.displayPlayer ~= "Twin",
        "verified Twin lost public precedence or realm qualification")
end

-- A later exact copy may promote only the identical ambiguous evidence.
local bridge = WireRecord("Bridge", 810005, 23000000, 21, "dummy",
    "bridge@realmc", "realmc")
assert(Deliver("Bridge", "bridge-short", bridge),
    "ambiguous bridge evidence was not retained")
assert(Deliver("Bridge-RealmC", "bridge-exact", bridge),
    "exact bridge did not promote matching evidence")
assert(not NexusDB.dpsCapture.characterBest.dummy.bridge
        and NexusDB.dpsCapture.characterBest.dummy["bridge@realmc"]
        and NexusDB.dpsCapture.characterBest.dummy["bridge@realmc"].ownerVerified,
    "exact bridge did not atomically promote only its matching row")

-- Reload retains both proven realms and the shadowed ambiguous evidence.
Sync.Init(Codec, {})
DPS.Init({}, Sync)
assert(NexusDB.dpsCapture.characterBest.dummy.twin,
    "reload erased ambiguous historical evidence")
dummy = DPS.GetDpsBoard("dummy")
assert(#dummy == 3, "reload changed public identity reconciliation")

-- The shared projection policy applies to Dummy, LK, Combined, and Community
-- before sorting/counting/paging. Community builds remain distinct records,
-- but their authors can never render as indistinguishable Twin labels.
local builds = {
    a={id="a",title="Realm A",author="Twin",ownerKey="twin@realma",
        realm="realma",ownerVerified=true,class="MAGE",ordinaryComplete=true,
        echoes=Echoes(820001),fingerprint=DPS.GetEchoKey(Echoes(820001))},
    b={id="b",title="Realm B",author="Twin",ownerKey="twin@realmb",
        realm="realmb",ownerVerified=true,class="MAGE",ordinaryComplete=true,
        echoes=Echoes(820002),fingerprint=DPS.GetEchoKey(Echoes(820002))},
    legacy={id="legacy",title="Legacy",author="Twin",class="MAGE",
        ownerVerified=false,ordinaryComplete=true,
        echoes=Echoes(820003),fingerprint=DPS.GetEchoKey(Echoes(820003))},
}
Nexus.BuildCatalog = {
    Summaries=function() return builds end,
    Status=function() return {availableCount=3} end,
}
dofile("core/ViewProjections.lua")
local P = Nexus.ViewProjections
local function Board(category)
    local rows, summary = P.Leaderboard(category,
        {classFilter="ALL",search=""})
    assert(rows and summary and summary.filtered == #rows,
        category.." public count did not match reconciled rows")
    return rows
end
local projectedDummy, projectedLk, combined =
    Board("dummy"), Board("lk"), Board("combined")
assert(#projectedDummy == 3 and #projectedLk == 2 and #combined == 2,
    "Dummy/LK/Combined did not share canonical identity policy")
for _, rows in ipairs({projectedDummy,projectedLk,combined}) do
    local labels = {}
    for _, row in ipairs(rows) do
        assert(not labels[row.displayPlayer],
            "public leaderboard rendered indistinguishable identity labels")
        labels[row.displayPlayer] = true
    end
end

local community, summary = P.Builds({currentClassOnly=false,
    qualifiedOnly=false,scope="all",sortMode="title",page=1})
assert(#community == 3 and summary.filteredTotal == 3
        and summary.displayedCount == 3,
    "Community public counts/paging omitted distinct build records")
local authorLabels = {}
for _, build in ipairs(community) do
    assert(type(build.displayAuthor) == "string"
            and not authorLabels[build.displayAuthor],
        "Community rendered indistinguishable Twin identities")
    authorLabels[build.displayAuthor] = true
end
assert(authorLabels["Twin (legacy/unverified)"],
    "ambiguous Community evidence lacks an explicit diagnostic label")

print("canonical public reconciliation, realm labels, ambiguity shadowing, reload, and Sync -- OK")
