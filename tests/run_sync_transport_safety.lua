-- Outbound Sync must revalidate the named channel immediately before every
-- send, retain packets while disconnected, and reject newest packets when a
-- bounded queue is full without overwriting older queued traffic.
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")
dofile("core/Sync.lua")

local Sync = Nexus.Sync
local clock = 1000
GetTime = function() return clock end
UnitName = function() return "Alice" end
NexusDB = { communityBuilds={}, syncTombstones={} }
Sync.Init(Nexus.Codec, {})

local function Pump(steps)
    for _ = 1, steps do
        clock = clock + 0.2
        Sync.OnUpdate(0.2)
    end
end

-- The cached slot began as 1. Before the queued packet is sent, the sync
-- channel moves to 7 and General takes slot 1. Raw Sync traffic must follow
-- wrbuildssync, never the stale numeric slot.
H.sentChatMessages = {}
assert(Sync.BroadcastDps("renumbered", "Alice", 1000, 80, "dummy"))
H.joinedChannels[Sync.ChannelName()] = 7
H.joinedChannels.general = 1
Pump(6)
assert(#H.sentChatMessages == 1, "renumbered packet was not sent")
assert(H.sentChatMessages[1].target == 7,
    "cached Sync slot sent raw traffic to a different channel")

-- If the named channel cannot be found or rejoined, the packet stays queued.
assert(Sync.BroadcastDps("retained", "Alice", 1001, 80, "dummy"))
H.joinedChannels = {}
local oldTemporary, oldNamed = JoinTemporaryChannel, JoinChannelByName
JoinTemporaryChannel = function() end
JoinChannelByName = function() end
local sentBefore = #H.sentChatMessages
Pump(6)
local waiting = Sync.WorkState()
assert(#H.sentChatMessages == sentBefore,
    "packet was sent without a validated wrbuildssync channel")
assert(waiting.outbound == 1,
    "packet was discarded when channel validation/reconnect failed")

-- Discovery of the channel at a new slot releases the retained packet.
H.joinedChannels[Sync.ChannelName()] = 9
JoinTemporaryChannel, JoinChannelByName = oldTemporary, oldNamed
Pump(6)
assert(#H.sentChatMessages == sentBefore + 1
    and H.sentChatMessages[#H.sentChatMessages].target == 9,
    "retained packet did not use the newly validated channel slot")
assert(Sync.WorkState().outbound == 0,
    "retained packet remained queued after a successful send")

-- Saturate the documented bulk queue. The explicit policy is to preserve
-- already queued packets and reject the newest packet/batch with a visible
-- counter and false return value.
Sync.Init(Nexus.Codec, {})
H.sentChatMessages = {}
local limits = Sync.WorkState()
assert(type(limits.maxOutboundQueue) == "number"
    and limits.maxOutboundQueue > 0,
    "Sync does not expose an explicit outbound queue bound")
for i = 1, limits.maxOutboundQueue - 1 do
    assert(Sync.BroadcastDps("queued-" .. i, "Alice", 2000 + i, 80, "dummy"),
        "outbound queue rejected a packet before its documented limit")
end
local batchEchoes = {}
for i = 1, 24 do
    batchEchoes[i] = { spellId=200000 + i, quality=3, stacks=2 }
end
assert(not Sync.BroadcastBuild({ id="atomic-batch", title="Atomic Batch",
    author="Alice", class="MAGE", lastModified=1, postedAt=1,
    description=string.rep("bounded ", 20), echoes=batchEchoes }),
    "multi-chunk batch partially entered a nearly full queue")
assert(Sync.WorkState().sending == limits.maxOutboundQueue - 1,
    "rejected multi-chunk batch partially mutated the queue")
assert(Sync.BroadcastDps("queued-final", "Alice", 999998, 80, "dummy"),
    "final available queue slot was not usable after atomic batch rejection")
assert(not Sync.BroadcastDps("rejected-newest", "Alice", 999999, 80, "dummy"),
    "outbound queue silently exceeded its documented limit")
local full = Sync.WorkState()
assert(full.sending == limits.maxOutboundQueue,
    "outbound overflow changed or overwrote the bounded queue")
assert((Sync.Stats().queueOverflowRejected or 0) >= 1,
    "outbound overflow was not recorded explicitly")

Pump(6)
assert(H.sentChatMessages[1]
    and H.sentChatMessages[1].text:find("queued%-1", 1, false),
    "queue overflow overwrote the oldest retained packet")

-- A responder must never publish a WLLC claim when the corresponding WLRB
-- payload was rejected by bulk backpressure. Keep the response pending until
-- capacity is available instead of suppressing every other responder.
Sync.Init(Nexus.Codec, {})
NexusDB.communityBuilds["claim-build"] = {
    id="claim-build", title="Claim Build", author="Alice", class="MAGE",
    lastModified=10, postedAt=10,
    echoes={{spellId=200100, quality=3, stacks=1}},
}
limits = Sync.WorkState()
for i = 1, limits.maxOutboundQueue do
    assert(Sync.BroadcastDps("claim-fill-" .. i, "Alice", 3000 + i,
        80, "dummy"), "failed to fill claim backpressure queue")
end
assert(Sync.HandleIncoming("WLLQ|Requester|claim-build", "Requester"),
    "valid on-demand loadout request was rejected")
assert(Sync.WorkState().pendingLoadouts == 1,
    "on-demand loadout response was not scheduled")
local oldTemporary2, oldNamed2 = JoinTemporaryChannel, JoinChannelByName
H.joinedChannels = {}
JoinTemporaryChannel = function() end
JoinChannelByName = function() end
Sync.OnUpdate(2)
local rejectedResponse = Sync.WorkState()
assert(rejectedResponse.control == 0,
    "loadout claim was queued without an admitted build payload")
assert(rejectedResponse.pendingLoadouts == 1,
    "backpressured loadout response was not retained for retry")
JoinTemporaryChannel, JoinChannelByName = oldTemporary2, oldNamed2

-- Bucket election has the same invariant: WLBC may only be published after
-- every WLRB packet in that bucket has been admitted atomically. Leave room
-- for one packet while scheduling two one-packet builds in the same bucket;
-- the partial admission must be rolled back along with the claim.
Sync.Init(Nexus.Codec, {})
local function TestBuildBucket(id)
    local hash = 5381
    for i = 1, #id do hash = ((hash * 33) + id:byte(i)) % 2147483648 end
    return (hash % 8) + 1
end
local firstBucketId = "bucket-build-a"
local secondBucketId
for i = 1, 100 do
    local candidate = "bucket-build-" .. i
    if TestBuildBucket(candidate) == TestBuildBucket(firstBucketId) then
        secondBucketId = candidate
        break
    end
end
assert(secondBucketId, "test setup could not find two ids in one build bucket")
NexusDB.communityBuilds = {
    [firstBucketId] = {
        id=firstBucketId, title="Bucket Build A", author="Alice", class="MAGE",
        lastModified=11, postedAt=11,
        echoes={{spellId=200101, quality=3, stacks=1}},
    },
    [secondBucketId] = {
        id=secondBucketId, title="Bucket Build B", author="Alice", class="MAGE",
        lastModified=12, postedAt=12,
        echoes={{spellId=200102, quality=3, stacks=1}},
    },
}
limits = Sync.WorkState()
for i = 1, limits.maxOutboundQueue - 1 do
    assert(Sync.BroadcastDps("bucket-fill-" .. i, "Alice", 4000 + i,
        80, "dummy"), "failed to fill bucket backpressure queue")
end
local emptyBuckets = "0,0,0,0,0,0,0,0"
assert(Sync.HandleIncoming("WLRQ|Requester|" .. emptyBuckets .. "|0|req-bucket",
    "Requester"), "valid bucket reconciliation request was rejected")
assert(Sync.WorkState().pendingResponses == 1,
    "bucket reconciliation response was not scheduled")
local oldTemporary3, oldNamed3 = JoinTemporaryChannel, JoinChannelByName
H.joinedChannels = {}
JoinTemporaryChannel = function() end
JoinChannelByName = function() end
Sync.OnUpdate(6)
local rejectedBucket = Sync.WorkState()
assert(rejectedBucket.control == 0,
    "bucket claim was queued without a complete admitted payload")
assert(rejectedBucket.pendingResponses == 1,
    "backpressured bucket response was not retained for retry")
assert(rejectedBucket.sending == limits.maxOutboundQueue - 1,
    "failed bucket admission partially mutated the bulk queue")
JoinTemporaryChannel, JoinChannelByName = oldTemporary3, oldNamed3

print("sync validation, retry retention, overflow, and claim safety -- OK")
