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

Reset(true)
local cw2=Route('cw2-mixed')
cw2.pipeFree=true
assert(Sync.EnqueueLogicalTransfer(Single('cw2-object'),cw2))
assert(Sync.EnqueueLogicalTransfer(Single('legacy-object')))
Pump(30) -- intentionally no ACK: exact CW2 object must fall back
local directCW2,channelCW2,channelLegacy=false,false,false
for _,m in ipairs(H.sentChatMessages) do
    if m.text:find('cw2-object',1,true) then
        assert(m.text:find('^WLTB:') and not m.text:find('|',1,true),
            'CW2 route lost on direct/fallback queue')
        if m.kind=='WHISPER' then directCW2=true else channelCW2=true end
    elseif m.text:find('legacy-object',1,true) then
        assert(not m.text:find('^WLTB:'),'legacy queue was wrapped by CW2 state')
        channelLegacy=m.kind=='CHANNEL'
    end
end
assert(directCW2 and channelCW2 and channelLegacy,'mixed route/fallback test incomplete')
assert(Sync.RequestSync())
local envelope=Sync._EncodeLabBulk('WLD2|Peer|object|1/1|QQ==',true)
assert(Sync.IsDirectBulkWhisper(envelope,'Peer'),'CW2 request did not admit envelope')
assert(not Sync.IsDirectBulkWhisper(envelope,'Forged'),'CW2 sender mismatch accepted')
Sync._outgoingRequest.createdAt=H.now-100000
assert(not Sync.IsDirectBulkWhisper(envelope,'Peer'),'expired CW2 request accepted envelope')
print('mixed CW2/legacy queues, lost ACK fallback and request expiry: OK')

Reset(false)
assert(Sync.EnqueueLogicalTransfer(Single("disabled"), Route("req-disabled")))
Pump(5)
assert(H.sentChatMessages[1] and H.sentChatMessages[1].kind == "CHANNEL",
    "disabled direct transport did not preserve channel delivery")

Reset(true)
assert(Sync.DirectTransportEnabled(), "direct test setting was not retained")
SendChatMessage = function(text, kind, language, target)
    if kind == "WHISPER" then
        if #text > 255 then error("WoW chat rejected an oversized whisper") end
        if text:gsub("||", ""):find("|", 1, true) then
            error("WoW chat rejected an unescaped pipe")
        end
    end
    return originalSend(text, kind, language, target)
end
assert(Sync.EnqueueLogicalTransfer(Single("success"), Route("req-success")))
assert(next(Sync._directTransfers), "eligible transfer did not enter direct state")
Pump(3)
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

-- A later convergence pass can become current while an earlier pass's
-- direct object is still in flight. WLRB/WLD2 intentionally retain their
-- legacy shapes and carry no request ID. Content-bound ACKs match the accepted
-- revision independently of scope rotation. Legacy ACKs remain scope-strict.
Reset(true)
assert(Sync.EnqueueLogicalTransfer(Single("rotated-scope"),
    Route("req-earlier")))
Pump(1)
assert(Sync.HandleIncoming("WLXQ|Peer|req-newer|1|CW1|0", "Peer"),
    "newer request scope fixture was rejected")
assert(not Sync.HandleIncoming("WLAK|Peer|req-newer|B|rotated-scope", "Peer"))
local rotatedDigest = Sync._TransferDigest(Single("rotated-scope"))
assert(not Sync.HandleIncoming("WLA2|Other|req-newer|B|rotated-scope|"
    .. rotatedDigest, "Other"), "wrong recipient content ACK was accepted")
assert(not Sync.HandleIncoming("WLA2|Peer|req-newer|B|rotated-scope|deadbeef-4",
    "Peer"), "wrong content ACK was accepted")
assert(Sync.HandleIncoming(
    "WLA2|Peer|req-newer|B|rotated-scope|" .. rotatedDigest, "Peer"),
    "content-bound ACK after request rotation was rejected")
assert(Sync.Stats().directAckSuccess == 1
    and Sync.Stats().directContentAck == 1,
    "cross-pass logical ACK was not instrumented")
assert(not next(Sync._pendingDirectAcks))
assert(Sync._ObjectDigest("QQ==", "1") ~= Sync._ObjectDigest("QQ==", "2"),
    "build revision was omitted from content identity")

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
local escapedCanonical = canonical:gsub("|", "||")
assert(Sync.IsDirectBulkWhisper(escapedCanonical, "Sender"),
    "Ebonhold's escaped whisper event was not recognized as direct bulk")

UnitName = function() return "Receiver" end
Reset(true)
assert(Sync.RequestSync())
local cw2Canonical=Sync._EncodeLabBulk(canonical,true)
assert(Sync.HandleIncoming(cw2Canonical, "Sender", "WHISPER"),
    "valid direct build was not accepted")
assert(NexusDB.communityBuilds["accepted-build"],
    "accepted direct build did not reach replicated state")
local activeRequestId=Sync._outgoingRequest.requestId
Sync._outgoingRequest.createdAt=H.now-100000
assert(Sync.IsDirectBulkWhisper(cw2Canonical,"Sender"),
    "validated CW2 responder became visible when request aged out")
assert(Sync._AckAcceptedDirect("Sender","B","late-object","WHISPER","digest"),
    "validated CW2 responder could not be ACKed after request aged out")
Pump(5)
local sawLeaseAck=false
for _,sent in ipairs(H.sentChatMessages) do
    local wire=sent.text:gsub("||","|")
    sawLeaseAck=sawLeaseAck or wire:find("WLA2|Receiver|"..activeRequestId
        .."|B|late-object|digest",1,true)~=nil
end
local sentDump={}
for _,sent in ipairs(H.sentChatMessages) do sentDump[#sentDump+1]=sent.text end
assert(sawLeaseAck,"aged CW2 ACK lost its original request scope\n"..table.concat(sentDump,"\n"))
local lease=Sync._cw2ReceivePeers.sender
assert(lease,"validated CW2 responder did not create a bounded lease")
lease.lastSeen=H.now-Sync._enhanced.cw2ReceiveIdleTtl-1
assert(not Sync.IsDirectBulkWhisper(cw2Canonical,"Sender"),
    "inactive CW2 responder remained authorized/hidden")
Pump(4)
local sawAck = false
local reconstructedAck
for _, sent in ipairs(H.sentChatMessages) do
    local wire = sent.text:gsub("||", "|")
    if wire:find("^WLA2|Receiver|")
        and wire:find("|B|accepted%-build|") then
        sawAck = true
        reconstructedAck = wire
    end
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
    assert(not sent.text:gsub("||", "|"):find("^WLA[2K]|"),
        "invalid direct build emitted an ACK")
end

-- A fully reconstructed and validated DPS object that is already dominated
-- by local replicated state is an idempotent transport success. The capture
-- API must still reject the weaker value, but withholding the logical ACK
-- would strand a direct slot until timeout and replay needless channel bulk.
Reset(true)
assert(Sync.RequestSync())
local captureCalls = 0
Nexus.DpsCapture = {
    ReceiveRecord=function(record, ownerSender)
        captureCalls = captureCalls + 1
        assert(record.p == "Sender" and ownerSender == "Sender",
            "duplicate DPS fixture bypassed owner validation")
        return false, "not-better-than-existing"
    end,
}
local duplicateTransferId = "Sender:100:200"
local duplicatePayload = Nexus.Codec.Base64Encode(Nexus.Codec.JSONEncode({
    v=5, p="Sender", c="dummy", d=200, t=100,
}))
assert(Sync.HandleIncoming("WLD2|Sender|" .. duplicateTransferId
    .. "|1/1|" .. duplicatePayload, "Sender", "WHISPER"),
    "validated idempotent DPS merge was treated as transport failure")
Pump(4)
local sawDuplicateAck = false
for _, sent in ipairs(H.sentChatMessages) do
    local wire = sent.text:gsub("||", "|")
    if wire:find("^WLA2|Receiver|")
        and wire:find("|D|" .. duplicateTransferId .. "|", 1, true) then
        sawDuplicateAck = true
    end
end
assert(captureCalls == 1 and sawDuplicateAck,
    "validated idempotent DPS merge did not emit a logical ACK")
assert(Sync.Stats().dpsIdempotentAccepted == 1
    and Sync.Stats().dpsRecordRejected == 0,
    "idempotent DPS transport outcome was counted as a capture rejection")

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

-- Replay the ACK emitted by the real receiver against the sender's actual
-- encoded transfer, under a different request ID and after extension expiry.
UnitName = function() return "Sender" end
Reset(true)
assert(Sync.EnqueueLogicalTransfer({canonical},
    {requester="Receiver", requestId="original-request", chatWhisper=true}))
Pump(1)
assert(Sync.HandleIncoming(reconstructedAck, "Receiver"),
    "real receiver content ACK did not match sender wire bytes")
H.now = H.now + 13
Sync.OnUpdate(0)
assert(Sync.Stats().directFallback == 0,
    "accepted content ACK still triggered a timeout fallback")

print("direct disabled/success/failure/lost-ACK/disconnect fallback: OK")
