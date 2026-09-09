-- Deterministic fanout model for one requested logical transfer. `peers`
-- includes the sender, requester, and every uninvolved channel subscriber.
local peerCounts = {10, 50, 100, 250}
local chunkCounts = {1, 20, 100, 200}
local changedRows = {1, 10, 100}

print("peers,chunks,channel_tx,channel_bulk_rx,direct_tx,direct_bulk_rx,direct_uninvolved_rx,avoided_rx")
for _, peers in ipairs(peerCounts) do
    for _, chunks in ipairs(chunkCounts) do
        local channelTx = chunks
        local channelRx = chunks * (peers - 1)
        local directTx = chunks
        local directRx = chunks
        local directUninvolved = 0
        local avoided = channelRx - directRx
        assert(channelTx == directTx,
            "recipient routing must not change pacing or packet count")
        assert(directUninvolved == 0,
            "successful recipient routing leaked bulk to uninvolved peers")
        assert(avoided == chunks * (peers - 2),
            "fanout reduction model is inconsistent")
        print(table.concat({peers, chunks, channelTx, channelRx, directTx,
            directRx, directUninvolved, avoided}, ","))
    end
end

for _, rows in ipairs(changedRows) do
    local channelSerializations = rows
    local directSerializations = rows
    assert(channelSerializations == directSerializations,
        "route selection changed sender serialization work")
end

local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")
dofile("core/Sync.lua")
local Sync = Nexus.Sync
UnitName = function() return "FanoutSender" end
Nexus.SyncPolicy = {
    Mode=function() return "manual" end,
    Allows=function() return true end,
}
NexusDB = {communityBuilds={}, syncTombstones={}, dpsCapture={},
    settings={syncDirectExperimental=true}}
Sync.Init(Nexus.Codec, {})
Sync.EnsureChannel()
H.now = H.now + 1.2
Sync.OnUpdate(1.2)
H.sentChatMessages = {}

local directChunks = {}
for i = 1, 200 do
    directChunks[i] = string.format(
        "WLRB|FanoutSender|large-transfer|1|%d/200|QQ==", i)
end
assert(Sync.EnqueueLogicalTransfer(directChunks,
    {requester="Target", requestId="fanout-1", chatWhisper=true}))
assert(Sync.RequestSync())
H.now = H.now + 1.2
Sync.OnUpdate(1.2)
assert(H.sentChatMessages[1].kind == "CHANNEL"
    and H.sentChatMessages[1].text:find("^WLXQ"),
    "control traffic was starved behind direct bulk")
assert(Sync.WorkState().sending >= 200
    and Sync.WorkState().sending <= Sync.WorkState().maxOutboundQueue,
    "direct bulk queue escaped its existing hard bound")

Sync.Init(Nexus.Codec, {})
NexusDB.settings.syncDirectExperimental = true
for i = 1, 40 do
    assert(Sync.EnqueueLogicalTransfer({string.format(
        "WLRB|FanoutSender|channel-backlog-%d|1|1/1|QQ==", i)}))
end
assert(Sync.EnqueueLogicalTransfer({
    "WLRB|FanoutSender|priority-direct|1|1/1|QQ=="},
    {requester="PriorityTarget", requestId="priority-direct",
        chatWhisper=true}))
H.sentChatMessages = {}
H.now = H.now + 1.2
Sync.OnUpdate(1.2)
assert(H.sentChatMessages[1] and H.sentChatMessages[1].kind == "WHISPER",
    "accepted direct work was starved behind channel bulk")

Sync.Init(Nexus.Codec, {})
NexusDB.settings.syncDirectExperimental = true
H.sentChatMessages = {}
Nexus.DpsCapture = {
    GetLegacySyncHash=function() return "1,1,1,1,1,1,1,1" end,
    GetEnhancedSyncHash=function() return "1,1,1,1,1,1,1,1" end,
    SyncBucketClaimable=function() return true end,
    BroadcastAllBuildBests=function()
        return 0, true, true
    end,
}
local fairnessBuildHash = Sync.GetCompatibilityHashes()
for i = 1, 16 do
    local peer = "ControlPeer" .. i
    assert(Sync.HandleIncoming("WLRQ|" .. peer .. "|"
        .. fairnessBuildHash .. "|0|control-" .. i .. "|1.19.5", peer),
        "could not schedule a control-producing response")
end
for _ = 1, 200 do
    H.now = H.now + 0.1
    Sync.OnUpdate(0.1)
end
assert(Sync.WorkState().control >= 10,
    "could not build a sustained control-plane backlog")
assert(Sync.EnqueueLogicalTransfer({
    "WLRB|FanoutSender|control-fairness|1|1/1|QQ=="},
    {requester="FairnessTarget", requestId="control-fairness",
        chatWhisper=true}))
for _ = 1, 6 do
    H.now = H.now + 1.2
    Sync.OnUpdate(1.2)
end
local fairnessDirectSent = false
for _, message in ipairs(H.sentChatMessages) do
    local wire = message.text:gsub("||", "|")
    if message.kind == "WHISPER"
        and message.target == "FairnessTarget"
        and wire:find("^WLRB|FanoutSender|control%-fairness|") then
        fairnessDirectSent = true
    end
end
assert(fairnessDirectSent,
    "direct work was indefinitely starved by control-plane backlog")
Nexus.DpsCapture = nil

Sync.Init(Nexus.Codec, {})
NexusDB.settings.syncDirectExperimental = true
for i = 1, 8 do
    assert(Sync.EnqueueLogicalTransfer({string.format(
        "WLRB|FanoutSender|peer-cap-%d|1|1/1|QQ==", i)},
        {requester="BoundedTarget", requestId="peer-cap-" .. i,
            chatWhisper=true}))
end
local ninth, ninthWhy = Sync.EnqueueLogicalTransfer({
    "WLRB|FanoutSender|peer-cap-9|1|1/1|QQ=="},
    {requester="BoundedTarget", requestId="peer-cap-9",
        chatWhisper=true})
assert(not ninth and ninthWhy == "sync queue full",
    "full direct state silently leaked the ninth object onto the channel")
local directStateCount = 0
for _ in pairs(Sync._directTransfers) do
    directStateCount = directStateCount + 1
end
assert(directStateCount == 8,
    "per-peer direct logical-transfer bound changed")
H.now = H.now + 1.2
Sync.OnUpdate(1.2)
assert(H.sentChatMessages[#H.sentChatMessages].kind == "WHISPER",
    "bounded direct queue did not begin draining")
assert(Sync.HandleIncoming(
    "WLAK|BoundedTarget|peer-cap-1|B|peer-cap-1", "BoundedTarget"),
    "logical ACK did not free a bounded direct slot")
assert(Sync.EnqueueLogicalTransfer({
    "WLRB|FanoutSender|peer-cap-9|1|1/1|QQ=="},
    {requester="BoundedTarget", requestId="peer-cap-9",
        chatWhisper=true}),
    "direct response did not resume after an ACK freed capacity")

NexusDB.settings.syncDirectExperimental = false
Sync.Init(Nexus.Codec, {})
local oversized = {}
for i = 1, Sync.WorkState().maxOutboundQueue + 1 do
    oversized[i] = "WLRB|FanoutSender|cap-probe|1|1/1|QQ=="
end
assert(not Sync.EnqueueLogicalTransfer(oversized),
    "outbound queue admitted a batch beyond its hard cap")

print("fanout matrix 10/50/100/250 peers x 1/20/100/200 chunks: OK")
