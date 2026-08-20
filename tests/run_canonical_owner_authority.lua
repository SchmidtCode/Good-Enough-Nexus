-- Durable owner authority is derived from the actual realm-qualified
-- transport sender. Display-name resemblance is never ownership proof.
local H = dofile("tests/harness.lua")

local Identity = Nexus.Identity

assert(Identity.CanonicalOwnerFromTransport("Twin-RealmA") == "twin@realma",
    "realm-qualified transport did not produce its canonical owner")
assert(Identity.CanonicalOwnerFromTransport("Twin") == nil,
    "realm-less transport produced durable owner authority")
assert(Identity.TransportOwns("twin@realma", "Twin-RealmA") == true,
    "exact canonical transport owner was not verified")
assert(Identity.TransportOwns("twin@realma", "Twin-RealmB") == false,
    "same-name cross-realm transport gained owner authority")

dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua")
dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua")
dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua")
dofile("core/SyncSession.lua"); dofile("core/Sync.lua")
dofile("core/DpsCapture.lua")

local Codec, Sync, DPS = Nexus.Codec, Nexus.Sync, Nexus.DpsCapture
time = function() return 50000 end
NexusDB = {communityBuilds={},syncTombstones={},dpsCapture={}}
Sync.Init(Codec, {})

local function BuildPacket(sender, id, ownerKey, stamp)
    local payload = {
        id=id,t="Twin Build",a="Twin",o=ownerKey,c="MAGE",m=stamp,
        e={{200100,3,1}},
    }
    return table.concat({"WLRB",sender,id,tostring(stamp),"1/1",
        Codec.Base64Encode(Codec.JSONEncode(payload))}, "|")
end

assert(Sync.HandleIncoming(
    BuildPacket("Twin-RealmA", "twin-a", "twin@realma", 10),
    "Twin-RealmA"), "exact realm-qualified owner build was rejected")
local exact = NexusDB.communityBuilds["twin-a"]
assert(exact and exact.ownerVerified == true
        and exact.ownerKey == "twin@realma",
    "exact realm-qualified owner build was not verified")

assert(Sync.HandleIncoming(
    BuildPacket("Twin-RealmB", "twin-mismatch", "twin@realma", 11),
    "Twin-RealmB"), "cross-realm evidence was not retained")
local mismatch = NexusDB.communityBuilds["twin-mismatch"]
assert(mismatch and mismatch.ownerVerified == false
        and mismatch.ownerKey == nil
        and mismatch.claimedOwnerKey == "twin@realma"
        and mismatch.relaySender == "Twin-RealmB",
    "same-name cross-realm build gained durable owner authority")

local function SummaryPacket(sender, id, ownerKey, stamp)
    local payload = {
        id=id,t="Twin Summary",a="Twin",o=ownerKey,c="MAGE",m=stamp,
        h="1a2b",n=1,
    }
    return table.concat({"WLBI",sender,
        Codec.Base64Encode(Codec.JSONEncode(payload))}, "|")
end

assert(Sync.HandleIncoming(
    SummaryPacket("Twin-RealmA", "summary-a", "twin@realma", 20),
    "Twin-RealmA"), "exact realm-qualified summary was rejected")
local summary = NexusDB.communityBuilds["summary-a"]
assert(summary and summary.ownerVerified == true
        and summary.ownerKey == "twin@realma",
    "exact realm-qualified summary was not verified")

assert(not Sync.HandleIncoming(
    SummaryPacket("Twin-RealmB", "summary-mismatch", "twin@realma", 21),
    "Twin-RealmB"),
    "same-name cross-realm summary was accepted as direct-owner input")
assert(NexusDB.communityBuilds["summary-mismatch"] == nil,
    "same-name cross-realm summary entered durable state")

assert(Sync.HandleIncoming(
    BuildPacket("Twin", "twin-short", "twin@realma", 22), "Twin"),
    "realm-less build evidence was not retained")
local realmLess = NexusDB.communityBuilds["twin-short"]
assert(realmLess and realmLess.ownerVerified == false
        and realmLess.ownerKey == nil,
    "realm-less transport gained current-realm owner authority")

assert(Sync.HandleIncoming(
    BuildPacket("Twin-RealmB", "twin-b", "twin@realmb", 23),
    "Twin-RealmB"), "exact RealmB build was rejected")
assert(NexusDB.communityBuilds["twin-a"].ownerKey == "twin@realma"
        and NexusDB.communityBuilds["twin-b"].ownerKey == "twin@realmb",
    "same-name verified realm builds did not coexist")

assert(not Sync.HandleIncoming(
    BuildPacket("Twin-RealmB", "twin-mismatch", "twin@realmb", 25),
    "Twin-RealmB"),
    "RealmB replaced a retained RealmA owner claim")
assert(NexusDB.communityBuilds["twin-mismatch"].ownerVerified == false
        and NexusDB.communityBuilds["twin-mismatch"].claimedOwnerKey
            == "twin@realma"
        and NexusDB.communityBuilds["twin-mismatch"].relaySender
            == "Twin-RealmB",
    "failed wrong-owner promotion changed retained provenance")
assert(Sync.HandleIncoming(
    BuildPacket("Twin-RealmA", "twin-mismatch", "twin@realma", 25),
    "Twin-RealmA"),
    "the exact claimed owner could not promote retained evidence")
assert(NexusDB.communityBuilds["twin-mismatch"].ownerVerified == true
        and NexusDB.communityBuilds["twin-mismatch"].ownerKey
            == "twin@realma"
        and NexusDB.communityBuilds["twin-mismatch"].claimedOwnerKey == nil,
    "exact claimed-owner promotion did not establish canonical ownership")

assert(Sync.HandleIncoming(
    BuildPacket("Mallory-RealmX", "relayed-twin", "twin@realma", 25),
    "Mallory-RealmX"),
    "ordinary third-party relay evidence was not retained")
assert(NexusDB.communityBuilds["relayed-twin"].ownerVerified == false
        and NexusDB.communityBuilds["relayed-twin"].claimedOwnerKey
            == "twin@realma"
        and NexusDB.communityBuilds["relayed-twin"].relaySender
            == "Mallory-RealmX",
    "ordinary relay unexpectedly gained owner authority")
assert(Sync.HandleIncoming(
    BuildPacket("Twin-RealmA", "relayed-twin", "twin@realma", 25),
    "Twin-RealmA"),
    "exact owner could not promote matching third-party relay evidence")
assert(NexusDB.communityBuilds["relayed-twin"].ownerVerified == true
        and NexusDB.communityBuilds["relayed-twin"].ownerKey
            == "twin@realma",
    "exact owner promotion left relay evidence unverified")

assert(Sync.HandleIncoming(
    BuildPacket("Mallory-RealmX", "relayed-summary", "twin@realma", 30),
    "Mallory-RealmX"),
    "summary-promotion relay evidence was not retained")
local pendingBeforeSummary = Sync.WorkState().pendingReplacements
assert(Sync.HandleIncoming(
    SummaryPacket("Twin-RealmA", "relayed-summary", "twin@realma", 31),
    "Twin-RealmA"),
    "exact owner summary could not supersede relayed evidence")
assert(Sync.WorkState().pendingReplacements == pendingBeforeSummary + 1,
    "exact owner summary did not queue a verified replacement")

NexusDB.communityBuilds["legacy-nil-full"] = {
    id="legacy-nil-full",title="Legacy Nil Full",author="Twin",
    ownerKey="twin@realma",isMine=false,class="MAGE",lastModified=31,
    echoes={{spellId=200100,quality=3,stacks=1}},
}
assert(not Sync.HandleIncoming(
    BuildPacket("Twin-RealmB", "legacy-nil-full", "twin@realmb", 32),
    "Twin-RealmB"),
    "wrong realm promoted a legacy nil-verification owner claim")
assert(Sync.HandleIncoming(
    BuildPacket("Twin-RealmA", "legacy-nil-full", "twin@realma", 32),
    "Twin-RealmA"),
    "exact owner could not refresh a legacy nil-verification claim")
assert(NexusDB.communityBuilds["legacy-nil-full"].ownerVerified == true,
    "fresh exact full packet did not verify the legacy owner claim")

NexusDB.communityBuilds["legacy-nil-summary"] = {
    id="legacy-nil-summary",title="Legacy Nil Summary",author="Twin",
    ownerKey="twin@realma",isMine=false,class="MAGE",lastModified=32,
}
assert(Sync.HandleIncoming(
    SummaryPacket("Twin-RealmA", "legacy-nil-summary", "twin@realma", 33),
    "Twin-RealmA"),
    "exact owner summary could not refresh a legacy nil-verification claim")
assert(NexusDB.communityBuilds["legacy-nil-summary"].ownerVerified == true,
    "fresh exact summary did not verify the legacy owner claim")

assert(Sync.HandleIncoming(
    BuildPacket("Mallory-RealmX", "relayed-delete", "twin@realma", 34),
    "Mallory-RealmX"),
    "delete-promotion relay evidence was not retained")
assert(Sync.HandleIncoming(
    "WLRD|Twin-RealmA|relayed-delete|35|Twin", "Twin-RealmA"),
    "exact owner could not delete its third-party relayed evidence")
assert(NexusDB.communityBuilds["relayed-delete"] == nil
        and NexusDB.syncTombstones["relayed-delete"]
        and NexusDB.syncTombstones["relayed-delete"].ownerKey
            == "twin@realma",
    "relayed-evidence delete did not persist exact owner authority")

assert(Sync.HandleIncoming(
    BuildPacket("Twin-RealmB", "mismatch-delete", "twin@realma", 36),
    "Twin-RealmB"),
    "cross-realm delete fixture evidence was not retained")
assert(not Sync.HandleIncoming(
    "WLRD|Twin-RealmB|mismatch-delete|37|Twin", "Twin-RealmB"),
    "wrong realm deleted a retained RealmA owner claim")
assert(Sync.HandleIncoming(
    "WLRD|Twin-RealmA|mismatch-delete|37|Twin", "Twin-RealmA"),
    "exact claimed owner could not delete cross-realm retained evidence")

assert(not Sync.HandleIncoming(
    BuildPacket("Twin-RealmB", "twin-a", "twin@realmb", 26),
    "Twin-RealmB"),
    "same-name RealmB seized RealmA's verified build ID")
assert(NexusDB.communityBuilds["twin-a"].ownerKey == "twin@realma",
    "cross-realm owner change overwrote RealmA's verified build")

assert(not Sync.HandleIncoming(
    SummaryPacket("Twin-RealmB", "summary-a", "twin@realmb", 27),
    "Twin-RealmB"),
    "same-name RealmB summary seized RealmA's verified build ID")
assert(NexusDB.communityBuilds["summary-a"].ownerKey == "twin@realma",
    "cross-realm summary changed the verified owner")

assert(not Sync.HandleIncoming(
    BuildPacket("Twin-RealmA", "envelope-spoof", "twin@realma", 24),
    "Twin-RealmB"), "realm-mismatched envelope bypassed transport binding")
assert(NexusDB.communityBuilds["envelope-spoof"] == nil,
    "realm-mismatched envelope entered durable state")

assert(Sync.HandleIncoming("WLNP|Twin-RealmA|1.20.0", "Twin-RealmA")
        and Sync.HandleIncoming("WLNP|Twin-RealmB|1.20.1", "Twin-RealmB"),
    "realm-qualified presence fixtures were rejected")
local realmAPeer = Sync.GetPeerInfo("Twin-RealmA")
local realmBPeer = Sync.GetPeerInfo("Twin-RealmB")
assert(realmAPeer and realmBPeer and realmAPeer ~= realmBPeer
        and realmAPeer.version == "1.20.0"
        and realmBPeer.version == "1.20.1",
    "same-name realms collided in known-peer accounting")

UnitName = function() return "LocalTwin" end
GetNormalizedRealmName = function() return "RealmA" end
assert(Sync.HandleIncoming(
        "WLNP|LocalTwin-RealmA|1.20.0", "LocalTwin-RealmA")
        and Sync.HandleIncoming(
            "WLNP|LocalTwin-RealmB|1.20.1", "LocalTwin-RealmB"),
    "local-realm presence fixtures were rejected")
assert(Sync.GetPeerInfo("LocalTwin-RealmA") == nil,
    "exact local realm was retained as a remote peer")
assert(Sync.GetPeerInfo("LocalTwin-RealmB") ~= nil,
    "same-name foreign realm was discarded as local self traffic")
UnitName = function() return "Boganic" end
GetNormalizedRealmName = function() return "Ebonhold" end

DPS.Init({}, Sync)
local function DpsRecord(spellId, ownerKey, realm, dps, stamp)
    local echoes = {{spellId=spellId,stacks=1}}
    return {
        v=7,f=DPS.GetEchoKey(echoes),h=DPS.GetEchoHash(echoes),e=echoes,
        c="dummy",d=dps,u=65,t=stamp,p="Twin",l=80,k="MAGE",
        o=ownerKey,r=realm,
    }
end

local function DeliverDps(sender, transferId, record)
    local encoded = Codec.Base64Encode(Codec.JSONEncode(record))
    local chunkSize = 120
    local total = math.ceil(#encoded / chunkSize)
    local result = false
    for index = 1, total do
        local packet = string.format("WLD2|%s|%s|%d/%d|%s", sender,
            transferId,index,total,encoded:sub(
                (index - 1) * chunkSize + 1,index * chunkSize))
        assert(#packet <= 255, "DPS authority fixture exceeded wire limit")
        result = Sync.HandleIncoming(packet, sender) or result
    end
    return result
end

assert(DeliverDps("Twin-RealmA", "dps-a",
    DpsRecord(200200, "twin@realma", "realma", 25000000, 30)),
    "exact realm-qualified DPS owner was rejected")
assert(DeliverDps("Twin-RealmB", "dps-mismatch",
    DpsRecord(200201, "twin@realma", "realma", 26000000, 31)),
    "same-name cross-realm DPS evidence was not retained")

local rows = DPS.GetDpsBoard("dummy")
local byFingerprint = {}
for _, row in ipairs(rows) do byFingerprint[row.fingerprint] = row end
local exactDps = byFingerprint[DPS.GetEchoKey({{spellId=200200,stacks=1}})]
local mismatchDps = byFingerprint[DPS.GetEchoKey({{spellId=200201,stacks=1}})]
assert(#rows == 2 and exactDps and exactDps.ownerVerified == true
        and exactDps.ownerKey == "twin@realma",
    "cross-realm DPS input displaced the exact RealmA owner record")
assert(mismatchDps and mismatchDps.ownerVerified == false
        and mismatchDps.ownerKey == nil and mismatchDps.realm == "realmb",
    "cross-realm DPS input gained authority or borrowed RealmA storage")

assert(DeliverDps("Twin-RealmB", "dps-b-exact",
    DpsRecord(200201, "twin@realmb", "realmb", 26000000, 31)),
    "later exact RealmB DPS owner could not promote its own evidence")
rows = DPS.GetDpsBoard("dummy")
byFingerprint = {}
for _, row in ipairs(rows) do byFingerprint[row.fingerprint] = row end
local promoted = byFingerprint[DPS.GetEchoKey({{spellId=200201,stacks=1}})]
assert(promoted and promoted.ownerVerified == true
        and promoted.ownerKey == "twin@realmb" and promoted.realm == "realmb",
    "later exact owner did not promote only its matching realm evidence")

assert(DeliverDps("Twin", "dps-short",
    DpsRecord(200202, "twin@realma", "realma", 24000000, 32)),
    "realm-less DPS evidence was not retained")
rows = DPS.GetDpsBoard("dummy")
byFingerprint = {}
for _, row in ipairs(rows) do byFingerprint[row.fingerprint] = row end
local shortDps = byFingerprint[DPS.GetEchoKey({{spellId=200202,stacks=1}})]
assert(shortDps and shortDps.ownerVerified == false
        and shortDps.ownerKey == nil and shortDps.realm == nil,
    "realm-less DPS transport borrowed payload realm authority")

Sync.Init(Codec, {})
DPS.Init({}, Sync)
assert(NexusDB.communityBuilds["twin-a"].ownerVerified == true
        and NexusDB.communityBuilds["twin-b"].ownerVerified == true
        and NexusDB.communityBuilds["twin-short"].ownerVerified == false,
    "reload recomputed build ownership from short-name resemblance")
rows = DPS.GetDpsBoard("dummy")
local verifiedRealms, unverified = {}, 0
for _, row in ipairs(rows) do
    if row.ownerVerified == true then verifiedRealms[row.ownerKey] = true
    else unverified = unverified + 1 end
end
assert(verifiedRealms["twin@realma"] and verifiedRealms["twin@realmb"]
        and unverified == 1,
    "reload collapsed or re-authorized realm-qualified DPS evidence")

local nilAuthority = {
    id="nil-authority",title="Unverified",author="Twin",
    ownerKey="twin@realma",class="MAGE",lastModified=40,
    echoes={{spellId=200300,quality=3,stacks=1}},
}
local relayed, relayWhy = Sync.BroadcastBuild(nilAuthority)
assert(relayed == false and relayWhy == "relay unauthorized",
    "ownerVerified=nil build remained relay-eligible")

local verifiedMissingOwner = {
    id="verified-missing-owner",title="Missing Owner",author="Twin",
    ownerVerified=true,class="MAGE",lastModified=40,
    echoes={{spellId=200302,quality=3,stacks=1}},
}
local missingOwnerRelayed, missingOwnerWhy =
    Sync.BroadcastBuild(verifiedMissingOwner)
assert(missingOwnerRelayed == false and missingOwnerWhy == "relay unauthorized",
    "ownerVerified=true without a canonical key retained relay authority")

local verifiedMismatchedOwner = {
    id="verified-mismatched-owner",title="Mismatched Owner",author="Twin",
    ownerKey="other@realma",ownerVerified=true,class="MAGE",lastModified=40,
    echoes={{spellId=200303,quality=3,stacks=1}},
}
local mismatchedOwnerRelayed, mismatchedOwnerWhy =
    Sync.BroadcastBuild(verifiedMismatchedOwner)
assert(mismatchedOwnerRelayed == false
        and mismatchedOwnerWhy == "relay unauthorized",
    "schema-mismatched verified metadata retained relay authority")

UnitName = function() return "Twin" end
GetNormalizedRealmName = function() return "RealmA" end
local falseLocalAuthority = {
    id="false-local-authority",title="Unverified Local-Looking",author="Twin",
    ownerKey="twin@realma",ownerVerified=false,isMine=true,class="MAGE",
    lastModified=40,echoes={{spellId=200301,quality=3,stacks=1}},
}
local falseLocalRelayed, falseLocalWhy =
    Sync.BroadcastBuild(falseLocalAuthority)
assert(falseLocalRelayed == false and falseLocalWhy == "relay unauthorized",
    "ownerVerified=false build regained authority through isMine")
assert(not Sync.BroadcastDelete(falseLocalAuthority),
    "ownerVerified=false build regained delete authority through isMine")

NexusDB.dpsCapture = {}
Sync.Init(Codec, {})
DPS.Init({}, Sync)
H.sentChatMessages = {}
local injectedEchoes = {{spellId=200304,stacks=1}}
local injected = DpsRecord(
    200304, "twin@realma", "realma", 28000000, 42)
injected.protocolVersion = injected.v
injected.fingerprint = injected.f
injected.loadoutHash = injected.h
injected.echoes = injected.e
injected.category = injected.c
injected.dps = injected.d
injected.duration = injected.u
injected.ts = injected.t
injected.player = injected.p
injected.level = injected.l
injected.class = injected.k
injected.ownerKey = injected.o
injected.realm = injected.r
injected.ownerVerified = true
injected._originVerified = true
assert(DeliverDps("Twin-RealmB", "dps-injected-authority", injected),
    "injected-authority DPS evidence was not retained for inspection")
local injectedStored
for _, row in ipairs(DPS.GetDpsBoard("dummy")) do
    if row.fingerprint == DPS.GetEchoKey(injectedEchoes) then
        injectedStored = row
    end
end
assert(injectedStored and injectedStored.ownerVerified == false,
    "payload-supplied authority flag reached durable DPS state")
for _ = 1, 80 do Sync.OnUpdate(0.2) end
for _, message in ipairs(H.sentChatMessages) do
    assert(not message.text:find("^WLD2|"),
        "payload-supplied DPS authority was automatically re-broadcast")
end

local sentUnverifiedDps, unverifiedDpsWhy =
    Sync.BroadcastDpsRecord(shortDps)
assert(sentUnverifiedDps == false and unverifiedDpsWhy == "owner_sender",
    "realm-less unverified DPS row remained owner-broadcast eligible")
local sentExactDps = Sync.BroadcastDpsRecord(exactDps)
assert(sentExactDps == true,
    "exact verified local-realm DPS row lost owner-broadcast authority")

local ghostEchoes = {{spellId=200400,stacks=1}}
local ghostFingerprint = DPS.GetEchoKey(ghostEchoes)
local ghost = {
    player="Ghost",ownerKey="ghost@realma",realm="realma",
    ownerVerified=false,category="dummy",dps=27000000,duration=65,
    ts=41,level=80,class="MAGE",echoes=ghostEchoes,
    fingerprint=ghostFingerprint,loadoutHash=DPS.GetEchoHash(ghostEchoes),
    protocolVersion=7,
}
NexusDB.dpsCapture = {
    characterBest={dummy={["ghost@realma"]=ghost},lk={}},
    personalBest={},buildBest={},
}
UnitName = function() return "Ghost" end
DPS.Init({}, Sync)
local ghostBucket = DPS.SyncBucket("dummy", "Ghost")
local ghostClaimable = DPS.ResponseBucketClaimInfo(ghostBucket)
assert(ghostClaimable == false and not DPS.LocalOwnsDpsBucket(ghostBucket),
    "unverified same-name DPS row retained response-claim authority")

local malformedEchoes = {{spellId=200401,stacks=1}}
local malformedDps = {
    player="Bob",ownerKey="bob@realma",realm="realmb",
    ownerVerified=true,category="dummy",dps=27500000,duration=65,
    ts=43,level=80,class="MAGE",echoes=malformedEchoes,
    fingerprint=DPS.GetEchoKey(malformedEchoes),
    loadoutHash=DPS.GetEchoHash(malformedEchoes),protocolVersion=7,
}
NexusDB.dpsCapture = {
    characterBest={dummy={["bob@realma"]=malformedDps},lk={}},
    personalBest={},buildBest={},
}
UnitName = function() return "Bob" end
GetNormalizedRealmName = function() return "RealmA" end
DPS.Init({}, Sync)
local malformedBucket = DPS.SyncBucket("dummy", "Bob")
assert(DPS.ResponseBucketClaimInfo(malformedBucket) == false,
    "ownerKey/realm-mismatched DPS row retained response-claim authority")
local malformedSent, malformedWhy = Sync.BroadcastDpsRecord(malformedDps)
assert(malformedSent == false and malformedWhy == "owner_sender",
    "ownerKey/realm-mismatched DPS row remained outbound-authoritative")

assert(DPS.ReceiveRecord({
        v=7,f=malformedDps.fingerprint,h=malformedDps.loadoutHash,
        e=malformedEchoes,c="dummy",d=28000000,u=65,t=44,p="Bob",
        l=80,k="MAGE",o="bob@realma",r="realma",
    }, "Bob-RealmA"),
    "coherent exact DPS owner could not replace mismatched saved metadata")
local coherentDps = DPS.GetCharacterBest("dummy", "Bob")
coherentDps.category = "dummy"
local coherentClaimable = DPS.ResponseBucketClaimInfo(malformedBucket)
assert(coherentClaimable == true,
    "coherent verified DPS row lost response-claim eligibility")
local coherentSent, coherentWhy = Sync.BroadcastDpsRecord(coherentDps)
assert(coherentSent == true,
    "coherent exact-local DPS row lost outbound authority: "
        .. tostring(coherentWhy))

UnitName = function() return "Twin" end
GetNormalizedRealmName = function() return "RealmB" end
assert(not Sync.BroadcastDelete(NexusDB.communityBuilds["summary-a"]),
    "same-name RealmB queued RealmA's owner-only deletion")
assert(NexusDB.communityBuilds["summary-a"]
        and NexusDB.syncTombstones["summary-a"] == nil,
    "cross-realm local delete changed RealmA's durable state")
GetNormalizedRealmName = function() return "RealmA" end
assert(Sync.BroadcastDelete(NexusDB.communityBuilds["summary-a"]),
    "exact local RealmA owner could not queue its deletion")
assert(NexusDB.syncTombstones["summary-a"]
        and NexusDB.syncTombstones["summary-a"].ownerKey
            == "twin@realma",
    "local delete did not persist canonical tombstone authority")

Sync.Init(Codec, {})
H.sentChatMessages = {}
GetNormalizedRealmName = function() return "RealmB" end
assert(Sync.HandleIncoming(
    "WLRQ|Requester|0|0|realm-b-tomb", "Requester"),
    "cross-realm tombstone response request was rejected")
for _ = 1, 160 do Sync.OnUpdate(0.2) end
for _, message in ipairs(H.sentChatMessages) do
    assert(not (message.text:find("^WLRD|")
            and message.text:find("summary%-a")),
        "RealmB re-broadcast RealmA's owner-only tombstone")
end
GetNormalizedRealmName = function() return "RealmA" end

assert(not Sync.HandleIncoming(
    "WLRD|Twin-RealmB|twin-a|100|Twin", "Twin-RealmB"),
    "same-name RealmB transport deleted RealmA's verified build")
assert(NexusDB.communityBuilds["twin-a"] ~= nil,
    "cross-realm delete removed verified RealmA state")

assert(Sync.HandleIncoming(
    "WLRD|Twin-RealmA|twin-a|101|Twin", "Twin-RealmA"),
    "exact RealmA transport could not delete its verified build")
assert(NexusDB.communityBuilds["twin-a"] == nil
        and NexusDB.syncTombstones["twin-a"]
        and NexusDB.syncTombstones["twin-a"].ownerKey == "twin@realma",
    "exact delete did not persist canonical tombstone authority")

Sync.Init(Codec, {})
H.sentChatMessages = {}
assert(Sync.RequestSync(), "canonical claim fixture could not start a request")
for _ = 1, 20 do Sync.OnUpdate(0.2) end
local activeRequestId
for _, message in ipairs(H.sentChatMessages) do
    local wire = message.text:gsub("||", "|")
    activeRequestId = activeRequestId or wire:match(
        "^WLRQ|[^|]+|[^|]+|[^|]+|([^|]+)|")
end
assert(type(activeRequestId) == "string" and activeRequestId ~= "",
    "canonical claim fixture did not expose its active request ID")
assert(not Sync.HandleIncoming(table.concat({"WLRC","Relay-RealmX",
        "Twin-RealmB",activeRequestId,"0","0"}, "|"), "Relay-RealmX"),
    "RealmB claim was accepted against RealmA's active request")
assert(not Sync.HandleIncoming(table.concat({"WLBC","Relay-RealmX",
        "Twin-RealmB",activeRequestId,"B","1","0"}, "|"),
        "Relay-RealmX"),
    "RealmB bucket claim was accepted against RealmA's active request")
assert(not Sync.HandleIncoming(table.concat({"WLBC","Relay-RealmX",
        "Twin",activeRequestId,"B","1","0"}, "|"),
        "Relay-RealmX"),
    "realm-less bucket claim borrowed RealmA request authority")
assert(not Sync.HandleIncoming(table.concat({"WLLC","Relay-RealmX",
        "Twin-RealmB","missing-build",activeRequestId}, "|"),
        "Relay-RealmX"),
    "RealmB loadout claim was accepted against RealmA's active request")
assert(Sync.HandleIncoming(table.concat({"WLLC","Relay-RealmX",
        "Twin-RealmA","missing-build",activeRequestId}, "|"),
        "Relay-RealmX"),
    "exact RealmA request context lost compatible loadout-claim handling")
assert(not Sync.HandleIncoming(
    BuildPacket("Twin-RealmB", "twin-a", "twin@realmb", 100),
    "Twin-RealmB"),
    "cross-realm stale build was accepted against RealmA's tombstone")
assert(not Sync.HandleIncoming(
    SummaryPacket("Twin-RealmB", "twin-a", "twin@realmb", 100),
    "Twin-RealmB"),
    "cross-realm stale summary was accepted against RealmA's tombstone")
assert(not Sync.HandleIncoming(
    "WLRD|Twin-RealmB|twin-a|100|Twin", "Twin-RealmB"),
    "cross-realm stale delete was accepted as RealmA's tombstone duplicate")
assert(not Sync.HandleIncoming(
    BuildPacket("Twin-RealmB", "twin-a", "twin@realma", 102),
    "Twin-RealmB"),
    "same-name RealmB transport resurrected RealmA's tombstoned build")
assert(NexusDB.communityBuilds["twin-a"] == nil,
    "cross-realm resurrection changed durable state after reload")

Nexus.BundledBuilds = {
    schemaVersion=1,catalogVersion="canonical-owner-baseline",
    sourceVersion="test",generatedAt=0,builds={
        ["bundled-owner"]={
            id="bundled-owner",title="Bundled Owner",author="Twin",
            ownerKey="twin@realma",class="MAGE",lastModified=1,postedAt=1,
            echoes={{spellId=200500,quality=3,stacks=1}},
        },
    },
}
Sync.Init(Codec, {})
assert(Sync.HandleIncoming(
    "WLRD|Twin-RealmA|bundled-owner|200|Twin", "Twin-RealmA"),
    "exact canonical owner could not tombstone its trusted bundled build")
assert(NexusDB.syncTombstones["bundled-owner"]
        and NexusDB.syncTombstones["bundled-owner"].ownerKey
            == "twin@realma",
    "bundled delete did not retain canonical tombstone authority")

UnitName = function() return "Relay" end
GetNormalizedRealmName = function() return "RealmX" end
Nexus.BundledBuilds = nil
NexusDB = {
    communityBuilds={
        ["nil-claim-row"]={
            id="nil-claim-row",title="Ambiguous Legacy",author="Bob",
            ownerKey="bob@otherrealm",isMine=false,class="MAGE",
            lastModified=300,
            echoes={{spellId=200600,quality=3,stacks=1}},
        },
    },
    syncTombstones={},dpsCapture={},
}
Sync.Init(Codec, {})
DPS.Init({}, Sync)
H.sentChatMessages = {}
local _, emptyDpsHash = Sync.GetCompatibilityHashes()
assert(Sync.HandleIncoming(table.concat({"WLRQ","Requester-RealmQ",
        "0",emptyDpsHash,"c1-nil-owner-claim","1.20.0"}, "|"),
        "Requester-RealmQ"),
    "nil-owner response-claim fixture was rejected")
for _ = 1, 220 do Sync.OnUpdate(0.2) end
for _, message in ipairs(H.sentChatMessages) do
    assert(not message.text:find("^WLRC|")
            and not message.text:find("^WLBC|")
            and not message.text:find("^WLRB|")
            and not message.text:find("^WLBI|"),
        "relay-ineligible nil owner suppressed an authoritative response")
end

NexusDB = {
    communityBuilds={},dpsCapture={},
    syncTombstones={
        ["foreign-tomb"]={stamp=301,author="Origin",
            ownerKey="origin@realmy",ownerVerified=true},
    },
}
Sync.Init(Codec, {})
DPS.Init({}, Sync)
H.sentChatMessages = {}
local _, tombDpsHash = Sync.GetCompatibilityHashes()
assert(Sync.HandleIncoming(table.concat({"WLRQ","Requester-RealmQ",
        "0",tombDpsHash,"c1-foreign-tomb-claim","1.20.0"}, "|"),
        "Requester-RealmQ"),
    "foreign-tomb response-claim fixture was rejected")
for _ = 1, 220 do Sync.OnUpdate(0.2) end
for _, message in ipairs(H.sentChatMessages) do
    assert(not message.text:find("^WLRC|")
            and not message.text:find("^WLBC|")
            and not message.text:find("^WLRD|"),
        "non-owner foreign tomb suppressed an authoritative response")
end

print("canonical transport owner authority -- OK")
