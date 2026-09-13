-- Offline regression against Better Nexus tag v1.19.5, commit
-- d36a09f06be198dfb76cd1cc82bf437444f60cb2.

local Fixture = dofile("tests/fixtures/better_nexus_v1_19_5.lua")
local H = dofile("tests/harness.lua")

dofile("core/Codec.lua")
dofile("core/Sync.lua")

local Sync = Nexus.Sync
local clock = 4000
GetTime = function() return clock end
time = function() return 50000 end
UnitName = function() return "FixtureLocal" end
UnitClass = function() return "Mage", "MAGE" end
UnitLevel = function() return 80 end
GetNormalizedRealmName = function() return "Ebonhold" end

NexusDB = {
    communityBuilds = {},
    syncTombstones = {},
    dpsCapture = {},
}
Sync.Init(Nexus.Codec, {})

local function MalformedCount()
    return tonumber(Sync.Stats().malformedRejected) or 0
end

local function ExpectNotMalformed(packet, sender, label)
    local before = MalformedCount()
    local ok, result = pcall(Sync.HandleIncoming, packet, sender)
    assert(ok, label .. " raised an error: " .. tostring(result))
    assert(MalformedCount() == before, label .. " changed the malformed count")
    return result
end

local function ExpectMalformed(packet, sender, label)
    local before = MalformedCount()
    local ok, result = pcall(Sync.HandleIncoming, packet, sender)
    assert(ok, label .. " raised an error: " .. tostring(result))
    assert(result == false, label .. " was accepted")
    assert(MalformedCount() == before + 1,
        label .. " did not report one malformed packet")
end

local unknown = Fixture.packets.unknown
assert(unknown.ignored, "fixture no longer describes unknown codes as ignored")
assert(ExpectNotMalformed(unknown.wire, "FuturePeer", "unknown packet") == false,
    "v1.19.5 unknown packet was not ignored")
assert(not Sync.IsKnownPeer("FuturePeer"),
    "unknown packet marked its sender as a Nexus peer")

local request = Fixture.packets.WLRQ
assert(request.minimumFields == 2 and request.maximumFields == 6,
    "frozen WLRQ field-count contract changed")
assert(ExpectNotMalformed(request.minimum, "LegacyBare", "two-field WLRQ") == true,
    "v1.19.5 two-field WLRQ was rejected")
assert(ExpectNotMalformed(request.representative, "LegacyPeer", "six-field WLRQ") == true,
    "v1.19.5 six-field WLRQ was rejected")
ExpectMalformed(request.tooMany, "LegacyPeer", "seven-field WLRQ")

local presence = Fixture.packets.WLNP
assert(presence.fields == 3, "frozen WLNP field-count contract changed")
assert(ExpectNotMalformed(presence.representative, "PresencePeer",
    "three-field WLNP") == true, "v1.19.5 WLNP was rejected")

local bucketClaim = Fixture.packets.WLBC
assert(bucketClaim.fields == 7, "frozen WLBC field-count contract changed")
assert(ExpectNotMalformed(bucketClaim.representative, "ClaimPeer",
    "seven-field WLBC") == true, "v1.19.5 WLBC was rejected")

local build = Fixture.packets.WLRB
assert(build.fields == 6, "frozen WLRB field-count contract changed")
ExpectNotMalformed(build.representative, "BuildPeer", "six-field WLRB")
assert(Sync.WorkState().buildInflight == 1,
    "six-field WLRB did not enter the legacy chunk path")
ExpectMalformed(build.tooFew, "BuildPeer", "five-field WLRB")
ExpectMalformed(build.tooMany, "BuildPeer", "seven-field WLRB")

local dpsTransfer = Fixture.packets.WLD2
assert(dpsTransfer.fields == 5, "frozen WLD2 field-count contract changed")
ExpectNotMalformed(dpsTransfer.representative, "DpsPeer", "five-field WLD2")
assert(Sync.WorkState().dpsInflight == 1,
    "five-field WLD2 did not enter the legacy chunk path")
ExpectMalformed(dpsTransfer.tooFew, "DpsPeer", "four-field WLD2")
ExpectMalformed(dpsTransfer.tooMany, "DpsPeer", "six-field WLD2")

print("v1.19.5 packet field counts and unknown-code behavior: OK")

NexusDB = {
    communityBuilds = {},
    syncTombstones = {},
    dpsCapture = Fixture.NewDpsCapture(),
}
dofile("core/DpsCapture.lua")
local DPS = Nexus.DpsCapture
DPS.Init({}, Sync)

assert(type(DPS.GetLegacySyncHash) == "function",
    "DPS.GetLegacySyncHash is required for v1.19.5 reconciliation")
local actualDigest = DPS.GetLegacySyncHash()
assert(actualDigest == Fixture.dps.expectedDigest, string.format(
    "v1.19.5 DPS digest mismatch: expected %s, got %s",
    Fixture.dps.expectedDigest, tostring(actualDigest)))

print("v1.19.5 literal legacy DPS digest: OK")

-- Real saved state with generation/provenance unknown to old clients must
-- still reach quiet reconciliation using the frozen legacy digest.
local oldDigest = actualDigest
local enhancedBefore = DPS.GetEnhancedSyncHash()
local saved = Fixture.NewDpsCapture()
saved.characterBest.dummy.alpha.generationAt = 999
saved.characterBest.dummy.alpha.evidence = "relay"
saved.characterBest.dummy.alpha.legacy = true
NexusDB.dpsCapture = saved
dofile("core/DpsCapture.lua") -- independent module state, as on another client
DPS = Nexus.DpsCapture
DPS.Init({}, Sync)
assert(DPS.GetLegacySyncHash() == oldDigest)
assert(DPS.GetEnhancedSyncHash() ~= enhancedBefore)
Sync.Init(Nexus.Codec, {})
Sync.EnsureChannel()
H.sentChatMessages = {}
for pass = 1, 3 do
    local id = "real-state-quiet-" .. pass
    local buildHash = Sync.GetCompatibilityHashes()
    assert(Sync.HandleIncoming("WLRQ|LegacyPeer|" .. buildHash .. "|"
        .. oldDigest .. "|" .. id .. "|1.19.5", "LegacyPeer"))
    for _ = 1, 30 do clock = clock + 1.2; Sync.OnUpdate(1.2) end
    assert(not Sync.RequestDiagnostics("LegacyPeer", id).pending,
        "real equivalent legacy state retained response work")
end
assert(Sync.ResponseStats().dpsSerializations == 0,
    "generation/evidence differences caused repeated legacy serialization")
for _, sent in ipairs(H.sentChatMessages) do
    assert(not sent.text:find("^WLD2"), "quiet legacy pass sent DPS bulk")
end
print("real saved-state legacy generation/evidence differences stay quiet: OK")

-- Actual owner serializer output must satisfy the frozen five-field chunk
-- grammar, retain the exact evidence, and remain on the legacy channel.
NexusDB.dpsCapture = {}
DPS.Init({}, Sync)
local echoes = {{spellId=200100, stacks=1, quality=3}}
local record = {
    player="FixtureLocal", category="dummy", class="MAGE", level=80,
    dps=12345678, duration=65, ts=49000, generationAt=49000,
    echoes=echoes, fingerprint=DPS.GetEchoKey(echoes),
    loadoutHash=DPS.GetEchoHash(echoes), ownerKey="fixturelocal@ebonhold",
    realm="ebonhold", buildId="frozen-owner-build", protocolVersion=5,
}
H.sentChatMessages = {}
assert(Sync.BroadcastDpsRecord(record), "real owner serialization failed")
for _ = 1, 100 do clock = clock + 1.2; Sync.OnUpdate(1.2) end
local chunks, total = {}, nil
for _, sent in ipairs(H.sentChatMessages) do
    if sent.text:find("^WLD2") then
        assert(sent.kind == "CHANNEL" and #sent.text <= 255)
        local wire = sent.text:gsub("||", "|")
        local sender, id, index, count, body = wire:match(
            "^WLD2|([^|]+)|([^|]+)|(%d+)/(%d+)|([A-Za-z0-9+/=]+)$")
        assert(sender == "FixtureLocal" and id == "FixtureLocal:49000:12345678",
            "outgoing WLD2 changed the frozen header/identifier grammar")
        index, count = tonumber(index), tonumber(count)
        assert(index >= 1 and index <= count and count <= 999)
        assert(not total or total == count)
        assert(not chunks[index], "duplicate outgoing chunk")
        chunks[index], total = body, count
    end
end
assert(total and #chunks == total, "outgoing WLD2 was incomplete")
local decoded = Nexus.Codec.JSONDecode(Nexus.Codec.Base64Decode(table.concat(chunks)))
assert(decoded.v == 5 and decoded.p == record.player and decoded.c == "dummy"
    and decoded.d == record.dps and decoded.u == 65 and decoded.t == 49000
    and decoded.h == record.loadoutHash and decoded.f == record.fingerprint
    and decoded.e[1].spellId == 200100 and decoded.e[1].count == 1,
    "outgoing canonical DPS payload lost its exact owner evidence: "
        .. Nexus.Codec.JSONEncode(decoded))
print("real outgoing WLD2 matches frozen legacy envelope and chunk contract: OK")
