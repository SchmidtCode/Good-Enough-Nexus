-- Explicit mixed-version route matrix. The legacy endpoint is the frozen
-- v1.19.5 wire contract; every new endpoint uses the current Sync module.
local Fixture = dofile("tests/fixtures/better_nexus_v1_19_5.lua")
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")
dofile("core/Sync.lua")

local Sync = Nexus.Sync
local player = "MatrixNew"
UnitName = function() return player end
Nexus.SyncPolicy = {
    Mode=function() return "manual" end,
    Allows=function() return true end,
}

local function Fields(wire)
    local fields = {}
    for value in tostring(wire):gmatch("([^|]+)") do
        fields[#fields + 1] = value
    end
    return fields
end

local function LegacyAccepts(wire)
    local fields = Fields(wire:gsub("||", "|"))
    local code = fields[1]
    if code == "WLRQ" then
        return #fields >= Fixture.packets.WLRQ.minimumFields
            and #fields <= Fixture.packets.WLRQ.maximumFields
    elseif code == "WLNP" then
        return #fields == Fixture.packets.WLNP.fields
    elseif code == "WLBC" then
        return #fields == Fixture.packets.WLBC.fields
    elseif code == "WLRB" then
        return #fields == Fixture.packets.WLRB.fields
    elseif code == "WLD2" then
        return #fields == Fixture.packets.WLD2.fields
    end
    return false -- v1.19.5 safely ignores unknown extension/ACK codes.
end

local function Reset(name, direct)
    player = name
    H.sentChatMessages = {}
    NexusDB = {communityBuilds={}, syncTombstones={}, dpsCapture={},
        settings={syncDirectExperimental=direct == true}}
    Nexus.BuildCatalog.Init(NexusDB, Nexus.BundledBuilds)
    Nexus.DpsCapture = {
        GetLegacySyncHash=function() return "0,0,0,0,0,0,0,0" end,
        GetEnhancedSyncHash=function() return "0,0,0,0,0,0,0,0" end,
        SyncBucketClaimable=function() return false end,
        BroadcastAllBuildBests=function() return 0, true, true end,
    }
    Sync.Init(Nexus.Codec, {})
    Sync.EnsureChannel()
    H.now = H.now + 1.2
    Sync.OnUpdate(1.2) -- discard presence traffic
    H.sentChatMessages = {}
end

local function AddBuild(id)
    local build = {
        id=id, title="Matrix build", author=player, class="MAGE",
        postedAt=100, lastModified=100,
        echoes={{spellId=200100, quality=3, stacks=1}},
    }
    local ok, why = Nexus.BuildCatalog.Put(build)
    assert(ok, "failed to store matrix build: " .. tostring(why))
    return build
end

local function PumpUntilBulk(limit)
    for _ = 1, limit or 160 do
        H.now = H.now + 0.2
        Sync.OnUpdate(0.2)
        for _, sent in ipairs(H.sentChatMessages) do
            local canonical = sent.text:gsub("||", "|")
            if canonical:find("^WLRB|") or canonical:find("^WLTB:") then
                return sent, canonical
            end
        end
    end
end

-- old -> old: the frozen request and response stay on the shared channel.
assert(LegacyAccepts(Fixture.packets.WLRQ.representative),
    "old requester packet is not accepted by the frozen old responder")
assert(LegacyAccepts(Fixture.packets.WLRB.representative),
    "old channel response is not accepted by the frozen old requester")

-- old -> new: no extension means legacy digest semantics and channel bulk.
Reset("NewResponder", true)
AddBuild("old-to-new")
assert(Sync.HandleIncoming(
    "WLRQ|OldRequester|0|0|old-new|1.19.5", "OldRequester"))
local oldNewState = Sync.RequestDiagnostics("OldRequester", "old-new")
assert(oldNewState.pending and oldNewState.digestMode == "legacy"
    and not oldNewState.directCapable,
    "new responder did not classify an old requester as legacy")
local oldNewBulk, oldNewWire = PumpUntilBulk()
assert(oldNewBulk and oldNewBulk.kind == "CHANNEL"
    and LegacyAccepts(oldNewWire),
    "new responder did not send an old-compatible channel response")

-- new -> old: old ignores WLXQ, accepts unchanged WLRQ, and the new requester
-- accepts an unchanged old WLRB channel response.
Reset("NewRequester", true)
assert(Sync.RequestSync())
for _ = 1, 5 do
    H.now = H.now + 1.2
    Sync.OnUpdate(1.2)
end
local sawIgnoredExtension, sawLegacyRequest = false, false
for _, sent in ipairs(H.sentChatMessages) do
    local wire = sent.text:gsub("||", "|")
    if wire:find("^WLXQ|") then
        sawIgnoredExtension = not LegacyAccepts(wire)
    elseif wire:find("^WLRQ|") then
        sawLegacyRequest = LegacyAccepts(wire)
    end
end
assert(sawIgnoredExtension and sawLegacyRequest,
    "new requester did not remain readable to the frozen old peer")
local oldPayload = Nexus.Codec.Base64Encode(Nexus.Codec.JSONEncode({
    id="new-from-old", t="Old response", a="OldResponder", c="MAGE",
    m=101, e={{200100,3,1}},
}))
local oldResponse = "WLRB|OldResponder|new-from-old|101|1/1|" .. oldPayload
assert(LegacyAccepts(oldResponse), "old response fixture changed wire shape")
assert(Sync.HandleIncoming(oldResponse, "OldResponder", "CHANNEL")
    and Nexus.BuildCatalog.Get("new-from-old"),
    "new requester did not accept an old responder's channel data")

-- new -> new, direct disabled: extension enables enhanced comparison but the
-- established channel remains the data route.
Reset("DisabledResponder", false)
AddBuild("new-disabled")
assert(Sync.HandleIncoming(
    "WLXQ|NewRequester|new-disabled-req|1|C0|0,0,0,0,0,0,0,0",
    "NewRequester"))
assert(Sync.HandleIncoming(
    "WLRQ|NewRequester|0|0,0,0,0,0,0,0,0|new-disabled-req|1.96.5",
    "NewRequester"))
local disabledBulk = PumpUntilBulk()
assert(disabledBulk and disabledBulk.kind == "CHANNEL",
    "direct-disabled new peers did not retain channel bulk")

-- new -> new, direct enabled: request-scoped CW2 sends only to the requester,
-- a logical ACK releases state, and no bulk fallback appears.
Reset("DirectResponder", true)
AddBuild("new-direct")
assert(Sync.HandleIncoming(
    "WLXQ|DirectRequester|new-direct-req|1|CW2|0,0,0,0,0,0,0,0",
    "DirectRequester"))
assert(Sync.HandleIncoming(
    "WLRQ|DirectRequester|0|0,0,0,0,0,0,0,0|new-direct-req|1.96.5",
    "DirectRequester"))
local directBulk = PumpUntilBulk()
assert(directBulk and directBulk.kind == "WHISPER"
    and directBulk.target == "DirectRequester",
    "negotiated new peers did not use recipient-specific bulk")
assert(Sync.HandleIncoming(
    "WLAK|DirectRequester|new-direct-req|B|new-direct",
    "DirectRequester"), "new-peer logical ACK was rejected")
H.now = H.now + 13
Sync.OnUpdate(0)
for _, sent in ipairs(H.sentChatMessages) do
    local wire = sent.text:gsub("||", "|")
    assert(not (sent.kind == "CHANNEL"
        and (wire:find("^WLRB|") or wire:find("^WLTB:"))),
        "successful direct response leaked bulk to uninvolved channel peers")
end
assert(Sync.Stats().directAckSuccess == 1
    and Sync.Stats().directFallback == 0,
    "successful direct route did not settle cleanly")

print("sync matrix old-old, old-new, new-old, new-new channel/direct -- OK")
