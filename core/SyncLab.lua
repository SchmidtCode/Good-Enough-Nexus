-- Explicit, temporary two-character diagnostic session. No saved record edits
-- except normal validated sync acceptance. All traffic uses the normal pacer.
Nexus = Nexus or {}
local Lab = {}
Nexus.SyncLab = Lab
local session
local function Now() return GetTime() end
local function Me() return UnitName("player") end
local function Same(a,b) return tostring(a):lower() == tostring(b):lower() end
local function Print(text)
    DEFAULT_CHAT_FRAME:AddMessage("Nexus sync lab: " .. tostring(text))
end

function Lab.Trace(kind, text)
    if not session then return end
    -- Keep identifiers/outcomes, never encoded build bodies in this report.
    text = tostring(text):gsub("(WLRB|.*|%d+/%d+|).*", "%1<chunk>")
        :gsub("(WLD2|.*|%d+/%d+|).*", "%1<chunk>")
        :gsub("[%c]", " "):sub(1,160)
    if #session.events >= 240 then
        table.remove(session.events, 1)
        session.dropped = session.dropped + 1
    end
    session.events[#session.events+1] = string.format("%.1fs %s %s",
        Now()-session.started, tostring(kind):sub(1,16), text)
end

function Lab.Report()
    if not session then return NexusDB and NexusDB.syncLabReport or "No lab report." end
    local st, work = Nexus.Sync.Stats(), Nexus.Sync.WorkState()
    local out = {"NEXUS SYNC LAB 1 diagnostics=3 transport=CW2", "role=" .. session.role .. " player=" .. Me()
        .. " peer=" .. session.peer .. " id=" .. session.id,
        string.format("elapsed=%.1fs ready=%s finished=%s step=%d/%d",
            Now()-session.started, tostring(session.ready), tostring(session.finished),
            session.cursor or 0, #(session.tasks or {})),
        string.format("directTX/RX=%d/%d ACK=%d contentACK=%d timeout=%d fallback=%d",
            st.directBulkTx or 0, st.directBulkRx or 0, st.directAckSuccess or 0,
            st.directContentAck or 0, st.directAckTimeout or 0, st.directFallback or 0),
        string.format("channelTX/RX=%d/%d queues=%d pendingACK=%d deferred=%d",
            st.channelBulkTx or 0, st.channelBulkRx or 0, work.outbound or 0,
            work.directAckPending or 0, work.dpsDeferred or 0),
        string.format("DPS owner/relay/noop/rejected=%d/%d/%d/%d",
            st.dpsDirectAccepted or 0, st.dpsRelayAccepted or 0,
            st.dpsIdempotentAccepted or 0, st.dpsRecordRejected or 0),
        "Validation is unchanged. Relays remain unverified. Pace=1.10s; deadline=600s.",
        "INVENTORY / SELECTED RECORDS"}
    for _, line in ipairs(session.inventory) do out[#out+1] = line:sub(1,200) end
    out[#out+1] = "SEND FAILURE DETAILS"
    for _, line in ipairs(session.failures or {}) do out[#out+1] = line end
    out[#out+1] = "EVENTS retained=" .. #session.events .. " dropped=" .. session.dropped
    for _, line in ipairs(session.events) do out[#out+1] = line end
    return table.concat(out, "\n")
end

local function Save() NexusDB.syncLabReport = Lab.Report() end

-- Called only by the transport during an explicitly armed lab. Do not log
-- encoded bodies. Preserve the error separately from the rolling event ring.
function Lab.SendFailure(route, payload, wireBytes, problem)
    if not session then return end
    local header, chunk = payload:match("^(.-|%d+/%d+|)") , payload:match("|(%d+/%d+)|")
    local safeError=tostring(problem):gsub("[%c|]", " "):sub(1,180)
    local detail=string.format("%s chunk=%s wireBytes=%d",route,chunk or "control",wireBytes)
    if #(session.failures or {}) < 12 then
        session.failures=session.failures or {}
        session.failures[#session.failures+1]=detail
        session.failures[#session.failures+1]="error=" .. safeError
    end
    Lab.Trace("API-FAIL",detail)
    Lab.Trace("API-ERROR",safeError)
    if route=="CHANNEL" then
        local key=header or payload
        if session.failedPacket==key then
            session.failedAttempts=session.failedAttempts+1
        else
            session.failedPacket,session.failedAttempts=key,1
        end
        if session.failedAttempts>=3 then session.abortReason="repeated channel API failure" end
    end
    Save()
end

function Lab.Stop(reason)
    if not session then return end
    Lab.Trace("STOP", reason or "user")
    Save()
    session = nil
    Nexus.Sync.CloseDiagnosticSession()
    Print("stopped; report retained. /nexuslab log")
end

function Lab.Start(role, peer, count)
    if session then return false, "use /nexuslab stop first" end
    if role ~= "send" and role ~= "receive" then return false, "invalid role" end
    count = tonumber(count) or 5
    if count < 1 or count > 5 or count ~= math.floor(count) then
        return false, "record count must be 1 to 5"
    end
    local id = "lab-" .. math.floor(Now()*1000) .. "-" .. math.random(1000,9999)
    local ok, why = Nexus.Sync.OpenDiagnosticSession(peer, id)
    if not ok then return false, why or "invalid peer or unsafe context" end
    session = {role=role,peer=peer,count=count,id=id,started=Now(),
        events={},inventory={},dropped=0,nextHello=0,nextSnapshot=0,attempts=0}
    Lab.showReport = true
    Lab.Trace("START", "normal mesh work paused; only configured peer is processed")
    Save()
    Print(role .. " armed for " .. peer .. ". Stay resting and out of combat. /nexuslab log")
    return true
end

-- Both endpoints must explicitly opt in locally. Target and sender are never
-- accepted as arbitrary redirection instructions. Normal clients ignore these.
function Lab.Handle(code, p)
    if not session or not Same(p[2], session.peer) or not Same(p[3], Me())
        or type(p[4]) ~= "string" or #p[4] > 80
        or not p[4]:match("^lab%-%d+%-%d+$") then return false end
    if code == "WLTQ" and session.role == "receive" then
        local count = tonumber(p[5])
        if #p ~= 6 or p[6] ~= "CW2" or not count or count < 1
            or count > 5 or count ~= math.floor(count) then return false end
        if session.ready and session.id ~= p[4] then return false end
        session.id, session.ready = p[4], true
        Nexus.Sync._diagnostic.id = p[4]
        Nexus.Sync._diagnostic.pipeFree = true
        Nexus.Sync._outgoingRequest = {requestId=p[4],createdAt=Now()}
        if not session.lastReply or Now()-session.lastReply >= 5 then
            Nexus.Sync.DiagnosticControl(table.concat({"WLTR",Me(),session.peer,p[4]},"|"))
            session.lastReply=Now()
            Lab.Trace("READY", "explicit CW2 pipe-free test request accepted")
        end
        return true
    elseif code == "WLTR" and #p == 4 and session.role == "send"
        and session.id == p[4] then
        session.ready = true
        Nexus.Sync._diagnostic.pipeFree = true
        Lab.Trace("READY", "receiver acknowledged lab request")
        return true
    end
    return false
end

local function Inventory()
    local rows = Nexus.DpsCapture.DiagnosticRecords()
    local eligible, failures, samples = {dummy={},lk={}}, {}, 0
    for _, row in ipairs(rows) do
        if not Same(row.player, Me()) then
            local ok, _, prepared, reason = Nexus.Sync.BroadcastDpsRecord(row, nil,
                true, {prepareOnly=true})
            if ok and prepared then
                eligible[row.category][#eligible[row.category]+1] = row
            else
                reason = reason or "serialization-or-queue"
                failures[reason] = (failures[reason] or 0) + 1
                if samples < 20 then
                    samples = samples + 1
                    session.inventory[#session.inventory+1] = string.format(
                        "BLOCKED %s %s dps=%s build=%s reason=%s",
                        row.player,row.category,row.dps,tostring(row.buildId),reason)
                    session.inventory[#session.inventory+1] = string.format(
                        "  duration=%s ts=%s level=%s class=%s echoes=%d hash=%s",
                        tostring(row.duration),tostring(row.ts),tostring(row.level),
                        tostring(row.class),type(row.echoes)=="table" and #row.echoes or 0,
                        tostring(row.loadoutHash))
                end
            end
        end
    end
    session.inventory[#session.inventory+1] = string.format(
        "scanned=%d cap=500 eligible third-party dummy=%d lk=%d",
        #rows,#eligible.dummy,#eligible.lk)
    for reason,n in pairs(failures) do
        session.inventory[#session.inventory+1] = "blocked " .. reason .. "=" .. n
    end
    local selected, cursors = {}, {dummy=1,lk=1}
    for i=1,session.count do
        local category = i%2 == 1 and "dummy" or "lk"
        if not eligible[category][cursors[category]] then
            category = category == "dummy" and "lk" or "dummy"
        end
        local row = eligible[category][cursors[category]]
        if row then
            cursors[category] = cursors[category]+1
            selected[#selected+1] = row
            session.inventory[#session.inventory+1] = string.format(
                "SELECT %d %s %s dps=%s build=%s echoes=%d",
                #selected,row.player,row.category,row.dps,tostring(row.buildId),
                type(row.echoes)=="table" and #row.echoes or 0)
            session.inventory[#session.inventory+1] = string.format(
                "  duration=%s ts=%s level=%s class=%s hash=%s",
                tostring(row.duration),tostring(row.ts),tostring(row.level),
                tostring(row.class),tostring(row.loadoutHash))
        end
    end
    session.tasks = {}
    for _, row in ipairs(selected) do
        for _, mode in ipairs({"compact-first", "build", "compact-after-build",
            "full-evidence", "full-repeat", "channel-compact"}) do
            session.tasks[#session.tasks+1] = {row=row,mode=mode}
        end
    end
    session.cursor=1
    Lab.Trace("PLAN", "selected=" .. #selected .. " steps=" .. #session.tasks)
end

function Lab.Update()
    if not session then return end
    if session.abortReason then Lab.Stop(session.abortReason); return end
    if Now()-session.started >= 600 then Lab.Stop("600-second deadline"); return end
    if Now() >= session.nextSnapshot then
        session.nextSnapshot=Now()+15
        local w=Nexus.Sync.WorkState()
        Lab.Trace("PROGRESS", string.format("connected=%s queues=%d ACKwait=%d deferred=%d",
            tostring(Nexus.Sync.IsConnected()),w.outbound,w.directAckPending,w.dpsDeferred))
        Save()
    end
    if not Nexus.Sync.IsConnected() then return end
    if not session.ready then
        if session.role == "send" and Now() >= session.nextHello then
            if session.attempts >= 10 then Lab.Stop("peer did not arm/respond"); return end
            session.attempts=session.attempts+1
            session.nextHello=Now()+5
            Nexus.Sync.DiagnosticControl(table.concat({"WLTQ",Me(),session.peer,
                session.id,session.count,"CW2"},"|"))
        end
        return
    end
    if session.role ~= "send" or session.finished then return end
    if not session.tasks then Inventory() end
    local w=Nexus.Sync.WorkState()
    if w.outbound>0 or w.directAckPending>0 or w.directFallbackPending>0
        or w.pendingLoadouts>0 then return end
    local task=session.tasks[session.cursor]
    if not task then
        session.finished=true
        Lab.Trace("DONE", "all planned steps drained; inspect receiver RESULT and sender ACK lines")
        Save()
        Print("test steps complete. Get both reports with /nexuslab log")
        return
    end
    local route={requester=session.peer,requestId=session.id,
        chatWhisper=task.mode~="channel-compact",
        fullEvidence=task.mode=="full-evidence" or task.mode=="full-repeat"}
    Lab.Trace("STEP", string.format("%d/%d %s %s %s",session.cursor,#session.tasks,
        task.mode,task.row.player,task.row.category))
    local ok, why
    if task.mode=="build" then
        ok,why=Nexus.Sync.DiagnosticBuild(task.row.buildId,route)
    else
        ok,why=Nexus.Sync.BroadcastDpsRecord(task.row,nil,true,route)
    end
    Lab.Trace("ADMIT", "result=" .. tostring(ok) .. " reason=" .. tostring(why))
    session.cursor=session.cursor+1
end

SLASH_NEXUSLAB1 = "/nexuslab"
SlashCmdList.NEXUSLAB = function(message)
    message=tostring(message or ""):match("^%s*(.-)%s*$")
    if message=="stop" then Lab.Stop("user"); return end
    if message=="log" then
        Lab.showReport=true
        if session then Save() end
        if Nexus.LogViewer then Nexus.LogViewer.Show("sync") end
        return
    end
    if message=="normal" then Lab.showReport=false; return end
    local role,peer,count=message:match("^(%a+)%s+(%S+)%s*(%d*)$")
    if role then
        local ok,why=Lab.Start(role,peer,tonumber(count))
        if not ok then Print(why) end
    else
        Print("/nexuslab receive Testsender | send Testreceiver 5 | log | stop | normal")
    end
end
