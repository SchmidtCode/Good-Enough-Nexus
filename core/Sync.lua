-- Nexus: core/Sync.lua v2.1
-- Peer-to-peer sharing for Nexus Builds.
--
-- Login starts a slow convergence sync that repeats until the local mesh state
-- is stable. Valid build and DPS updates are always accepted; exact Echo lists
-- are included in sync responses rather than fetched only when a menu is opened.
--
-- SHARING IS AUTOMATIC. Builds go out when you post or edit, and in
-- response to any peer sync request.
--
-- WIRE PROTOCOL (| separated; pipe escaped to || on send):
--   WLRQ|<sender>|<buildhash>|<dpshash>|<requestId> -- state request
--   WLRC|<sender>|<requester>|<requestId>|<buildhash>|<dpshash> -- claim
--   WLRB|<sender>|<id>|<m>|<idx>/<total>|<b64>  -- build chunk
--   WLRD|<sender>|<id>|<stamp>                   -- delete notification
--
-- PAYLOAD FORMAT (compact, ~65% smaller than verbose):
--   { id, t=title, a=author, c=class, m=lastModified,
--     d=description(omitted if empty), e=[[spellId,quality,stacks],...] }
--
-- ANTI-SPAM:
--   • Conservative paced queued sends; full loadouts sync in-band
--   • Eight build and DPS hash buckets: resend only changed subsets
--   • Responder claims: identical peers elect one sender; unique peers contribute
--   • 2s answer spacing between completed peer responses
--   • Hot-build window (120s): a build posted while no peer is listening
--     is still included in the next BroadcastMine so the peer catches it
--     on their next Sync Now
--   • Max 999 chunks per build (enforced before queuing)

Nexus = Nexus or {}
local Sync = {}
Nexus.Sync = Sync

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------

local SYNC_CHANNEL    = "wrbuildssync"
local CODE_BUILD      = "WLRB"
local CODE_INDEX      = "WLBI" -- lightweight build summary, no Echo list
local CODE_LOADOUT_REQ= "WLLQ" -- request one exact loadout by build id
local CODE_LOADOUT_CLAIM="WLLC" -- one peer claims an on-demand loadout response
local CODE_REQUEST    = "WLRQ"
local CODE_CLAIM      = "WLRC" -- legacy whole-state responder claim
local CODE_BUCKET_CLAIM = "WLBC" -- per-bucket mesh claim; divides work across peers
local CODE_DELETE     = "WLRD"
local CODE_DPS        = "WLDS" -- legacy build-id DPS
local CODE_DPS2       = "WLD2" -- exact-set DPS chunks
local CODE_PRESENCE   = "WLNP" -- lightweight Nexus peer/version presence
local CHAT_LIMIT      = 255    -- WoW SendChatMessage hard cap
local CHAT_SAFETY     = 8      -- conservative margin
local MAX_BYTES       = 32768  -- refuse builds larger than this
local SEND_INTERVAL   = 1.10   -- conservative channel pacing; avoids server chat spam/mutes
local RECEIVE_WINDOW  = 60     -- compatibility/status timer; receiving is always enabled
local INFLIGHT_GRACE  = 30     -- seconds to finish an interrupted chunk transfer
local REQUEST_COOLDOWN = 6     -- min seconds between our own Sync Now presses
local ANSWER_COOLDOWN  = 2     -- minimum gap between completed peer responses
local CLAIM_DELAY_MIN  = 0.35  -- deterministic responder-election delay
local CLAIM_DELAY_MAX  = 1.75
local BUCKET_CLAIM_MAX = 5.50 -- wide deterministic window lets different peers win different buckets
local BUCKET_SETTLE    = 1.50 -- allow a winning claim to propagate before payload queueing
local HOT_WINDOW       = 120   -- seconds a just-posted build is re-included in answers
local JOIN_RETRY_INTERVAL = 10
local JOIN_MAX_ATTEMPTS   = 30
local THROTTLE_PAUSE      = 8     -- pause all Nexus transport after a server throttle notice
local THROTTLE_SLOW_TIME  = 45    -- temporarily use extra-safe pacing after a throttle
local AUTO_SYNC_DELAY      = 6
local AUTO_SYNC_MIN_PASS    = 60  -- allow throttled peers time to begin/drain large responses
local AUTO_SYNC_QUIET       = 15  -- require a real quiet period before judging a pass stable
local AUTO_SYNC_MAX_PASSES  = 0   -- retained for diagnostics; convergence now ends only when stable

------------------------------------------------------------------------
-- Module state
------------------------------------------------------------------------

local Codec, Adapter
local channelIndex
local sendQueue      = {}
local sendQueueHead  = 1
local controlQueue   = {} -- tiny election/control packets; always drain before bulk chunks
local controlQueueHead = 1
local inflight       = {}
local dpsInflight    = {}   -- "sender:id" -> { chunks, total, t0, lastMod }
local seenRemoteIds  = {}   -- id -> lastModified we already hold
local tombstones     = {}   -- id -> stamp; never resurrect
local hotBuilds      = {}   -- id -> { build, t }; recently posted, include in answers
local ticker         = 0
local throttlePauseUntil = 0
local throttleSlowUntil  = 0
local lastTransportAttempt = -math.huge
local transportFilterInstalled = false
local joinRetryTicker = 0
local joinAttempts   = 0
local receiveWindowUntil = 0
local lastRequestAt  = -math.huge
local lastAnsweredAt = -math.huge
local pendingResponses = {} -- requester:requestId -> deferred response candidate
local pendingLoadouts = {}  -- requester:buildId -> staggered on-demand response
local requestedLoadouts = {} -- buildId -> last recovery request time
local legacyRecoveryQueue = {} -- incomplete summaries learned from older peers
local legacyRecoveryHead = 1
local legacyRecoveryTicker = 0
local lastSyncNewCount = 0
local autoSyncPending = false
local autoSyncElapsed = 0
local autoConverge = { active=false, pass=0, stable=0, started=0, lastInbound=0, buildHash=nil, dpsHash=nil }
local Now, MyName
local knownPeers = {} -- normalized player name -> { name, version, lastSeen }

local function NormalizePeerName(name)
    name = tostring(name or ""):gsub("%s+", "")
    name = name:match("^([^%-]+)") or name
    return name:lower()
end

local function MarkPeer(name, version)
    if not name or name == "" then return end
    local me = MyName and MyName() or ""
    if NormalizePeerName(name) == NormalizePeerName(me) then return end
    local key = NormalizePeerName(name)
    if key == "" then return end
    local peer = knownPeers[key] or {}
    peer.name = tostring(name):match("^([^%-]+)") or tostring(name)
    if version and version ~= "" then peer.version = tostring(version) end
    peer.lastSeen = Now and Now() or ((GetTime and GetTime()) or 0)
    knownPeers[key] = peer
end

function Sync.GetPeerInfo(name)
    local peer = knownPeers[NormalizePeerName(name)]
    if not peer then return nil end
    local now = Now and Now() or ((GetTime and GetTime()) or 0)
    if peer.lastSeen and now - peer.lastSeen > 7200 then return nil end
    return peer
end

function Sync.IsKnownPeer(name) return Sync.GetPeerInfo(name) ~= nil end

local stats = {
    sent=0, received=0, duplicatesSkipped=0,
    malformedRejected=0, ignoredOutsideWindow=0,
    oversizeDropped=0, updated=0, skippedUpToDate=0,
}

------------------------------------------------------------------------
-- Diagnostic log
------------------------------------------------------------------------

local eventLog = {}
local LOG_CAP  = 160
local LOG_TRIM_AT = 200
local logSeq   = 0

local function LogEvent(cat, fmt, ...)
    logSeq = logSeq + 1
    local ok, text = pcall(string.format, fmt, ...)
    if not ok then text = tostring(fmt) end
    eventLog[#eventLog+1] = { seq=logSeq, t=(GetTime and GetTime()) or 0,
        cat=cat, text=text }
    -- Trim in one occasional batch instead of shifting the table on every
    -- sync message once the cap is reached. Large peer syncs stay smooth.
    if #eventLog > LOG_TRIM_AT then
        local keep = {}
        local first = #eventLog - LOG_CAP + 1
        for i = first, #eventLog do keep[#keep + 1] = eventLog[i] end
        eventLog = keep
    end
end
Sync.LogEvent  = LogEvent
function Sync.EventLog()  return eventLog end
function Sync.ClearLog()  eventLog = {}; logSeq = 0 end
function Sync.LogRaw(e)   LogEvent("RX", "%s", tostring(e)) end
function Sync.RawLog()    return eventLog end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

Now = function() return (GetTime and GetTime()) or 0 end
MyName = function() return (UnitName and UnitName("player")) or "?" end

local function EscapedLen(s)
    return #s + select(2, s:gsub("|", ""))
end

-- djb2 hash of the caller's library so peers can skip sends when already
-- up to date. Input: { [id] = { lastModified=N }, ... }
local BUILD_BUCKETS = 8
local function BuildBucket(id)
    local text = tostring(id or "")
    local h = 5381
    for i = 1, #text do h = ((h * 33) + text:byte(i)) % 2147483648 end
    return (h % BUILD_BUCKETS) + 1
end

local function SplitHashes(value)
    local out = {}
    local i = 1
    for part in tostring(value or ""):gmatch("([^,]+)") do out[i] = part; i = i + 1 end
    return out
end

local function TombStamp(value)
    if type(value) == "table" then return tonumber(value.stamp) or 0 end
    return tonumber(value) or 0
end

local function TombAuthor(value)
    return type(value) == "table" and tostring(value.author or "") or ""
end

local function LibraryHash(builds)
    local buckets = {}
    for i = 1, BUILD_BUCKETS do buckets[i] = {} end
    for id, b in pairs(builds or {}) do
        local bucket = BuildBucket(id)
        local complete = (type(b.echoes) == "table" and #b.echoes > 0) and "F" or "S"
        local fp = tostring(b.fingerprintHash or b.fingerprint or "0")
        buckets[bucket][#buckets[bucket]+1] = id..":"..tostring(b.lastModified or b.postedAt or 0)..":"..complete..":"..fp
    end
    for id, tomb in pairs(tombstones or {}) do
        local bucket = BuildBucket(id)
        buckets[bucket][#buckets[bucket]+1] = "!"..id..":"..tostring(TombStamp(tomb))..":"..TombAuthor(tomb)
    end
    local hashes = {}
    for bucket = 1, BUILD_BUCKETS do
        table.sort(buckets[bucket])
        local h = 5381
        for _, text in ipairs(buckets[bucket]) do
            for i = 1, #text do h = ((h * 33) + text:byte(i)) % 2147483648 end
        end
        hashes[bucket] = #buckets[bucket] > 0 and string.format("%x", h) or "0"
    end
    return table.concat(hashes, ",")
end

local function CurrentBuildHash()
    return LibraryHash(NexusDB and NexusDB.communityBuilds or {})
end

local function CurrentDpsHash()
    local D = Nexus.DpsCapture
    if D and D.GetSyncHash then
        local ok, value = pcall(D.GetSyncHash)
        if ok and value then return tostring(value) end
    end
    return "0"
end

local function StableDelay(text)
    local h = 5381
    text = tostring(text or "")
    for i = 1, #text do h = ((h * 33) + text:byte(i)) % 1000003 end
    local span = CLAIM_DELAY_MAX - CLAIM_DELAY_MIN
    return CLAIM_DELAY_MIN + (h % 1000) / 999 * span
end

-- Compact payload: short field names + echo arrays instead of objects.
-- Cuts a 69-echo build from ~4100 bytes b64 down to ~1400 bytes b64
-- (8 chunks instead of 23).
local function CompactEncode(build)
    local e = {}
    for _, echo in ipairs(build.echoes or {}) do
        -- 4th array slot is optional and omitted for ordinary Echoes (a Lua
        -- table constructor with a trailing nil is indistinguishable from
        -- one without it -- #e stays 3), so this is byte-for-byte identical
        -- to the old wire shape for every build that has no locked Echoes,
        -- and an older Nexus peer decoding a build that does simply never
        -- looks at index 4 and is unaffected.
        e[#e+1] = { tonumber(echo.spellId), tonumber(echo.quality) or 0,
                    math.max(1, tonumber(echo.stacks) or 1), echo.locked and 1 or nil }
    end
    return {
        id = build.id,
        t  = build.title,
        a  = build.author,
        c  = build.class,
        m  = tonumber(build.lastModified) or tonumber(build.postedAt) or 0,
        d  = (type(build.description) == "string" and build.description ~= "")
             and build.description or nil,
        e  = e,
        x  = build.autoDps and 1 or nil,
        -- build link URL (optional; admin-set reference to external page)
        lk = (type(build.link) == "string" and build.link ~= "") and build.link or nil,
    }
end

-- Reverse compact -> standard shape (used on receive)
local function CompactDecode(data)
    if type(data) ~= "table" then return nil end
    -- Support both compact (t/a/c/m/e) and legacy verbose (title/author/...)
    local title  = data.t or data.title
    local author = data.a or data.author
    local class  = data.c or data.class
    local lastMod = tonumber(data.m or data.lastModified or data.postedAt) or 0
    local rawE   = data.e or data.echoes
    if not (data.id and title and type(rawE) == "table") then return nil end
    local echoes = {}
    for _, e in ipairs(rawE) do
        local spellId, quality, stacks, locked
        if type(e) == "table" then
            -- compact array form [spellId, quality, stacks, locked(optional)]
            if e[1] then
                spellId = tonumber(e[1])
                quality = tonumber(e[2]) or 0
                stacks  = math.max(1, tonumber(e[3]) or 1)
                locked  = (e[4] == 1) or nil
            else
                -- verbose object form (legacy)
                spellId = tonumber(e.spellId)
                quality = tonumber(e.quality) or 0
                stacks  = math.max(1, tonumber(e.stacks) or 1)
                locked  = e.locked and true or nil
            end
        end
        if spellId and spellId > 0 then
            echoes[#echoes+1] = { spellId=spellId, quality=quality, stacks=stacks, locked=locked }
        end
    end
    if #echoes == 0 then return nil end
    return {
        id          = tostring(data.id),
        title       = tostring(title):sub(1, 120),
        author      = type(author) == "string" and author:sub(1, 80) or "Unknown",
        class       = type(class) == "string" and class or nil,
        description = type(data.d or data.description) == "string"
                      and (data.d or data.description):sub(1, 4000) or "",
        lastModified = lastMod,
        postedAt     = tonumber(data.postedAt) or lastMod,
        echoes       = echoes,
        autoDps      = data.x == 1 or data.autoDps == true,
        link         = (type(data.lk) == "string" and data.lk ~= "") and data.lk or nil,
    }
end

------------------------------------------------------------------------
-- Channel
------------------------------------------------------------------------

local function FindSyncChannel()
    if not GetChannelList then return nil end
    local all = { GetChannelList() }
    for i = 1, #all, 2 do
        local idx  = tonumber(all[i])
        local name = all[i+1]
        if idx and idx > 0 and type(name) == "string"
            and name:lower() == SYNC_CHANNEL then
            return idx
        end
    end
    return nil
end

local function HideChannelFromChat()
    if not NUM_CHAT_WINDOWS or not ChatFrame_RemoveChannel then return end
    for i = 1, NUM_CHAT_WINDOWS do
        local f = _G["ChatFrame"..i]
        if f then pcall(ChatFrame_RemoveChannel, f, SYNC_CHANNEL) end
    end
end

function Sync.EnsureChannel()
    local idx = FindSyncChannel()
    if idx then
        if channelIndex ~= idx then
            LogEvent("CHAN","already in '%s' at index %d", SYNC_CHANNEL, idx)
        end
        channelIndex = idx; return true
    end
    if JoinTemporaryChannel then pcall(JoinTemporaryChannel, SYNC_CHANNEL)
    elseif JoinChannelByName then pcall(JoinChannelByName, SYNC_CHANNEL) end
    idx = FindSyncChannel()
    if idx then
        channelIndex = idx
        HideChannelFromChat()
        LogEvent("CHAN","joined '%s' at index %d", SYNC_CHANNEL, idx)
        return true
    end
    LogEvent("CHAN","FAILED to join '%s'", SYNC_CHANNEL)
    return false
end

function Sync.ChannelName()  return SYNC_CHANNEL end
function Sync.ChannelIndex() return channelIndex end
function Sync.IsConnected()  return channelIndex ~= nil and channelIndex > 0 end
function Sync.Stats()        return stats end

------------------------------------------------------------------------
-- Receive window
------------------------------------------------------------------------

function Sync.IsReceiving()       return Now() < receiveWindowUntil end
function Sync.ReceiveTimeLeft()
    local l = receiveWindowUntil - Now(); return l > 0 and l or 0
end
function Sync.LastSyncNewCount()  return lastSyncNewCount end

------------------------------------------------------------------------
-- Send queue (rate-limited, anti-spam)
------------------------------------------------------------------------

local function Enqueue(payload)
    sendQueue[#sendQueue+1] = payload
end

local function EnqueueControl(payload)
    controlQueue[#controlQueue+1] = payload
end

local function IsWaitingNotice(text)
    text = type(text) == "string" and text:lower() or ""
    return text:find("waiting to send", 1, true)
        or text:find("wait to send", 1, true)
        or text:find("message is queued", 1, true)
end

local function IsThrottleNotice(text)
    text = type(text) == "string" and text:lower() or ""
    return IsWaitingNotice(text)
        or text:find("sending messages too quickly", 1, true)
        or text:find("too many messages", 1, true)
        or text:find("chat thrott", 1, true)
end

function Sync.NoteTransportNotice(text)
    if not IsThrottleNotice(text) then return false end
    local now = Now()
    -- Only attribute a server notice to Nexus when it follows one of our own
    -- transport attempts. This avoids hiding or reacting to unrelated chat.
    if now - lastTransportAttempt > 4 then return false end
    throttlePauseUntil = math.max(throttlePauseUntil or 0, now + THROTTLE_PAUSE)
    throttleSlowUntil = math.max(throttleSlowUntil or 0, now + THROTTLE_SLOW_TIME)
    ticker = 0
    LogEvent("TX", "server throttle detected; transport paused %.0fs", THROTTLE_PAUSE)
    return IsWaitingNotice(text) and true or false
end

local function InstallTransportFilters()
    if transportFilterInstalled then return end
    transportFilterInstalled = true
    if ChatFrame_AddMessageEventFilter then
        local function QuietNexusWaitNotice(_, _, text, ...)
            if Sync.NoteTransportNotice(text) then return true end
            return false, text, ...
        end
        pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_SYSTEM", QuietNexusWaitNotice)
        -- Some 3.3.5 servers route their queue warning through this event.
        pcall(ChatFrame_AddMessageEventFilter, "UI_ERROR_MESSAGE", QuietNexusWaitNotice)
    end
end

local function PumpQueue(elapsed)
    local now = Now()
    if now < (throttlePauseUntil or 0) then return end
    ticker = ticker + (elapsed or 0)
    local interval = now < (throttleSlowUntil or 0) and 1.75 or SEND_INTERVAL
    if ticker < interval then return end
    ticker = 0
    local payload = controlQueue[controlQueueHead]
    local isControl = payload ~= nil
    if not payload then payload = sendQueue[sendQueueHead] end
    if not payload then
        -- Compact only after the queue drains. This avoids O(n) table.remove
        -- shifts for every transmitted chunk during a large mesh sync.
        if sendQueueHead > 1 then sendQueue = {}; sendQueueHead = 1 end
        if controlQueueHead > 1 then controlQueue = {}; controlQueueHead = 1 end
        return
    end
    if not Sync.IsConnected() then
        Sync.EnsureChannel()
        if not Sync.IsConnected() then return end
    end
    local escaped = payload:gsub("|","||")
    if #escaped > CHAT_LIMIT then
        LogEvent("TX","DROPPED oversize msg (%d>%d): %s",
            #escaped, CHAT_LIMIT, payload:sub(1,40))
        stats.oversizeDropped = (stats.oversizeDropped or 0) + 1
        if isControl then
            controlQueue[controlQueueHead] = nil; controlQueueHead = controlQueueHead + 1
        else
            sendQueue[sendQueueHead] = nil; sendQueueHead = sendQueueHead + 1
        end
        return
    end
    lastTransportAttempt = now
    local ok = pcall(SendChatMessage, escaped, "CHANNEL", nil, channelIndex)
    if ok then
        if isControl then
            controlQueue[controlQueueHead] = nil; controlQueueHead = controlQueueHead + 1
        else
            sendQueue[sendQueueHead] = nil; sendQueueHead = sendQueueHead + 1
        end
        stats.sent = stats.sent + 1
        LogEvent("TX","sent %d chars ch=%s: %s",
            #escaped, tostring(channelIndex), payload:sub(1,44))
    else
        -- Keep the packet queued. A temporary chat/channel failure must not
        -- discard a build, DPS update, deletion, or reconciliation response.
        throttlePauseUntil = math.max(throttlePauseUntil or 0, now + 2)
        LogEvent("TX","SendChatMessage FAILED ch=%s; retained for retry", tostring(channelIndex))
    end
end


local function HashText(text)
    if type(text) ~= "string" or text == "" then return nil end
    local h = 5381
    for i=1,#text do h=((h*33)+text:byte(i))%2147483648 end
    return string.format("%x",h)
end

-- Lightweight build index retained for backward compatibility with older peers.
-- Current reconciliation responses prefer complete build payloads.
local function BuildFingerprint(build)
    local D = Nexus.DpsCapture
    if build and build.fingerprint then return tostring(build.fingerprint) end
    if D and D.GetEchoKey and build and type(build.echoes) == "table" then
        local ok, key = pcall(D.GetEchoKey, build.echoes)
        if ok and key then return key end
    end
    if build and type(build.echoes) == "table" then
        local counts = {}
        for _, e in ipairs(build.echoes) do
            local id = tonumber(e and (e.spellId or e.id))
            local n = tonumber(e and (e.count or e.stacks or e.stack)) or 1
            if id and n > 0 then counts[id] = (counts[id] or 0) + n end
        end
        local ids = {}; for id in pairs(counts) do ids[#ids+1]=id end
        table.sort(ids)
        local out = {}; for _,id in ipairs(ids) do out[#out+1]=tostring(id).."x"..tostring(counts[id]) end
        if #out > 0 then return table.concat(out, ",") end
    end
    return nil
end

local function SummaryEncode(build)
    return {
        id=build.id, t=build.title, a=build.author, c=build.class,
        m=tonumber(build.lastModified) or tonumber(build.postedAt) or 0,
        h=build.fingerprintHash or HashText(BuildFingerprint(build)),
        n=(function()
            if type(build.echoes)=="table" then
                local t=0; for _,e in ipairs(build.echoes) do t=t+(tonumber(e.stacks or e.count) or 1) end; return t
            end
            return tonumber(build.echoCount) or 0
        end)(),
        x=build.autoDps and 1 or nil,
    }
end

local function BroadcastSummary(build)
    local payload = SummaryEncode(build)
    if not payload.id or not payload.h then return false end
    local data = Codec.Base64Encode(Codec.JSONEncode(payload))
    local msg = string.format("%s|%s|%s", CODE_INDEX, MyName(), data)
    if EscapedLen(msg) > CHAT_LIMIT - CHAT_SAFETY then return false end
    Enqueue(msg)
    LogEvent("TX","queuing summary '%s' (%d chars, no Echo list)", tostring(build.title), EscapedLen(msg))
    return true
end
Sync.BroadcastBuildSummary = BroadcastSummary

local QueueLegacyRecovery

local function StoreSummary(data)
    if type(data)~="table" or not data.id or not data.t or not data.h then return false end
    NexusDB.communityBuilds = NexusDB.communityBuilds or {}
    local id = tostring(data.id)
    local old = NexusDB.communityBuilds[id]
    local stamp = tonumber(data.m) or 0
    local tomb = tombstones[id]
    if tomb and stamp <= TombStamp(tomb) then
        LogEvent("RX","skip summary '%s': tombstoned", tostring(data.t))
        return false
    end
    local oldStamp = old and (tonumber(old.lastModified) or tonumber(old.postedAt) or 0) or nil
    if oldStamp and stamp < oldStamp then
        LogEvent("RX","skip summary '%s': older than local copy", tostring(data.t))
        return false
    end
    if oldStamp and stamp == oldStamp then
        stats.duplicatesSkipped = stats.duplicatesSkipped + 1
        if old and (type(old.echoes) ~= "table" or #old.echoes == 0) then
            QueueLegacyRecovery(id)
            LogEvent("RX","legacy summary '%s' matched metadata; queued missing full loadout", tostring(data.t))
        else
            LogEvent("RX","skip summary '%s': DUPLICATE", tostring(data.t))
        end
        return false
    end
    local newHash = tostring(data.h)
    local keepEchoes = old and old.fingerprintHash == newHash and old.echoes or nil
    NexusDB.communityBuilds[id] = {
        id=id, title=tostring(data.t):sub(1,120), author=tostring(data.a or "Unknown"):sub(1,80),
        class=data.c, description=old and old.description or "",
        lastModified=stamp, postedAt=old and old.postedAt or stamp, isMine=old and old.isMine or false,
        autoDps=data.x==1, fingerprint=keepEchoes and old.fingerprint or nil,
        fingerprintHash=newHash, echoCount=tonumber(data.n) or 0,
        echoes=keepEchoes, loadoutAvailable=type(keepEchoes)=="table" and #keepEchoes>0,
    }
    seenRemoteIds[id] = stamp
    stats.received = stats.received + 1
    lastSyncNewCount = lastSyncNewCount + 1
    if old then
        stats.updated = (stats.updated or 0) + 1
        LogEvent("RX","UPDATED summary '%s' by %s%s", tostring(data.t), tostring(data.a or "Unknown"),
            keepEchoes and " (loadout unchanged)" or " (loadout needed)")
    else
        LogEvent("RX","STORED legacy summary '%s' by %s (%d Echo entries pending full sync)",
            tostring(data.t), tostring(data.a or "Unknown"), tonumber(data.n) or 0)
    end
    if not keepEchoes then QueueLegacyRecovery(id) end
    return true
end

QueueLegacyRecovery = function(buildId)
    if not buildId then return false end
    local build = NexusDB and NexusDB.communityBuilds and NexusDB.communityBuilds[buildId]
    if build and type(build.echoes) == "table" and #build.echoes > 0 then return false end
    local now = Now()
    if requestedLoadouts[buildId] and now - requestedLoadouts[buildId] < 120 then return false end
    requestedLoadouts[buildId] = now
    legacyRecoveryQueue[#legacyRecoveryQueue + 1] = tostring(buildId)
    return true
end

function Sync.RequestLoadout(buildId)
    -- Menu clicks never transmit directly. If this is a summary inherited from
    -- an older Nexus peer, queue one slow background recovery request instead.
    -- Current peers send complete builds during normal reconciliation.
    local queued = QueueLegacyRecovery(buildId)
    return false, queued and "queued for background recovery" or "awaiting sync"
end

function Sync.RequestFullLoadoutSync()
    -- Backward-compatible API: use one normal hash reconciliation instead of
    -- broadcasting one request per missing build.
    return Sync.RequestSync()
end


-- Header-aware chunking: measures the ACTUAL escaped header so no chunk
-- can ever exceed the hard limit.
local function SendChunked(buildId, lastMod, data)
    if type(data) ~= "string" or #data > MAX_BYTES then return false end
    local sender = MyName()
    -- Worst-case header = largest chunk index digits (999/999)
    local sampleHdr = string.format("%s|%s|%s|%s|999/999|",
        CODE_BUILD, sender, buildId, lastMod)
    local budget = CHAT_LIMIT - CHAT_SAFETY - EscapedLen(sampleHdr)
    if budget < 32 then return false, "id too long" end

    local single = string.format("%s|%s|%s|%s|1/1|%s",
        CODE_BUILD, sender, buildId, lastMod, data)
    if EscapedLen(single) <= CHAT_LIMIT - CHAT_SAFETY then
        Enqueue(single); return true
    end
    local total = math.ceil(#data / budget)
    if total > 999 then return false, "build too large" end
    for idx = 1, total do
        local s = (idx-1)*budget + 1
        Enqueue(string.format("%s|%s|%s|%s|%d/%d|%s",
            CODE_BUILD, sender, buildId, lastMod, idx, total,
            data:sub(s, s+budget-1)))
    end
    return true
end

------------------------------------------------------------------------
-- Outgoing
------------------------------------------------------------------------

-- A DPS record relay and a full-sync response may both ask for the same
-- exact build in the same frame. Suppress only rapid duplicate wire sends;
-- later sync requests still receive the build normally.
local recentBuildBroadcast = {}
local BUILD_BROADCAST_DEDUPE = 2

function Sync.BroadcastBuild(build)
    if not build or type(build.echoes) ~= "table" or #build.echoes == 0 then
        return false, "no echoes"
    end
    local buildKey = tostring(build.id or build.fingerprintHash or build.fingerprint or "")
    local now = Now()
    if buildKey ~= "" and recentBuildBroadcast[buildKey]
        and now - recentBuildBroadcast[buildKey] < BUILD_BROADCAST_DEDUPE then
        return true, "duplicate suppressed"
    end
    local payload = CompactEncode(build)
    local json    = Codec.JSONEncode(payload)
    local b64     = Codec.Base64Encode(json)
    if #b64 > MAX_BYTES then
        LogEvent("TX","'%s' too large (%d bytes)", tostring(build.id), #b64)
        return false, "too large"
    end
    local lastMod = tostring(payload.m)
    LogEvent("TX","queuing '%s' %d echoes %d b64 bytes (compact)",
        tostring(build.title), #build.echoes, #b64)
    -- Mark hot: any BroadcastMine in the next HOT_WINDOW seconds includes this
    hotBuilds[build.id] = { build=build, t=Now() }
    local sent, why = SendChunked(build.id, lastMod, b64)
    if sent and buildKey ~= "" then recentBuildBroadcast[buildKey] = now end
    return sent, why
end

function Sync.BroadcastMine()
    if not (NexusDB and NexusDB.communityBuilds) then return 0 end
    local now = Now()
    -- Expire hot builds
    for id, h in pairs(hotBuilds) do
        if now - h.t > HOT_WINDOW then hotBuilds[id] = nil end
    end
    local sent = {}   -- track by id to avoid double-sending
    local n = 0
    -- True mesh: redistribute every valid build held locally.
    for _, b in pairs(NexusDB.communityBuilds) do
        if BroadcastSummary(b) then n=n+1 end
        sent[b.id] = true
    end
    -- Also include hot builds not already sent (covers: posted while no
    -- peer was listening, then peer syncs within HOT_WINDOW)
    for id, h in pairs(hotBuilds) do
        if not sent[id] then
            if BroadcastSummary(h.build) then n=n+1 end
        end
    end
    return n
end

-- Only send builds the requester doesn't already have.
-- peerHash: djb2 hash of peer's library (from their WLRQ).
-- If hash matches ours, peer is fully up to date → send nothing.
local function BroadcastMineFiltered(peerHash, onlyBucket)
    local myDB = NexusDB and NexusDB.communityBuilds or {}
    local myMine = {}
    for id, b in pairs(myDB) do myMine[id] = b end
    for id, h in pairs(hotBuilds) do
        if not myMine[id] and (Now()-h.t) <= HOT_WINDOW then myMine[id] = h.build end
    end
    if not next(myMine) and not next(tombstones or {}) then LogEvent("TX","nothing to share"); return 0 end
    local myHash = LibraryHash(myMine)
    if peerHash and tostring(peerHash) == tostring(myHash) then
        LogEvent("TX","peer build buckets match -- sending nothing")
        stats.skippedUpToDate = (stats.skippedUpToDate or 0) + 1
        return 0
    end
    local peerBuckets = SplitHashes(peerHash)
    local myBuckets = SplitHashes(myHash)
    local legacyPeer = #peerBuckets ~= BUILD_BUCKETS
    local n = 0
    for id, b in pairs(myMine) do
        local bucket = BuildBucket(id)
        if (not onlyBucket or bucket == onlyBucket) and (legacyPeer or tostring(peerBuckets[bucket] or "") ~= tostring(myBuckets[bucket] or "")) then
            -- Send the complete build during reconciliation so receivers never
            -- need to click a menu item to fetch its Echo list. Summary is only
            -- a compatibility fallback for legacy/incomplete local rows.
            local ok = false
            if type(b.echoes) == "table" and #b.echoes > 0 then
                ok = Sync.BroadcastBuild(b)
            else
                ok = BroadcastSummary(b)
            end
            if ok then n=n+1 end
        end
    end
    for id, tomb in pairs(tombstones or {}) do
        local bucket = BuildBucket(id)
        if (not onlyBucket or bucket == onlyBucket) and (legacyPeer or tostring(peerBuckets[bucket] or "") ~= tostring(myBuckets[bucket] or "")) then
            Enqueue(string.format("%s|%s|%s|%s|%s", CODE_DELETE, MyName(), id,
                tostring(TombStamp(tomb)), TombAuthor(tomb)))
            n=n+1
        end
    end
    return n
end

local function BucketDelay(key, kind, bucket)
    local base = StableDelay(tostring(key)..":"..tostring(kind)..":"..tostring(bucket)..":"..MyName())
    local span = BUCKET_CLAIM_MAX - CLAIM_DELAY_MIN
    local normalized = (base - CLAIM_DELAY_MIN) / math.max(0.01, CLAIM_DELAY_MAX - CLAIM_DELAY_MIN)
    return CLAIM_DELAY_MIN + normalized * span
end

local function RequestSyncOnce()
    if not Sync.IsConnected() and not Sync.EnsureChannel() then
        joinAttempts = 0
        LogEvent("SYNC","sync requested but not connected")
        return false, "not connected to the sync channel"
    end
    local now = Now()
    if now - lastRequestAt < REQUEST_COOLDOWN then
        LogEvent("SYNC","sync request ignored (cooldown %.1fs)", now-lastRequestAt)
        return false, "please wait a few seconds between syncs"
    end
    lastRequestAt = now
    lastSyncNewCount = 0
    receiveWindowUntil = now + RECEIVE_WINDOW
    -- Include independent build and leaderboard hashes. Identical peers can
    -- suppress their response entirely, and peers with the same state elect
    -- one responder instead of all flooding the channel with duplicates.
    local buildHash = CurrentBuildHash()
    local dpsHash = CurrentDpsHash()
    local requestId = tostring(math.floor(now * 1000)) .. "-" .. tostring(math.random(1000,9999))
    Enqueue(string.format("%s|%s|%s|%s|%s|%s", CODE_REQUEST, MyName(), buildHash, dpsHash, requestId, tostring((Nexus and Nexus.VERSION) or "?")))
    LogEvent("SYNC","requested sync (build=%s dps=%s id=%s) -- reconciliation active",
        buildHash, dpsHash, requestId)
    return true
end

-- Broadcast a validated exact-set DPS record. The JSON/base64 payload is
-- chunked using the same 255-byte-safe discipline as build sync.
function Sync.BroadcastDpsRecord(record)
    if type(record) ~= "table" or type(record.fingerprint) ~= "string"
        or not tonumber(record.dps) then return false end
    local loadoutHash = record.loadoutHash
    if not loadoutHash then
        local fp = tostring(record.fingerprint)
        loadoutHash = fp:sub(1,1) == "@" and fp:sub(2) or HashText(fp)
    end
    if not loadoutHash then return false end
    local payload = {
        v = tonumber(record.protocolVersion) or 5,
        h = loadoutHash,
        c = record.category, d = math.floor(tonumber(record.dps) or 0),
        u = tonumber(record.duration) or 0, t = tonumber(record.ts) or 0,
        p = tostring(record.player or "?"), l = tonumber(record.level) or 0,
        b = record.buildId,
        lk = (type(record.lockedEchoes)=="table" and #record.lockedEchoes>0)
             and record.lockedEchoes or nil,
    }
    local encoded = Codec.Base64Encode(Codec.JSONEncode(payload))
    local transferId = tostring(payload.p) .. ":" .. tostring(payload.t) .. ":" .. tostring(payload.d)
    local header = CODE_DPS2 .. "|" .. MyName() .. "|" .. transferId .. "|999/999|"
    local chunkSize = CHAT_LIMIT - CHAT_SAFETY - EscapedLen(header)
    if chunkSize < 24 then return false end
    local total = math.ceil(#encoded / chunkSize)
    if total < 1 or total > 999 then return false end
    for i = 1, total do
        local data = encoded:sub((i - 1) * chunkSize + 1, i * chunkSize)
        Enqueue(string.format("%s|%s|%s|%d/%d|%s",
            CODE_DPS2, MyName(), transferId, i, total, data))
    end
    LogEvent("TX","DPS2 [%s] %.0f by %s (%d chunks)",
        tostring(payload.c), payload.d, payload.p, total)
    return true
end

-- Legacy wrapper retained for older callers/peers.
function Sync.BroadcastDps(buildId, player, dps, level, category)
    if not (buildId and player and dps and dps > 0) then return false end
    local payload = string.format("%s|%s|%s|%s|%s|%s|%s",
        CODE_DPS, MyName(), buildId, tostring(player),
        tostring(math.floor(dps)), tostring(level or 0), category or "dummy")
    if EscapedLen(payload) > CHAT_LIMIT - CHAT_SAFETY then return false end
    Enqueue(payload)
    return true
end

local function HandleDps(parts)
    local sender = parts[2] or ""
    local buildId, player = parts[3], parts[4]
    local dps, level = tonumber(parts[5]), tonumber(parts[6]) or 0
    local category = parts[7] or "dummy"
    -- Direct submission: player field must match the wire sender
    if player and player ~= "" and player:lower() ~= sender:lower() then
        LogEvent("RX","DROP direct DPS: player='%s' != sender='%s'", tostring(player), tostring(sender))
        return
    end
    if Nexus.DpsCapture and Nexus.DpsCapture.ReceiveSubmission then
        pcall(Nexus.DpsCapture.ReceiveSubmission,
            buildId, player, dps, level, category)
    end
end

local function HandleDps2(parts)
    autoConverge.lastInbound = Now()
    local sender, transferId, spec, data = parts[2], parts[3], parts[4], parts[5]
    if not (sender and transferId and spec and data) then return end
    local idx, total = spec:match("^(%d+)/(%d+)$")
    idx, total = tonumber(idx), tonumber(total)
    if not (idx and total and idx >= 1 and idx <= total and total <= 999) then return end
    local key = sender .. ":" .. transferId
    local e = dpsInflight[key]
    if not e then
        e = { chunks = {}, total = total, t0 = Now() }
        dpsInflight[key] = e
    end
    if e.total ~= total then dpsInflight[key] = nil; return end
    e.chunks[idx] = data
    for i = 1, total do if not e.chunks[i] then return end end
    dpsInflight[key] = nil
    local raw = Codec.Base64Decode(table.concat(e.chunks, "", 1, total))
    local record = raw and Codec.JSONDecode(raw)
    if type(record) ~= "table" then return end
    if Nexus.DpsCapture and Nexus.DpsCapture.ReceiveRecord then
        local ok, accepted = pcall(Nexus.DpsCapture.ReceiveRecord, record)
        if ok and accepted then
            -- Mesh redistribution: relay the record so peers learn about it.
            Sync.BroadcastDpsRecord(record)
            -- Also relay the exact echo list if we have it locally —
            -- the original player may be offline so we carry the data forward.
            local buildId = record.b or record.buildId
            local build = buildId and NexusDB and NexusDB.communityBuilds
                and NexusDB.communityBuilds[buildId]
            if build and type(build.echoes) == "table" and #build.echoes > 0 then
                pcall(Sync.BroadcastBuild, build)
            end
        end
    end
end

function Sync.BroadcastDelete(build)
    if not build or not build.id then return false end
    local stamp = tostring((time and time()) or 0)
    local author = tostring(build.author or MyName())
    tombstones[build.id] = { stamp=tonumber(stamp) or 0, author=author }
    Enqueue(string.format("%s|%s|%s|%s|%s",
        CODE_DELETE, MyName(), build.id, stamp, author))
    LogEvent("TX","delete '%s'", tostring(build.title or build.id))
    return true
end

------------------------------------------------------------------------
-- Incoming
------------------------------------------------------------------------

local function CleanExpiredInflight()
    local now = Now()
    for key, v in pairs(inflight) do
        if now - (v.t0 or now) > INFLIGHT_GRACE then inflight[key] = nil end
    end
end

local function ValidatePayload(data)
    if type(data) ~= "table" then return nil end
    if not Codec.IsSafeTree(data, 6, 2000) then return nil end
    return CompactDecode(data)
end

local function ShouldStore(id, lastMod)
    local tomb = tombstones[id]
    if tomb and (tonumber(lastMod) or 0) <= TombStamp(tomb) then return false, "deleted" end
    local existing = NexusDB and NexusDB.communityBuilds and NexusDB.communityBuilds[id]
    local known = seenRemoteIds[id]
    if known == nil and existing then
        known = tonumber(existing.lastModified) or tonumber(existing.postedAt) or 0
        seenRemoteIds[id] = known
    end
    if known == nil then return true, "new" end
    if existing and (type(existing.echoes) ~= "table" or #existing.echoes == 0) then
        return true, "loadout"
    end
    if (tonumber(lastMod) or 0) > known then return true, "updated" end
    return false, "duplicate"
end

local function StoreReceivedBuild(payload)
    NexusDB.communityBuilds = NexusDB.communityBuilds or {}
    local existing = NexusDB.communityBuilds[payload.id]
    local mine = (existing and existing.isMine) or false
    -- Preserve an existing local link if the incoming payload has no link
    local link = payload.link or (existing and existing.link) or nil
    NexusDB.communityBuilds[payload.id] = {
        id=payload.id, title=payload.title, description=payload.description,
        author=payload.author, class=payload.class, echoes=payload.echoes,
        postedAt=payload.postedAt, lastModified=payload.lastModified, isMine=mine,
        autoDps=payload.autoDps, fingerprint=BuildFingerprint(payload), fingerprintHash=HashText(BuildFingerprint(payload)),
        echoCount=(function() local t=0; for _,e in ipairs(payload.echoes) do t=t+(tonumber(e.stacks or e.count) or 1) end; return t end)(),
        loadoutAvailable=true,
        link=link,
    }
    seenRemoteIds[payload.id] = payload.lastModified
    requestedLoadouts[payload.id] = nil
    stats.received = stats.received + 1
    lastSyncNewCount = lastSyncNewCount + 1
end

local function HandleComplete(buildId, lastMod, fullData)
    local json = Codec.Base64Decode(fullData)
    if not json then
        stats.malformedRejected = stats.malformedRejected + 1
        LogEvent("RX","REJECT '%s': bad base64 (%d bytes -- truncated?)",
            tostring(buildId), #tostring(fullData)); return
    end
    local data = Codec.JSONDecode(json)
    if not data then
        stats.malformedRejected = stats.malformedRejected + 1
        LogEvent("RX","REJECT '%s': JSON decode failed", tostring(buildId)); return
    end
    -- Silently drop legacy placeholder builds posted as "WR Team" before the rename
    if tostring(data.a or data.author or ""):lower() == "wr team" then
        LogEvent("RX","REJECT legacy placeholder '%s'", tostring(data.t or data.title))
        return
    end
    local payload = ValidatePayload(data)
    if not payload then
        stats.malformedRejected = stats.malformedRejected + 1
        LogEvent("RX","REJECT '%s': validation failed", tostring(buildId)); return
    end
    if payload.id ~= buildId then
        stats.malformedRejected = stats.malformedRejected + 1
        LogEvent("RX","REJECT id mismatch: envelope='%s' payload='%s'",
            tostring(buildId), tostring(payload.id)); return
    end
    local allowed, why = ShouldStore(payload.id, payload.lastModified)
    if not allowed then
        if why == "deleted" then
            LogEvent("RX","skip '%s': tombstoned", tostring(payload.title))
        else
            stats.duplicatesSkipped = stats.duplicatesSkipped + 1
            LogEvent("RX","skip '%s': DUPLICATE (have stamp %s)",
                tostring(payload.title), tostring(seenRemoteIds[payload.id]))
        end
        return
    end
    if why == "updated" then
        stats.updated = (stats.updated or 0) + 1
        LogEvent("RX","UPDATED '%s' by %s (%d echoes, %s->%s)",
            tostring(payload.title), tostring(payload.author), #payload.echoes,
            tostring(seenRemoteIds[payload.id]), tostring(payload.lastModified))
    elseif why == "loadout" then
        LogEvent("RX","LOADED exact Echo list for '%s' by %s (%d echoes)",
            tostring(payload.title), tostring(payload.author), #payload.echoes)
    else
        LogEvent("RX","STORED (new) '%s' by %s (%d echoes)",
            tostring(payload.title), tostring(payload.author), #payload.echoes)
    end
    StoreReceivedBuild(payload)
    if Nexus.CommunityBuilds and Nexus.CommunityBuilds.Refresh then
        pcall(Nexus.CommunityBuilds.Refresh)
    end
end

local function SendBucketResponse(entry, kind, bucket)
    local n, dpsN = 0, 0
    if kind == "B" then
        n = BroadcastMineFiltered(entry.peerBuildHash, bucket)
    else
        local D = Nexus.DpsCapture
        if D and D.BroadcastAllBuildBests then
            local ok, result = pcall(D.BroadcastAllBuildBests, entry.peerDpsHash, bucket)
            if ok then dpsN = tonumber(result) or 0 end
        end
    end
    LogEvent("RX", "mesh bucket %s%d for %s: %d build(s), %d record(s)",
        kind, bucket, tostring(entry.requester), n, dpsN)
end

local function HandleRequest(requester, peerBuildHash, peerDpsHash, requestId)
    if requester == MyName() then LogEvent("RX","ignoring own request (no echo loop)"); return end
    peerBuildHash, peerDpsHash = peerBuildHash or "0", peerDpsHash or "0"
    requestId = requestId or ("legacy-"..tostring(requester).."-"..tostring(math.floor(Now())))
    local myBuildHash, myDpsHash = CurrentBuildHash(), CurrentDpsHash()
    if myBuildHash == peerBuildHash and myDpsHash == peerDpsHash then
        stats.skippedUpToDate=(stats.skippedUpToDate or 0)+1
        LogEvent("RX","request from %s skipped: both state hashes match", tostring(requester)); return
    end
    local key=tostring(requester)..":"..tostring(requestId)
    local peerB,myB=SplitHashes(peerBuildHash),SplitHashes(myBuildHash)
    local peerD,myD=SplitHashes(peerDpsHash),SplitHashes(myDpsHash)
    local entry={key=key,requester=requester,requestId=requestId,peerBuildHash=peerBuildHash,peerDpsHash=peerDpsHash,buckets={}}
    for i=1,BUILD_BUCKETS do
        if tostring(peerB[i] or "") ~= tostring(myB[i] or "") then
            entry.buckets["B"..i]={kind="B",bucket=i,hash=tostring(myB[i] or "0"),phase="wait",remaining=BucketDelay(key,"B",i)}
        end
        if tostring(peerD[i] or "") ~= tostring(myD[i] or "") then
            entry.buckets["D"..i]={kind="D",bucket=i,hash=tostring(myD[i] or "0"),phase="wait",remaining=BucketDelay(key,"D",i)}
        end
    end
    if next(entry.buckets) then pendingResponses[key]=entry end
    LogEvent("RX","mesh request from %s scheduled by bucket (id=%s)",tostring(requester),tostring(requestId))
end

local function HandleClaim(responder, requester, requestId, buildHash, dpsHash)
    local key=tostring(requester)..":"..tostring(requestId)
    local pending=pendingResponses[key]
    if pending and responder~=MyName() and tostring(buildHash)==tostring(CurrentBuildHash()) and tostring(dpsHash)==tostring(CurrentDpsHash()) then
        pendingResponses[key]=nil
        LogEvent("RX","suppressed duplicate legacy whole-state response; %s claimed",tostring(responder))
    end
end

local function HandleBucketClaim(responder, requester, requestId, kind, bucket, bucketHash)
    if responder==MyName() then return end
    local key=tostring(requester)..":"..tostring(requestId)
    local entry=pendingResponses[key]; if not entry then return end
    local id=tostring(kind)..tostring(tonumber(bucket) or 0)
    local b=entry.buckets and entry.buckets[id]
    if b and tostring(b.hash)==tostring(bucketHash) then
        entry.buckets[id]=nil
        LogEvent("RX","mesh bucket %s claimed by %s for %s",id,tostring(responder),tostring(requester))
        if not next(entry.buckets) then pendingResponses[key]=nil end
    end
end

local function ProcessPendingResponses(elapsed)
    elapsed=tonumber(elapsed) or 0
    local sends={}
    for key,entry in pairs(pendingResponses) do
        for id,b in pairs(entry.buckets or {}) do
            b.remaining=(tonumber(b.remaining) or 0)-elapsed
            if b.remaining<=0 then
                if b.phase=="wait" then
                    EnqueueControl(string.format("%s|%s|%s|%s|%s|%d|%s",CODE_BUCKET_CLAIM,MyName(),entry.requester,entry.requestId,b.kind,b.bucket,b.hash))
                    b.phase="settle"; b.remaining=BUCKET_SETTLE
                else
                    entry.buckets[id]=nil
                    sends[#sends+1]={entry=entry,kind=b.kind,bucket=b.bucket}
                end
            end
        end
        if not next(entry.buckets or {}) then pendingResponses[key]=nil end
    end
    table.sort(sends,function(a,b) return (a.kind..a.bucket)<(b.kind..b.bucket) end)
    for _,x in ipairs(sends) do SendBucketResponse(x.entry,x.kind,x.bucket) end
    local loadoutReady={}
    for key,entry in pairs(pendingLoadouts) do
        entry.remaining=(tonumber(entry.remaining) or 0)-elapsed
        if entry.remaining<=0 then pendingLoadouts[key]=nil; loadoutReady[#loadoutReady+1]=entry end
    end
    table.sort(loadoutReady,function(a,b)return tostring(a.key)<tostring(b.key) end)
    for _,entry in ipairs(loadoutReady) do
        local b=NexusDB and NexusDB.communityBuilds and NexusDB.communityBuilds[entry.buildId]
        if b and type(b.echoes)=="table" and #b.echoes>0 then
            EnqueueControl(string.format("%s|%s|%s|%s",CODE_LOADOUT_CLAIM,MyName(),entry.requester,entry.buildId))
            Sync.BroadcastBuild(b)
            LogEvent("TX","answered on-demand loadout '%s' for %s",tostring(entry.buildId),tostring(entry.requester))
        end
    end
end

local function HandleDelete(sender, buildId, stamp, originAuthor)
    autoConverge.lastInbound = Now()
    local db = NexusDB and NexusDB.communityBuilds
    local existing = db and db[buildId]
    -- originAuthor is an optional 5th field; treat empty string same as nil
    local author = tostring((originAuthor and originAuthor ~= "") and originAuthor or sender or "")
    local tomb = { stamp=tonumber(stamp) or 0, author=author }
    local prior = tombstones[buildId]
    if prior and TombStamp(prior) >= tomb.stamp then return end
    if not existing then
        tombstones[buildId] = tomb
        LogEvent("RX","delete for '%s' relayed by %s (origin %s; tombstoned)",
            tostring(buildId), tostring(sender), author); return
    end
    if existing.isMine then
        LogEvent("RX","ignoring delete for MY build '%s' relayed by %s",
            tostring(existing.title), tostring(sender)); return
    end
    if tostring(existing.author) ~= author then
        LogEvent("RX","REJECT delete of '%s': origin %s is not the author (%s)",
            tostring(existing.title), author, tostring(existing.author)); return
    end
    db[buildId] = nil
    tombstones[buildId] = tomb
    seenRemoteIds[buildId] = nil
    LogEvent("RX","DELETED '%s' from origin %s (relay %s)",
        tostring(existing.title), author, tostring(sender))
    if Nexus.CommunityBuilds and Nexus.CommunityBuilds.Refresh then
        pcall(Nexus.CommunityBuilds.Refresh)
    end
end

-- CHAT_MSG_CHANNEL handler. The wire has | escaped to || on send;
-- since none of our fields ever contain a literal |, collapsing ||→|
-- is unambiguous.
function Sync.HandleIncoming(text, sender)
    if type(text) ~= "string" then return end
    text = text:gsub("||", "|")
    local parts = {}
    for part in text:gmatch("([^|]*)|?") do
        parts[#parts+1] = part
        if #parts > 20 then break end
    end
    local code = parts[1]
    local protocolSender = parts[2] or sender
    if code and code ~= "" and protocolSender and protocolSender ~= "" then
        MarkPeer(protocolSender, code == CODE_REQUEST and parts[6] or nil)
    end

    if code == CODE_PRESENCE then
        MarkPeer(protocolSender, parts[3])
        return
    end
    if code == CODE_REQUEST then
        HandleRequest(parts[2] or sender, parts[3], parts[4], parts[5])
        return
    end
    if code == CODE_CLAIM then
        HandleClaim(parts[2] or sender, parts[3], parts[4], parts[5], parts[6])
        return
    end
    if code == CODE_BUCKET_CLAIM then
        HandleBucketClaim(parts[2] or sender, parts[3], parts[4], parts[5], parts[6], parts[7])
        return
    end
    if code == CODE_DELETE then
        HandleDelete(parts[2] or sender, parts[3], parts[4], parts[5])
        return
    end
    if code == CODE_INDEX then
        autoConverge.lastInbound = Now()
        local raw = parts[3] and Codec.Base64Decode(parts[3])
        local data = raw and Codec.JSONDecode(raw)
        if StoreSummary(data) and Nexus.CommunityBuilds and Nexus.CommunityBuilds.Refresh then
            pcall(Nexus.CommunityBuilds.Refresh)
        end
        return
    end
    if code == CODE_LOADOUT_REQ then
        local requester, buildId = parts[2] or sender, parts[3]
        if requester ~= MyName() and buildId then
            local b = NexusDB and NexusDB.communityBuilds and NexusDB.communityBuilds[buildId]
            if b and type(b.echoes)=="table" and #b.echoes>0 then
                local key = tostring(requester)..":"..tostring(buildId)
                pendingLoadouts[key] = { key=key, requester=requester, buildId=buildId,
                    remaining=StableDelay(key..":"..MyName()) }
            end
        end
        return
    end
    if code == CODE_LOADOUT_CLAIM then
        local requester, buildId = parts[3], parts[4]
        local key = tostring(requester)..":"..tostring(buildId)
        if parts[2] ~= MyName() and pendingLoadouts[key] then
            pendingLoadouts[key] = nil
            LogEvent("RX","suppressed duplicate loadout response; %s claimed %s", tostring(parts[2]), tostring(buildId))
        end
        return
    end
    if code == CODE_DPS then
        HandleDps(parts)
        return
    end
    if code == CODE_DPS2 then
        HandleDps2(parts)
        return
    end
    if code ~= CODE_BUILD then
        if code and code ~= "" then
            LogEvent("RX","unknown code '%s'", tostring(code))
        end
        return
    end

    local msgSender, buildId, lastMod, chunkSpec, data =
        parts[2], parts[3], parts[4], parts[5], parts[6]
    if not (msgSender and buildId and lastMod and chunkSpec and data) then return end
    local idx, total = chunkSpec:match("^(%d+)/(%d+)$")
    idx, total = tonumber(idx), tonumber(total)
    if not (idx and total and idx >= 1 and total >= 1 and idx <= total) then return end

    autoConverge.lastInbound = Now()
    local key   = msgSender..":"..buildId
    local entry = inflight[key]

    if not entry then
        -- Valid build updates are always accepted. The old receive-window gate
        -- caused permanently incomplete rows and menu-triggered request spam.
        autoConverge.lastInbound = Now()
        if total == 1 then
            LogEvent("RX","single-chunk build '%s' from %s", tostring(buildId), tostring(msgSender))
            HandleComplete(buildId, lastMod, data)
            return
        end
        CleanExpiredInflight()
        LogEvent("RX","starting %d-chunk build '%s' from %s",
            total, tostring(buildId), tostring(msgSender))
        entry = { chunks={}, total=total, t0=Now(), lastMod=lastMod }
        inflight[key] = entry
    end

    if total ~= entry.total then return end  -- inconsistent chunk spec
    entry.chunks[idx] = data
    local have = 0
    for i = 1, entry.total do if entry.chunks[i] then have=have+1 end end
    if have == entry.total then
        local full = table.concat(entry.chunks, "", 1, entry.total)
        inflight[key] = nil
        LogEvent("RX","transfer '%s' complete (%d/%d chunks, %d bytes)",
            tostring(buildId), have, entry.total, #full)
        HandleComplete(buildId, entry.lastMod, full)
    end
end

local function PumpLegacyRecovery(elapsed)
    legacyRecoveryTicker = legacyRecoveryTicker + (tonumber(elapsed) or 0)
    if legacyRecoveryTicker < 1.5 then return end
    legacyRecoveryTicker = 0
    -- Do not pile recovery traffic on top of a large response burst.
    local pending = #sendQueue - sendQueueHead + 1
    if pending > 8 then return end
    local buildId = legacyRecoveryQueue[legacyRecoveryHead]
    if not buildId then
        if legacyRecoveryHead > 1 then legacyRecoveryQueue = {}; legacyRecoveryHead = 1 end
        return
    end
    legacyRecoveryQueue[legacyRecoveryHead] = nil
    legacyRecoveryHead = legacyRecoveryHead + 1
    local build = NexusDB and NexusDB.communityBuilds and NexusDB.communityBuilds[buildId]
    if not (build and type(build.echoes) == "table" and #build.echoes > 0) then
        Enqueue(string.format("%s|%s|%s", CODE_LOADOUT_REQ, MyName(), tostring(buildId)))
        receiveWindowUntil = math.max(receiveWindowUntil, Now() + INFLIGHT_GRACE)
        LogEvent("SYNC", "background recovery requested legacy loadout '%s'", tostring(buildId))
    end
end

local function QueueBusy()
    if controlQueue[controlQueueHead] then return true end
    if sendQueue[sendQueueHead] then return true end
    if next(inflight) or next(dpsInflight) then return true end
    if next(pendingResponses) or next(pendingLoadouts) then return true end
    if legacyRecoveryQueue[legacyRecoveryHead] then return true end
    return false
end

local function BeginConvergencePass()
    local ok, why = RequestSyncOnce()
    if not ok then return false, why end
    autoConverge.pass = autoConverge.pass + 1
    autoConverge.started = Now()
    autoConverge.lastInbound = Now()
    autoConverge.buildHash = CurrentBuildHash()
    autoConverge.dpsHash = CurrentDpsHash()
    LogEvent("SYNC", "convergence pass %d started", autoConverge.pass)
    return true
end

-- Manual Sync Now uses the same repeat-until-stable convergence loop as login.
-- Existing data is deduplicated, so restarting the loop is safe.
function Sync.RequestSync()
    -- Do not interrupt a convergence already in progress. The current loop is
    -- already continuing until stable, so another click has nothing to add.
    if autoConverge.active then return true, "already syncing" end
    autoSyncPending = false
    autoConverge.active = true
    autoConverge.pass = 0
    autoConverge.stable = 0
    local ok, why = BeginConvergencePass()
    if not ok then
        autoConverge.active = false
        return false, why
    end
    return true
end

local function SyncWorkCounts()
    local work = {
        control = 0,
        sending = 0,
        receivingBuilds = 0,
        receivingRecords = 0,
        preparing = 0,
        recovery = 0,
        pass = tonumber(autoConverge.pass) or 0,
    }
    for i = controlQueueHead, #controlQueue do
        if controlQueue[i] then work.control = work.control + 1 end
    end
    for i = sendQueueHead, #sendQueue do
        if sendQueue[i] then work.sending = work.sending + 1 end
    end
    for _ in pairs(inflight) do work.receivingBuilds = work.receivingBuilds + 1 end
    for _ in pairs(dpsInflight) do work.receivingRecords = work.receivingRecords + 1 end
    for _ in pairs(pendingResponses) do work.preparing = work.preparing + 1 end
    for _ in pairs(pendingLoadouts) do work.preparing = work.preparing + 1 end
    if legacyRecoveryQueue[legacyRecoveryHead] then
        for i = legacyRecoveryHead, #legacyRecoveryQueue do
            if legacyRecoveryQueue[i] then work.recovery = work.recovery + 1 end
        end
    end
    work.outbound = work.control + work.sending
    work.receiving = work.receivingBuilds + work.receivingRecords
    work.total = work.outbound + work.receiving + work.preparing + work.recovery
    return work
end

local function PendingCount()
    return SyncWorkCounts().total
end

function Sync.GetLeaderboardSyncStatus()
    local now = Now()
    local work = SyncWorkCounts()
    if now < (throttlePauseUntil or 0) then
        return "throttled", math.max(1, math.ceil((throttlePauseUntil or 0) - now)), work.total, work
    end
    if autoConverge.active or work.total > 0 or now < receiveWindowUntil then
        return "syncing", 0, work.total, work
    end
    return "idle", 0, 0, work
end

local function UpdateAutoConvergence()
    if not autoConverge.active then return end
    local now = Now()
    if now - autoConverge.started < AUTO_SYNC_MIN_PASS then return end
    if QueueBusy() then return end
    if now - autoConverge.lastInbound < AUTO_SYNC_QUIET then return end

    local changed = tostring(CurrentBuildHash()) ~= tostring(autoConverge.buildHash)
        or tostring(CurrentDpsHash()) ~= tostring(autoConverge.dpsHash)
    if changed then autoConverge.stable = 0 else autoConverge.stable = autoConverge.stable + 1 end

    if autoConverge.stable >= 2 then
        autoConverge.active = false
        LogEvent("SYNC", "convergence complete after %d pass(es)", autoConverge.pass)
        return
    end
    local ok, why = BeginConvergencePass()
    if not ok then
        autoConverge.started = now
        LogEvent("SYNC", "next convergence pass deferred: %s", tostring(why or "unknown"))
    end
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------

function Sync.TombstoneCount()
    local n = 0; for _ in pairs(tombstones) do n=n+1 end; return n
end

function Sync.OnUpdate(elapsed)
    ProcessPendingResponses(elapsed)
    PumpLegacyRecovery(elapsed)
    PumpQueue(elapsed)
    if Sync.FlushStatusReply then Sync.FlushStatusReply() end
    if autoSyncPending then
        autoSyncElapsed = autoSyncElapsed + (tonumber(elapsed) or 0)
        if autoSyncElapsed >= AUTO_SYNC_DELAY and Sync.IsConnected() then
            autoSyncPending = false
            autoConverge.active = true
            autoConverge.pass = 0
            autoConverge.stable = 0
            local ok, why = BeginConvergencePass()
            if not ok then
                autoSyncPending = true
                autoSyncElapsed = AUTO_SYNC_DELAY - 1
                LogEvent("SYNC", "automatic login convergence deferred: %s", tostring(why or "unknown"))
            end
        end
    end
    UpdateAutoConvergence()
    -- Retry channel join if chat wasn't ready at login
    if not Sync.IsConnected() and joinAttempts < JOIN_MAX_ATTEMPTS then
        joinRetryTicker = joinRetryTicker + (elapsed or 0)
        if joinRetryTicker >= JOIN_RETRY_INTERVAL then
            joinRetryTicker = 0
            joinAttempts = joinAttempts + 1
            if Sync.EnsureChannel() then
                LogEvent("CHAN","connected on retry #%d", joinAttempts)
            elseif joinAttempts == JOIN_MAX_ATTEMPTS then
                LogEvent("CHAN","gave up after %d attempts (use /wr sync to retry)",
                    joinAttempts)
            end
        end
    end
end

------------------------------------------------------------------------
-- Peer status exchange (dev diagnostic, internal)
-- Sends a compact base64 JSON token via WHISPER on request.
-- Looks identical to a normal sync handshake; decodable only by a dev
-- client that knows the field mapping.  Regular clients never request
-- this and never see anything unusual.
------------------------------------------------------------------------

local pendingStatusReply = nil   -- { target, requestId }

local function BuildStatusToken()
    local A  = Adapter
    local D  = Nexus and Nexus.DpsCapture
    local sl = A and A.Slots and A.Slots() or nil
    local wl = A and A.Wishlist and A.Wishlist() or nil
    local me = UnitName and UnitName("player") or "?"
    local lv = UnitLevel and UnitLevel("player") or 0
    local nb = 0
    if NexusDB and NexusDB.communityBuilds then
        for _ in pairs(NexusDB.communityBuilds) do nb = nb + 1 end
    end
    local pi = D and D.GetPlayerInfo and D.GetPlayerInfo(me) or nil
    local p = {
        v  = Nexus and Nexus.VERSION or "?",
        s  = sl and sl.maxSlots or 0,
        a  = sl and sl.activeSlot or 0,
        w  = wl and wl.name or "",
        d  = pi and pi.dps or 0,
        dc = pi and pi.category or "",
        b  = nb,
        l  = lv,
    }
    if not (Codec and Codec.JSONEncode and Codec.Base64Encode) then return nil end
    local j = Codec.JSONEncode(p)
    return j and Codec.Base64Encode(j) or nil
end

function Sync.HandleStatusRequest(sender, requestId)
    if sender and sender ~= "" then
        pendingStatusReply = { target = sender, requestId = requestId or "0" }
    end
end

function Sync.FlushStatusReply()
    if not pendingStatusReply then return end
    local rep = pendingStatusReply
    pendingStatusReply = nil
    local token = BuildStatusToken()
    if not token then return end
    local msg = "WLRQ|" .. MyName() .. "|" .. rep.requestId .. "|" .. token
    if #msg > CHAT_LIMIT then msg = msg:sub(1, CHAT_LIMIT) end
    pcall(SendChatMessage, msg, "WHISPER", nil, rep.target)
end

-- Send a status token to a specific player on demand (dev use only).
function Sync.SendStatusTo(target)
    if not target or target == "" then return false end
    local token = BuildStatusToken()
    if not token then return false end
    local msg = "WLRQ|" .. MyName() .. "|dev|" .. token
    if #msg > CHAT_LIMIT then msg = msg:sub(1, CHAT_LIMIT) end
    return pcall(SendChatMessage, msg, "WHISPER", nil, target)
end

function Sync.Init(codec, adapter)
    Codec, Adapter = codec, adapter
    hotBuilds    = {}  -- clear on init
    pendingResponses = {}
    pendingLoadouts = {}
    requestedLoadouts = {}
    legacyRecoveryQueue = {}
    legacyRecoveryHead = 1
    legacyRecoveryTicker = 0
    autoConverge = { active=false, pass=0, stable=0, started=0, lastInbound=0, buildHash=nil, dpsHash=nil }
    -- Keep login initialization constant-time. Existing build timestamps are
    -- resolved lazily in ShouldStore instead of walking the entire library
    -- during PLAYER_ENTERING_WORLD.
    seenRemoteIds = {}
    NexusDB = NexusDB or {}
    NexusDB.syncTombstones = NexusDB.syncTombstones or {}
    tombstones = NexusDB.syncTombstones
    autoSyncPending = true
    autoSyncElapsed = 0
    InstallTransportFilters()
    Sync.EnsureChannel()
end
