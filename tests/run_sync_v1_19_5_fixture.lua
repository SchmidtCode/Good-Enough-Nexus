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
