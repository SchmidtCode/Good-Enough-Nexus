local H = dofile("tests/harness.lua")

dofile("core/Codec.lua")
dofile("core/DpsWireValidator.lua")
dofile("core/Sync.lua")
dofile("core/DpsCapture.lua")

local Sync = Nexus.Sync
local DPS = Nexus.DpsCapture
local Codec = Nexus.Codec

local now = 50000
local uptime = 1000
time = function()
    return now
end
GetTime = function()
    return uptime
end
UnitName = function()
    return "Receiver"
end
UnitClass = function()
    return "Mage", "MAGE"
end
UnitLevel = function()
    return 80
end
GetNormalizedRealmName = function()
    return "Ebonhold"
end

local db
Nexus.BuildCatalog = {
    Init = function() end,
    Get = function(id)
        return db and db.communityBuilds and db.communityBuilds[id]
    end,
}

local function reset(builds)
    db = {
        communityBuilds = builds or {},
        syncTombstones = {},
        dpsCapture = {},
    }
    NexusDB = db
    Sync.Init(Nexus.Codec, {})
    DPS.Init({}, Sync)
end

local echoes = {
    { id = 1001, rank = 4 },
    { id = 1002, rank = 4 },
}
local fingerprint = DPS.GetEchoKey(echoes)
local payload = {
    v = 6,
    f = fingerprint,
    h = DPS.GetEchoHash(echoes),
    e = echoes,
    c = "lk",
    d = 24000000,
    u = 20,
    t = now,
    p = "OlderPeer",
    k = "MAGE",
    l = 80,
}

local function dps2Packets(sender, transfer, record, chunkSize)
    local encoded = Codec.Base64Encode(Codec.JSONEncode(record))
    chunkSize = chunkSize or 180
    local total = math.ceil(#encoded / chunkSize)
    local packets = {}
    for index = 1, total do
        local start = (index - 1) * chunkSize + 1
        local chunk = encoded:sub(start, start + chunkSize - 1)
        packets[index] = table.concat({
            "WLD2",
            sender,
            transfer,
            string.format("%d/%d", index, total),
            chunk,
        }, "|")
    end
    return packets
end

local function sendDps2(sender, transfer, record)
    local accepted
    for _, packet in ipairs(dps2Packets(sender, transfer, record)) do
        accepted = Sync.HandleIncoming(packet, sender) or accepted
    end
    return accepted
end

reset()
assert(Nexus.DpsWireValidator.Validate(payload, {
    localPlayer = "OlderPeer",
    samePeer = function(a, b) return a == b end,
    ownerMatches = function() return true end,
    echoKey = DPS.GetEchoKey,
    echoHash = DPS.GetEchoHash,
}), "20-second LK record failed wire validation")

assert(sendDps2("OlderPeer", "OlderPeer:50001:lk", payload),
    "older LK WLD2 record was rejected")
local lkBoard = DPS.GetDpsBoard("lk")
assert(#lkBoard == 1, "older LK WLD2 record did not reach the leaderboard")
assert(lkBoard[1].duration == 20, "older LK duration was not preserved")

reset()
assert(sendDps2("RelayPeer", "RelayPeer:50002:lk", payload),
    "relayed older WLD2 record was rejected")
local relayedBoard = DPS.GetDpsBoard("lk")
assert(#relayedBoard == 1, "relayed older WLD2 record did not reach the leaderboard")
assert(relayedBoard[1].legacy == true,
    "relayed older WLD2 record was not marked as legacy evidence")

local legacyBuild = {
    id = "legacy-build",
    title = "Legacy Loadout",
    author = "OldPeer",
    class = "MAGE",
    echoes = echoes,
    postedAt = 100,
    lastModified = 100,
}
legacyBuild.fingerprintHash = DPS.GetEchoHash(legacyBuild.echoes)
reset({ [legacyBuild.id] = legacyBuild })

-- Historical v6 WLD2 payloads carried only the build ID and Echo hash.
-- They omitted exact Echo, fingerprint, and class fields, and used zero when
-- duration/timestamp metadata was unavailable. A synced exact build provides
-- the missing loadout evidence, so this row should still import as unverified.
local compactV6 = {
    v = 6,
    h = legacyBuild.fingerprintHash,
    c = "dummy",
    d = 25500000,
    u = 0,
    t = 0,
    p = "OlderWinner",
    l = 80,
    b = legacyBuild.id,
}
assert(sendDps2("RelayPeer", "RelayPeer:50003:dummy", compactV6),
    "compact v6 relayed WLD2 record was rejected")
local compactBoard = DPS.GetDpsBoard("dummy")
assert(#compactBoard == 1,
    "compact v6 relayed WLD2 record did not reach the leaderboard")
assert(compactBoard[1].legacy == true,
    "compact v6 relayed WLD2 record was not marked as legacy evidence")
assert(DPS.GetEchoKey(compactBoard[1].echoes) == fingerprint,
    "compact v6 relay did not hydrate exact Echoes from its synced build")

reset()
assert(not sendDps2("RelayPeer", "RelayPeer:50004:dummy", compactV6),
    "compact v6 relay without its exact build was accepted")
assert(Sync.Stats().lastDpsRejectReason == "legacy-build-unavailable",
    "missing-build rejection reason was not exposed")

reset({ [legacyBuild.id] = legacyBuild })
local mismatchedV6 = {}
for key, value in pairs(compactV6) do mismatchedV6[key] = value end
mismatchedV6.h = "deadbeef"
assert(not sendDps2("RelayPeer", "RelayPeer:50005:dummy", mismatchedV6),
    "compact v6 relay with a mismatched build hash was accepted")
assert(Sync.Stats().lastDpsRejectReason == "legacy-build-hash-mismatch",
    "build-hash rejection reason was not exposed")

-- A dropped chat chunk must be recoverable from the next convergence pass.
-- Keep the partial transfer long enough to merge a retransmission that loses
-- a different chunk, while allowing the quiet partial to trigger that pass.
reset({ [legacyBuild.id] = legacyBuild })
H.sentChatMessages = {}
assert(Sync.RequestSync(), "retry convergence did not start")
uptime = uptime + 1.2
Sync.OnUpdate(1.2)
local retryPackets = dps2Packets(
    "RelayPeer", "RelayPeer:50006:dummy", compactV6, 40)
assert(#retryPackets >= 4, "retry fixture needs a multi-chunk DPS record")
for index = 1, #retryPackets - 1 do
    Sync.HandleIncoming(retryPackets[index], "RelayPeer")
end
assert(Sync.WorkState().dpsInflight == 1,
    "partial DPS transfer was not retained")
uptime = uptime + 61
Sync.OnUpdate(61)
uptime = uptime + 1.2
Sync.OnUpdate(1.2)
assert(Sync.WorkState().dpsInflight == 1,
    "partial DPS transfer expired before the retry pass")
local requestCount = 0
for _, message in ipairs(H.sentChatMessages) do
    if message.text:find("^WLRQ") then requestCount = requestCount + 1 end
end
assert(requestCount >= 2,
    "quiet partial DPS transfer blocked the next convergence request")
for index = 1, #retryPackets do
    if index ~= #retryPackets - 1 then
        Sync.HandleIncoming(retryPackets[index], "RelayPeer")
    end
end
assert(#DPS.GetDpsBoard("dummy") == 1,
    "two lossy convergence passes did not reconstruct the DPS record")

reset({ [legacyBuild.id] = legacyBuild })
local legacyPacket = table.concat({
    "WLDS",
    "OldPeer",
    legacyBuild.id,
    "OldPeer",
    "25000000",
    "80",
    "dummy",
}, "|")
assert(Sync.HandleIncoming(legacyPacket, "OldPeer"), "legacy WLDS record was rejected")
local legacyBoard = DPS.GetDpsBoard("dummy")
assert(#legacyBoard == 1, "legacy WLDS record did not reach the leaderboard")
assert(legacyBoard[1].legacy == true, "legacy WLDS record was not marked as legacy evidence")
assert(legacyBoard[1].generationAt == 0,
    "metadata-free legacy record did not use generation zero")
assert(DPS.BroadcastAllBuildBests("0") == 1,
    "legacy WLDS record could not continue through the current mesh")

local beforeSpoof = #legacyBoard
local spoofPacket = table.concat({
    "WLDS",
    "OldPeer",
    legacyBuild.id,
    "Victim",
    "99999999",
    "80",
    "dummy",
}, "|")
assert(not Sync.HandleIncoming(spoofPacket, "OldPeer"), "legacy WLDS spoof was accepted")
assert(#DPS.GetDpsBoard("dummy") == beforeSpoof, "legacy WLDS spoof changed the leaderboard")

print("sync legacy leaderboard compatibility: OK")
