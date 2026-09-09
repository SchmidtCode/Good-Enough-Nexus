local H = dofile("tests/harness.lua")

dofile("core/DpsCapture.lua")

local DPS = Nexus.DpsCapture
local now = 50000
time = function() return now end
GetServerTime = function() return now end
UnitName = function() return "Relay" end
UnitClass = function() return "Mage", "MAGE" end
UnitLevel = function() return 80 end
GetNormalizedRealmName = function() return "Ebonhold" end

local echoes = {{spellId=200100, stacks=1}}
local fingerprint = DPS.GetEchoKey(echoes)
local build = {
    id="generation-build", title="Generation Build", author="Owner",
    class="MAGE", echoes=echoes, postedAt=1, lastModified=1,
}

local broadcasts = {}
local function reset()
    NexusDB = {
        communityBuilds={[build.id]=build}, syncTombstones={}, dpsCapture={},
    }
    broadcasts = {}
    DPS.Init({}, {
        BroadcastDpsRecord=function(record)
            broadcasts[#broadcasts + 1] = record
            return true
        end,
    })
end

local function record(dps, generation, stamp)
    return {
        v=7, f=fingerprint, h=DPS.GetEchoHash(echoes), e=echoes,
        c="dummy", d=dps, u=65, t=stamp or generation,
        g=generation, p="Owner", k="MAGE", l=80, b=build.id,
        o="owner@ebonhold", r="ebonhold",
    }
end

reset()
assert(DPS.ReceiveRecord(record(31000000, 100), "Owner"),
    "initial owner snapshot was rejected")
local staleHash = DPS.GetSyncHash()
assert(DPS.ReceiveRecord(record(30000000, 200), "Owner"),
    "newer owner generation did not replace the older higher DPS snapshot")
local ownerBoard = DPS.GetDpsBoard("dummy")
assert(ownerBoard[1].dps == 30000000 and ownerBoard[1].generationAt == 200,
    "owner generation was not retained on the canonical row")
assert(DPS.GetSyncHash() ~= staleHash,
    "owner generation did not participate in the sync digest")

reset()
assert(DPS.ReceiveRecord(record(31000000, 100), "Owner"),
    "downstream stale owner snapshot was rejected")
assert(DPS.ReceiveRecord(record(30000000, 200), nil, "legacy-relay"),
    "newer relayed owner generation did not replace stale direct evidence")
local staleAccepted, staleReason = DPS.ReceiveRecord(
    record(32000000, 150), nil, "legacy-relay")
assert(not staleAccepted and staleReason == "not-better-than-existing",
    "older relayed generation rolled back newer owner state")
local downstream = DPS.GetDpsBoard("dummy")
assert(downstream[1].dps == 30000000
    and downstream[1].generationAt == 200
    and downstream[1].legacy == true,
    "downstream row did not preserve generation and local relay trust")

assert(DPS.BroadcastAllBuildBests("0") == 1,
    "relayed owner snapshot was not exportable to the next peer")
assert(#broadcasts == 1 and broadcasts[1].generationAt == 200,
    "next-hop export lost the owner generation")

-- Equivalent replicated state uses evidence strength only after owner,
-- generation, DPS, and exact loadout identity agree. Timestamp ordering must
-- not let a relay downgrade an owner or block a later owner upgrade.
reset()
assert(DPS.ReceiveRecord(record(30000000, 300, 299), nil, "legacy-relay"),
    "equivalent relay seed was rejected")
local relayLegacyDigest = DPS.GetLegacySyncHash()
local relayEnhancedDigest = DPS.GetEnhancedSyncHash()
local relaySeed = DPS.GetDpsBoard("dummy")[1]
assert(DPS.EvidenceClass(relaySeed) == "relay"
    and DPS.IsRelayEvidence(relaySeed)
    and not DPS.IsOwnerEvidence(relaySeed),
    "relay evidence was not classified explicitly")
assert(DPS.ReceiveRecord(record(30000000, 300, 300), "Owner"),
    "owner evidence did not upgrade equivalent relay state")
assert(DPS.GetLegacySyncHash() == relayLegacyDigest,
    "legacy digest changed for evidence-only upgrade")
assert(DPS.GetEnhancedSyncHash() ~= relayEnhancedDigest,
    "enhanced digest ignored evidence/provenance upgrade")
local upgraded = DPS.GetDpsBoard("dummy")[1]
assert(DPS.EvidenceClass(upgraded) == "owner"
    and DPS.IsOwnerEvidence(upgraded)
    and not DPS.IsRelayEvidence(upgraded),
    "relay to owner did not upgrade evidence")

reset()
assert(DPS.ReceiveRecord(record(30000000, 300, 300), "Owner"),
    "equivalent owner seed was rejected")
assert(not DPS.ReceiveRecord(
    record(30000000, 300, 299), nil, "legacy-relay"),
    "relay evidence downgraded equivalent owner state")
assert(DPS.IsOwnerEvidence(DPS.GetDpsBoard("dummy")[1]),
    "owner evidence was lost after an equivalent relay")

reset()
assert(DPS.ReceiveRecord(record(30000000, 400), "Owner"))
local generationLegacyDigest = DPS.GetLegacySyncHash()
local generationEnhancedDigest = DPS.GetEnhancedSyncHash()
assert(DPS.ReceiveRecord(record(30000000, 500), "Owner"),
    "newer equivalent owner generation was rejected")
assert(DPS.GetLegacySyncHash() == generationLegacyDigest,
    "legacy digest changed for generation-only update")
assert(DPS.GetEnhancedSyncHash() ~= generationEnhancedDigest,
    "enhanced digest ignored generation-only update")

local dpsDigest = DPS.GetEnhancedSyncHash()
assert(DPS.ReceiveRecord(record(31000000, 500, 501), "Owner"),
    "same-generation stronger owner record was rejected")
assert(DPS.GetEnhancedSyncHash() ~= dpsDigest,
    "enhanced digest ignored DPS change")
local originalLoadoutDigest = DPS.GetEnhancedSyncHash()
local alternateEchoes = {{spellId=200102, stacks=1}}
local alternateBuild = {
    id="generation-build-alt", title="Alternate Generation Build",
    author="Owner", class="MAGE", echoes=alternateEchoes,
    postedAt=1, lastModified=1,
}
NexusDB = {communityBuilds={
    [build.id]=build, [alternateBuild.id]=alternateBuild,
}, syncTombstones={}, dpsCapture={}}
DPS.Init({}, {BroadcastDpsRecord=function() return true end})
assert(DPS.ReceiveRecord({
    v=7, f=DPS.GetEchoKey(alternateEchoes),
    h=DPS.GetEchoHash(alternateEchoes), e=alternateEchoes,
    c="dummy", d=31000000, u=65, t=501, g=500,
    p="Owner", k="MAGE", l=80, b=alternateBuild.id,
    o="owner@ebonhold", r="ebonhold",
}, "Owner"), "alternate exact loadout record was rejected")
assert(DPS.GetEnhancedSyncHash() ~= originalLoadoutDigest,
    "enhanced digest ignored loadout change")

reset()
assert(DPS.ReceiveRecord(record(30000000, 300, 300), nil, "legacy-relay"),
    "relay to relay seed was rejected")
DPS.ReceiveRecord(record(30000000, 300, 299), nil, "legacy-relay")
assert(DPS.IsRelayEvidence(DPS.GetDpsBoard("dummy")[1]),
    "relay to relay changed evidence class")

reset()
assert(DPS.ReceiveRecord(record(30000000, 300, 300), "Owner"),
    "owner to owner seed was rejected")
DPS.ReceiveRecord(record(30000000, 300, 299), "Owner")
assert(DPS.IsOwnerEvidence(DPS.GetDpsBoard("dummy")[1]),
    "owner to owner changed evidence class")

print("DPS owner generation convergence and multi-hop relay: OK")
