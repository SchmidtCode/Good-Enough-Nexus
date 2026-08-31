-- Nexus: core/SyncResponder.lua
-- Stateful, transport-agnostic responder work engine. Sync.lua supplies the
-- serialization and send handlers; this module owns pending work, expiry,
-- bounded admission, and fair one-unit selection.

Nexus = Nexus or {}
local SyncResponder = {}
Nexus.SyncResponder = SyncResponder

local function Clear(map)
    for key in pairs(map) do map[key] = nil end
end

local function Count(map)
    local count = 0
    for _ in pairs(map) do count = count + 1 end
    return count
end

local function NewStats()
    return {
        turns=0, workUnits=0, backpressureDeferrals=0,
        entryPreparations=0, candidateSnapshots=0, candidateSorts=0,
        candidateScans=0, buildSerializations=0, buildAdmissions=0,
        dpsSerializations=0, chunkMessagesBuilt=0, compatRequests=0,
    }
end

function SyncResponder.New(options)
    options = options or {}
    local engine = {
        responses={}, loadouts={}, fairCursor=nil, candidateCache=nil,
        manualPublish=nil, stats=NewStats(),
        bucketCount=tonumber(options.bucketCount) or 8,
        pendingTtl=tonumber(options.pendingTtl) or 30,
        pendingMaxAge=tonumber(options.pendingMaxAge) or 300,
    }

    function engine.Reset()
        Clear(engine.responses)
        Clear(engine.loadouts)
        engine.fairCursor, engine.candidateCache, engine.manualPublish = nil, nil, nil
        engine.stats = NewStats()
    end

    function engine.ClearPending()
        Clear(engine.responses)
        Clear(engine.loadouts)
        engine.fairCursor = nil
    end

    function engine.PendingCount(kind)
        return Count(kind == "loadout" and engine.loadouts or engine.responses)
    end

    function engine.AdmitPending(kind, key, entry, limit)
        local map = kind == "loadout" and engine.loadouts or engine.responses
        if map[key] then return true, map[key], "existing" end
        if Count(map) >= (tonumber(limit) or math.huge) then return false, nil, "full" end
        map[key] = entry
        return true, entry, "added"
    end

    function engine.DropPending(kind, key)
        local map = kind == "loadout" and engine.loadouts or engine.responses
        local existed = map[key] ~= nil
        map[key] = nil
        return existed
    end

    function engine.PendingExpired(entry, now)
        now = tonumber(now) or 0
        local createdAt = tonumber(entry and entry.createdAt) or now
        local lastActiveAt = tonumber(entry and entry.lastActiveAt) or createdAt
        return now - createdAt > engine.pendingMaxAge
            or now - lastActiveAt > engine.pendingTtl
    end

    function engine.AdvancePending(elapsed, now)
        elapsed, now = tonumber(elapsed) or 0, tonumber(now) or 0
        engine.stats.turns = engine.stats.turns + 1
        for key, entry in pairs(engine.responses) do
            if engine.PendingExpired(entry, now) then
                engine.responses[key] = nil
            elseif not entry.prepared then
                entry.remaining = (tonumber(entry.remaining) or 0) - elapsed
            else
                for _, bucketState in pairs(entry.buckets or {}) do
                    bucketState.remaining =
                        (tonumber(bucketState.remaining) or 0) - elapsed
                end
            end
        end
        for key, entry in pairs(engine.loadouts) do
            if engine.PendingExpired(entry, now) then
                engine.loadouts[key] = nil
            else
                entry.remaining = (tonumber(entry.remaining) or 0) - elapsed
            end
        end
    end

    function engine.NextReadyBucket(entry)
        local cursor = tonumber(entry.bucketCursor) or 0
        for offset = 1, engine.bucketCount * 2 do
            local ordinal = ((cursor + offset - 1) % (engine.bucketCount * 2)) + 1
            local id = ordinal <= engine.bucketCount and "B" .. ordinal
                or "D" .. (ordinal - engine.bucketCount)
            local bucketState = entry.buckets and entry.buckets[id]
            if bucketState and (tonumber(bucketState.remaining) or 0) <= 0 then
                return id, bucketState, ordinal
            end
        end
    end

    function engine.SelectFairUnit(units)
        if #units == 0 then return nil end
        table.sort(units, function(left, right) return left.key < right.key end)
        local selected = units[1]
        if engine.fairCursor then
            for _, unit in ipairs(units) do
                if unit.key > engine.fairCursor then selected = unit; break end
            end
        end
        engine.fairCursor = selected.key
        return selected
    end

    function engine.NextUnit()
        local units = {}
        for key, entry in pairs(engine.responses) do
            if not entry.prepared then
                if (tonumber(entry.remaining) or 0) <= 0 then
                    units[#units + 1] = {
                        key="R|" .. key, type="prepare", entryKey=key, entry=entry,
                    }
                end
            else
                local id, bucketState, ordinal = engine.NextReadyBucket(entry)
                if id then
                    units[#units + 1] = {
                        key="R|" .. key, type="bucket", entryKey=key,
                        entry=entry, id=id, bucketState=bucketState, ordinal=ordinal,
                    }
                end
            end
        end
        for key, entry in pairs(engine.loadouts) do
            if (tonumber(entry.remaining) or 0) <= 0 then
                units[#units + 1] = {
                    key="L|" .. key, type="loadout", entryKey=key, entry=entry,
                }
            end
        end
        return engine.SelectFairUnit(units)
    end

    return engine
end
