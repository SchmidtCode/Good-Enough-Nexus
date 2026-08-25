-- Canonical pure ranking and identity rules shared by DPS storage, retention,
-- projections, and presentation adapters. No WoW calls or SavedVariables.

Nexus = Nexus or {}

local Ranking = {}
Nexus.DpsRanking = Ranking

local function Text(value)
    return tostring(value == nil and "" or value)
end

function Ranking.PlayerKey(value)
    return Text(value):lower():gsub("%s+", "")
end

function Ranking.NormalizeRealm(value)
    local realm = Ranking.PlayerKey(value)
    if realm == "" or realm == "unknown" then return nil end
    return realm
end

function Ranking.TypedIdentity(value)
    return type(value) .. ":" .. Text(value)
end

function Ranking.CharacterKey(row, fallback)
    row = type(row) == "table" and row or {}
    if type(row.ownerKey) == "string" then
        local name, realm = row.ownerKey:match("^([^@]+)@([^@]+)$")
        name = Ranking.PlayerKey(name)
        realm = Ranking.NormalizeRealm(realm)
        if name ~= "" and realm then return name .. "@" .. realm end
    end
    local realm = Ranking.NormalizeRealm(row.realm)
    local name = Ranking.PlayerKey(row.player or fallback)
    if realm and name ~= "" then
        name = name:match("^([^-]+)") or name
        return name .. "@" .. realm
    end
    return name
end

function Ranking.RecordIdentity(row)
    if type(row) ~= "table" then return nil end
    if row.fingerprint ~= nil then return Ranking.TypedIdentity(row.fingerprint) end
    if row.buildId ~= nil then return Ranking.TypedIdentity(row.buildId) end
    return nil
end

function Ranking.RecordKey(row, fallback)
    if type(row) ~= "table" then return "" end
    local identity = Ranking.RecordIdentity(row)
    if not identity then return "" end
    return Ranking.CharacterKey(row, fallback) .. "|" .. identity
end

local function RowOf(entry, reader)
    if type(reader) == "function" then return reader(entry) end
    return entry
end

function Ranking.PairCategories(dummyEntries, lkEntries, reader)
    local dummyByIdentity, dummyByBuild = {}, {}
    for _, entry in ipairs(type(dummyEntries) == "table" and dummyEntries or {}) do
        local row = RowOf(entry, reader)
        if type(row) == "table" then
            local character = Ranking.CharacterKey(row)
            local identity = Ranking.RecordIdentity(row)
            if identity then dummyByIdentity[character .. "|" .. identity] = entry end
            if row.buildId ~= nil then
                dummyByBuild[character .. "|"
                    .. Ranking.TypedIdentity(row.buildId)] = entry
            end
        end
    end

    local out = {}
    for _, lkEntry in ipairs(type(lkEntries) == "table" and lkEntries or {}) do
        local lkRow = RowOf(lkEntry, reader)
        if type(lkRow) == "table" then
            local character = Ranking.CharacterKey(lkRow)
            local identity = Ranking.RecordIdentity(lkRow)
            local dummyEntry = identity
                and dummyByIdentity[character .. "|" .. identity] or nil
            if not dummyEntry and lkRow.buildId ~= nil then
                dummyEntry = dummyByBuild[character .. "|"
                    .. Ranking.TypedIdentity(lkRow.buildId)]
            end
            if dummyEntry then
                out[#out + 1] = {
                    key=character .. "|"
                        .. tostring(identity or Ranking.TypedIdentity(lkRow.buildId)),
                    character=character,
                    identity=identity,
                    dummy=dummyEntry,
                    lk=lkEntry,
                    dummyRow=RowOf(dummyEntry, reader),
                    lkRow=lkRow,
                }
            end
        end
    end
    return out
end
function Ranking.Summary(dummyRows, lkRows)
    local summary = {dummy=0,lk=0,best=0,average=0,count=0}
    for category, rows in pairs({dummy=dummyRows,lk=lkRows}) do
        for _, row in ipairs(type(rows) == "table" and rows or {}) do
            local value = tonumber(row and (row.dps or row.value or row.amount)) or 0
            if value > summary[category] then summary[category] = value end
        end
        if summary[category] > 0 then summary.count = summary.count + 1 end
    end
    summary.best = math.max(summary.dummy, summary.lk)
    if summary.count == 2 then
        summary.average = (summary.dummy + summary.lk) / 2
    elseif summary.count == 1 then
        summary.average = summary.best
    end
    return summary
end

function Ranking.CombinedRows(dummyRows, lkRows)
    local out = {}
    for _, pair in ipairs(Ranking.PairCategories(dummyRows, lkRows)) do
        local drow, lrow = pair.dummyRow, pair.lkRow
        local average = ((tonumber(drow.dps) or 0)
            + (tonumber(lrow.dps) or 0)) / 2
        out[#out + 1] = {
            player=lrow.player, dps=average, average=average,
            dummyDps=drow.dps, lkDps=lrow.dps,
            dummyDuration=drow.duration, lkDuration=lrow.duration,
            level=math.max(tonumber(drow.level) or 0, tonumber(lrow.level) or 0),
            ts=math.min(tonumber(drow.ts) or 0, tonumber(lrow.ts) or 0),
            category="combined",
            ownerKey=lrow.ownerKey or drow.ownerKey,
            realm=lrow.realm or drow.realm,
            fingerprint=lrow.fingerprint or drow.fingerprint,
            echoes=lrow.echoes or drow.echoes,
            lockedEchoes=lrow.lockedEchoes or drow.lockedEchoes,
            buildId=lrow.buildId or drow.buildId,
            build=lrow.build or drow.build,
        }
    end
    table.sort(out, function(left, right)
        if left.average ~= right.average then return left.average > right.average end
        return tostring(left.player):lower() < tostring(right.player):lower()
    end)
    return out
end
