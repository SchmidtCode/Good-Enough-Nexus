local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")
dofile("core/Sync.lua")

local Sync = Nexus.Sync
local originalSend = SendChatMessage
UnitName = function() return "Local" end
Nexus.SyncPolicy = {
    Mode=function() return "manual" end,
    Allows=function() return true end,
}

local function Reset(enabled)
    H.sentChatMessages = {}
    NexusDB = {communityBuilds={}, syncTombstones={}, dpsCapture={},
        settings={syncDirectExperimental=enabled == true}}
    SendChatMessage = originalSend
    Sync.Init(Nexus.Codec, {})
    Sync.EnsureChannel()
    -- Drain the presence announcement so each case observes only its transfer.
    H.now = H.now + 1.2
    Sync.OnUpdate(1.2)
    H.sentChatMessages = {}
end

local function Route(requestId)
    return {requester="Peer", requestId=requestId, chatWhisper=true}
end

local function Pump(count)
    for _ = 1, count do
        H.now = H.now + 1.2
        Sync.OnUpdate(1.2)
    end
end

local function Single(id)
    return {"WLRB|Local|" .. id .. "|1|1/1|QQ=="}
end

Reset(false)
assert(Sync.EnqueueLogicalTransfer(Single("disabled"), Route("req-disabled")))
Pump(1)
assert(H.sentChatMessages[1] and H.sentChatMessages[1].kind == "CHANNEL",
    "disabled direct transport did not preserve channel delivery")

Reset(true)
assert(Sync.DirectTransportEnabled(), "direct test setting was not retained")
assert(Sync.EnqueueLogicalTransfer(Single("success"), Route("req-success")))
assert(next(Sync._directTransfers), "eligible transfer did not enter direct state")
Pump(1)
assert(H.sentChatMessages[1] and H.sentChatMessages[1].kind == "WHISPER"
    and H.sentChatMessages[1].target == "Peer",
    "eligible logical transfer was not sent to its recipient: "
        .. tostring(H.sentChatMessages[1] and H.sentChatMessages[1].kind)
        .. "/" .. tostring(H.sentChatMessages[1]
            and H.sentChatMessages[1].target))
assert(not Sync.HandleIncoming("WLAK|Other|req-success|B|success", "Other"),
    "ACK from the wrong character was accepted")
assert(not Sync.HandleIncoming("WLAK|Peer|wrong-request|B|success", "Peer"),
    "ACK for the wrong request was accepted")
assert(not Sync.HandleIncoming("WLAK|Peer|req-success|B|missing", "Peer"),
    "ACK for a nonexistent transfer was accepted")
assert(Sync.HandleIncoming("WLAK|Peer|req-success|B|success", "Peer"),
    "matching logical ACK was rejected")
assert(Sync.Stats().directAckSuccess == 1,
    "matching logical ACK was not instrumented")

Reset(true)
SendChatMessage = function(text, kind, language, target)
    if kind == "WHISPER" then error("simulated whisper API failure") end
    return originalSend(text, kind, language, target)
end
assert(Sync.EnqueueLogicalTransfer(Single("failure"), Route("req-failure")))
Pump(1)
assert(#H.sentChatMessages == 0,
    "failed direct attempt leaked a successful send")
Pump(1)
assert(H.sentChatMessages[1] and H.sentChatMessages[1].kind == "CHANNEL",
    "immediate direct failure did not fall back to the channel")
assert(Sync.Stats().directImmediateFailure == 1
    and Sync.Stats().directFallback == 1,
    "immediate failure/fallback instrumentation is wrong")

Reset(true)
assert(Sync.EnqueueLogicalTransfer(Single("lost-ack"), Route("req-lost")))
Pump(1)
assert(H.sentChatMessages[1].kind == "WHISPER")
H.now = H.now + 13
Sync.OnUpdate(0)
Pump(1)
assert(H.sentChatMessages[2] and H.sentChatMessages[2].kind == "CHANNEL",
    "lost ACK did not replay the logical transfer on the channel")
assert(Sync.Stats().directAckTimeout == 1
    and Sync.Stats().directFallback == 1,
    "lost ACK timeout/fallback instrumentation is wrong")

Reset(true)
assert(Sync.EnqueueLogicalTransfer(Single("expired-state"),
    Route("req-expired-state")))
H.now = H.now + 601
Sync.PruneTransientState(H.now)
assert(not next(Sync._directTransfers)
    and Sync.Stats().directFallback == 1,
    "unsent direct state did not expire into bounded channel fallback")
Pump(1)
assert(H.sentChatMessages[1]
    and H.sentChatMessages[1].kind == "CHANNEL",
    "expired direct state did not retain the legacy correctness path")

Reset(true)
assert(Sync.EnqueueLogicalTransfer(Single("redirect"),
    {requester="Bad Target", requestId="req-redirect", chatWhisper=true}))
Pump(1)
assert(H.sentChatMessages[1]
    and H.sentChatMessages[1].kind == "CHANNEL",
    "invalid target-redirection metadata escaped to whisper transport")

Reset(true)
local whisperCalls = 0
SendChatMessage = function(text, kind, language, target)
    if kind == "WHISPER" then
        whisperCalls = whisperCalls + 1
        if whisperCalls == 2 then error("simulated disconnect") end
    end
    return originalSend(text, kind, language, target)
end
local twoChunks = {
    "WLRB|Local|disconnect|1|1/2|QQ==",
    "WLRB|Local|disconnect|1|2/2|Qg==",
}
assert(Sync.EnqueueLogicalTransfer(twoChunks, Route("req-disconnect")))
Pump(2)
Pump(2)
local channelChunks = 0
for _, sent in ipairs(H.sentChatMessages) do
    if sent.kind == "CHANNEL" and sent.text:find("disconnect", 1, true) then
        channelChunks = channelChunks + 1
    end
end
assert(channelChunks == 2,
    "mid-transfer disconnect did not replay the complete logical transfer")

-- Receiver ACKs only after a real canonical transfer reconstructs, validates,
-- and is accepted into replicated state.
UnitName = function() return "Sender" end
Reset(false)
assert(Sync.BroadcastBuild({
    id="accepted-build", title="Accepted", author="Sender", class="MAGE",
    postedAt=100, lastModified=100,
    echoes={{spellId=200100, quality=3, stacks=1}},
}))
Pump(1)
local canonical
for _, sent in ipairs(H.sentChatMessages) do
    if sent.text:find("accepted%-build") then
        canonical = sent.text:gsub("||", "|")
    end
end
assert(canonical, "could not produce canonical build fixture")

UnitName = function() return "Receiver" end
Reset(true)
assert(Sync.RequestSync())
assert(Sync.HandleIncoming(canonical, "Sender", "WHISPER"),
    "valid direct build was not accepted")
assert(NexusDB.communityBuilds["accepted-build"],
    "accepted direct build did not reach replicated state")
Pump(4)
local sawAck = false
for _, sent in ipairs(H.sentChatMessages) do
    local wire = sent.text:gsub("||", "|")
    if wire:find("^WLAK|Receiver|")
        and wire:find("|B|accepted%-build$") then sawAck = true end
end
assert(sawAck, "accepted direct build did not emit a logical ACK")
local acceptedBefore = NexusDB.communityBuilds["accepted-build"]
Sync.HandleIncoming(canonical, "Sender", "CHANNEL")
assert(NexusDB.communityBuilds["accepted-build"] == acceptedBefore,
    "duplicate direct plus fallback delivery changed canonical build state")

Reset(true)
assert(Sync.RequestSync())
local invalid = canonical:gsub("|[^|]+$", "|not_base64")
assert(not Sync.HandleIncoming(invalid, "Sender", "WHISPER"),
    "invalid direct build was accepted")
Pump(4)
for _, sent in ipairs(H.sentChatMessages) do
    assert(not sent.text:gsub("||", "|"):find("^WLAK|"),
        "invalid direct build emitted an ACK")
end

Reset(true)
assert(Sync.RequestSync())
assert(not Sync.HandleIncoming(
    "WLRB|Sender|partial-direct|1|1/2|QQ==", "Sender", "WHISPER"))
assert(Sync.WorkState().buildInflight == 1,
    "direct partial did not enter bounded inflight state")
H.now = H.now + 301
Sync.OnUpdate(0)
assert(Sync.WorkState().buildInflight == 0,
    "disconnected direct partial did not expire")

print("direct disabled/success/failure/lost-ACK/disconnect fallback: OK")
