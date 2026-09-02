local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")
dofile("core/Sync.lua")

local Sync = Nexus.Sync
UnitName = function() return "Local" end
Nexus.SyncPolicy = {
    Mode=function() return "manual" end,
    Allows=function() return true end,
}
Nexus.DpsCapture = {
    GetLegacySyncHash=function() return "111" end,
    GetEnhancedSyncHash=function() return "222" end,
}
NexusDB = {communityBuilds={}, syncTombstones={}, dpsCapture={}, settings={}}
Sync.Init(Nexus.Codec, {})
Sync.EnsureChannel()

H.now = H.now + 1.2
Sync.OnUpdate(1.2) -- drain presence
H.sentChatMessages = {}
assert(Sync.RequestSync())
for _ = 1, 4 do
    H.now = H.now + 1.2
    Sync.OnUpdate(1.2)
end

local extension, request
for _, sent in ipairs(H.sentChatMessages) do
    local wire = sent.text:gsub("||", "|")
    if wire:sub(1, 5) == "WLXQ|" then extension = wire end
    if wire:sub(1, 5) == "WLRQ|" then request = wire end
end
assert(extension and request,
    "current request did not emit separate extension and legacy request packets")
local extensionFields, requestFields = {}, {}
for value in extension:gmatch("([^|]+)") do
    extensionFields[#extensionFields + 1] = value
end
for value in request:gmatch("([^|]+)") do
    requestFields[#requestFields + 1] = value
end
assert(#requestFields == 6 and requestFields[4] == "111",
    "WLRQ no longer carries the six-field legacy DPS digest")
assert(#extensionFields == 6 and extensionFields[4] == "1"
    and extensionFields[5] == "C0" and extensionFields[6] == "222",
    "WLXQ did not carry request-scoped capability/enhanced state")
assert(requestFields[5] == extensionFields[3],
    "WLXQ was not scoped to its WLRQ request id")

assert(Sync.HandleIncoming("WLXQ|EnhancedPeer|enh-1|1|CW1|222",
    "EnhancedPeer"))
assert(Sync.HandleIncoming("WLRQ|EnhancedPeer|0|111|enh-1|1.19.5",
    "EnhancedPeer"))
local enhanced = Sync.RequestDiagnostics("EnhancedPeer", "enh-1")
assert(enhanced.pending and enhanced.extension
    and enhanced.digestMode == "enhanced" and enhanced.directCapable,
    "extension-before-request did not select enhanced reconciliation")

assert(Sync.HandleIncoming("WLXQ|DisabledPeer|disabled-1|1|C0|222",
    "DisabledPeer"))
assert(Sync.HandleIncoming("WLRQ|DisabledPeer|0|111|disabled-1|1.19.5",
    "DisabledPeer"))
local disabled = Sync.RequestDiagnostics("DisabledPeer", "disabled-1")
assert(disabled.pending and disabled.digestMode == "enhanced"
    and not disabled.directCapable,
    "direct-disabled current peer did not use enhanced channel reconciliation")

assert(Sync.HandleIncoming("WLRQ|LegacyPeer|0|111|legacy-1|1.19.5",
    "LegacyPeer"))
local legacy = Sync.RequestDiagnostics("LegacyPeer", "legacy-1")
assert(legacy.pending and not legacy.extension
    and legacy.digestMode == "legacy" and not legacy.directCapable,
    "unknown peer was not treated as legacy")

assert(Sync.HandleIncoming("WLRQ|ReorderedPeer|0|111|reverse-1|1.19.5",
    "ReorderedPeer"))
assert(Sync.HandleIncoming("WLXQ|ReorderedPeer|reverse-1|1|CW1|222",
    "ReorderedPeer"))
local reordered = Sync.RequestDiagnostics("ReorderedPeer", "reverse-1")
assert(reordered.pending and reordered.extension
    and reordered.digestMode == "enhanced" and reordered.directCapable,
    "request-before-extension ordering did not upgrade pending reconciliation")

local stats = Sync.Stats()
assert(stats.enhancedRequests == 2 and stats.legacyRequests == 2,
    "legacy/enhanced request instrumentation is wrong: "
        .. tostring(stats.legacyRequests) .. "/"
        .. tostring(stats.enhancedRequests))

local malformedBefore = stats.malformedRejected
assert(not Sync.HandleIncoming("WLXQ|BadPeer|bad|2|CW1|222", "BadPeer"))
assert(not Sync.HandleIncoming("WLXQ|BadPeer|bad|1|AW1|222", "BadPeer"))
assert(not Sync.HandleIncoming("WLXQ|BadPeer|bad|1|CW1|not-a-hash", "BadPeer"))
assert(not Sync.HandleIncoming("WLXQ|BadPeer|bad|1|CW1", "BadPeer"))
assert(not Sync.HandleIncoming("WLXQ|BadPeer|bad|1|CW1|222|extra", "BadPeer"))
assert(not Sync.HandleIncoming("WLXQ|BadPeer|bad|1|CW1|222", "OtherPeer"))
assert(not Sync.HandleIncoming("WLXQ|Bad Peer|bad|1|CW1|222", "Bad Peer"))
assert(not Sync.HandleIncoming("WLXQ|BadPeer|" .. string.rep("x", 97)
    .. "|1|CW1|222", "BadPeer"))
assert(Sync.Stats().malformedRejected == malformedBefore + 8,
    "malformed extension packets did not fail closed")

assert(Sync.HandleIncoming("WLXQ|DuplicatePeer|dup-1|1|CW1|222",
    "DuplicatePeer"))
assert(Sync.HandleIncoming("WLXQ|DuplicatePeer|dup-1|1|CW1|222",
    "DuplicatePeer"), "identical duplicate extension was not idempotent")
assert(not Sync.HandleIncoming("WLXQ|DuplicatePeer|dup-1|1|CW1|333",
    "DuplicatePeer"), "conflicting duplicate extension was accepted")
assert(Sync._FindRequestExtension("DuplicatePeer", "dup-1").enhancedDpsHash
    == "222", "conflicting duplicate changed cached request state")

for i = 1, 8 do
    assert(Sync.HandleIncoming(string.format(
        "WLXQ|BoundedPeer|bound-%d|1|C0|222", i), "BoundedPeer"))
end
assert(not Sync.HandleIncoming("WLXQ|BoundedPeer|bound-9|1|C0|222",
    "BoundedPeer"), "per-sender request-extension bound was exceeded")

assert(Sync.HandleIncoming("WLXQ|ExpiringPeer|expire-1|1|CW1|222",
    "ExpiringPeer"))
H.now = H.now + 31
Sync.PruneTransientState(H.now)
assert(not Sync.RequestDiagnostics("ExpiringPeer", "expire-1").extension,
    "expired request extension remained usable")

-- Equal legacy and equal enhanced peers both settle without response traffic.
NexusDB = {communityBuilds={}, syncTombstones={}, dpsCapture={}, settings={}}
Sync.Init(Nexus.Codec, {})
local buildHash = Sync.GetCompatibilityHashes()
assert(Sync.HandleIncoming("WLRQ|QuietLegacy|" .. buildHash
    .. "|111|quiet-old|1.19.5", "QuietLegacy"))
H.now = H.now + 2
Sync.OnUpdate(2)
assert(not Sync.RequestDiagnostics("QuietLegacy", "quiet-old").pending,
    "equal legacy peer did not reach a quiet synchronized state")

assert(Sync.HandleIncoming("WLXQ|QuietEnhanced|quiet-new|1|CW1|222",
    "QuietEnhanced"))
assert(Sync.HandleIncoming("WLRQ|QuietEnhanced|" .. buildHash
    .. "|111|quiet-new|1.19.5", "QuietEnhanced"))
H.now = H.now + 2
Sync.OnUpdate(2)
assert(not Sync.RequestDiagnostics("QuietEnhanced", "quiet-new").pending,
    "equal enhanced peer did not reach a quiet synchronized state")

local extensionCount = 0
for _ in pairs(Sync._requestExtensions) do extensionCount = extensionCount + 1 end
for index = extensionCount + 1, Sync._enhanced.maxExtensions do
    local sender = "GlobalPeer" .. tostring(index)
    assert(Sync.HandleIncoming("WLXQ|" .. sender .. "|global-"
        .. tostring(index) .. "|1|C0|222", sender))
end
assert(not Sync.HandleIncoming(
    "WLXQ|GlobalOverflow|global-overflow|1|C0|222", "GlobalOverflow"),
    "global request-extension bound was exceeded")

print("request-scoped WLXQ negotiation and legacy WLRQ compatibility: OK")
