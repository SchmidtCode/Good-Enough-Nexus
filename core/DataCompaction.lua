-- Nexus: ordered, idempotent SavedVariables exact-evidence compaction.
--
-- Compaction is conservative: an inline array is removed only after the pool
-- round trip is deeply identical to the established public shape. Malformed,
-- conflicting, or merely noncanonical rows keep their inline evidence.

Nexus = Nexus or {}
local Compaction = {}
Nexus.DataCompaction = Compaction

local SCHEMA_VERSION = 1
local MIGRATION_VERSION = 1

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do
        out[DeepCopy(key, seen)] = DeepCopy(child, seen)
    end
    return out
end

local function DeepEqual(left, right, seen)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then return false end
    seen = seen or {}
    if seen[left] then return seen[left] == right end
    seen[left] = right
    for key, value in pairs(left) do
        if not DeepEqual(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function Count(source)
    local n = 0
    for _ in pairs(source or {}) do n = n + 1 end
    return n
end

local function Add(stats, key, amount)
    if type(stats) ~= "table" then return end
    stats[key] = (tonumber(stats[key]) or 0) + (amount or 1)
end

local function Evidence()
    return Nexus and Nexus.LoadoutEvidence
end

local function Meta(database)
    database.dataCompaction = type(database.dataCompaction) == "table"
        and database.dataCompaction or {}
    local meta = database.dataCompaction
    if meta.schemaVersion == nil then meta.schemaVersion = SCHEMA_VERSION end
    return meta
end

function Compaction.Enabled(database)
    database = type(database) == "table" and database
        or type(NexusDB) == "table" and NexusDB or nil
    local meta = database and database.dataCompaction
    return type(meta) == "table"
        and tonumber(meta.schemaVersion) == SCHEMA_VERSION
        and (tonumber(meta.version) or 0) >= MIGRATION_VERSION
end

local function LoadoutFingerprint(source)
    local counts = {}
    for _, echo in ipairs(type(source) == "table" and source or {}) do
        if not (echo and echo.locked) then
            local spellId = tonumber(echo and (echo.spellId or echo.id))
            local stacks = tonumber(echo
                and (echo.stacks or echo.count or echo.stack)) or 1
            if spellId and stacks > 0 then
                counts[spellId] = (counts[spellId] or 0) + stacks
            end
        end
    end
    local ids = {}
    for spellId in pairs(counts) do ids[#ids + 1] = spellId end
    table.sort(ids)
    local parts = {}
    for _, spellId in ipairs(ids) do
        parts[#parts + 1] = tostring(spellId) .. "x"
            .. tostring(counts[spellId])
    end
    return #parts > 0 and table.concat(parts, ",") or nil
end

local function CompactField(row, inlineField, referenceField, options,
                            style, force, stats)
    if type(row) ~= "table" then return false, false end
    if not force and not Compaction.Enabled() then return false, false end
    local inline = row[inlineField]
    if type(inline) ~= "table" or next(inline) == nil then
        return false, false
    end
    local evidence = Evidence()
    if not (evidence and evidence.Fingerprint and evidence.Intern) then
        Add(stats, "retainedUnavailable")
        return false, false
    end

    Add(stats, "arraysSeen")
    Add(stats, "beforeInlineEchoRows", #inline)
    local claimed = row[referenceField]
    local exact = evidence.Fingerprint(inline, options)
    if not exact then
        Add(stats, "retainedMalformed")
        Add(stats, "afterInlineEchoRows", #inline)
        return false, false
    end
    local claimConflict = claimed ~= nil and tostring(claimed) ~= exact
    local semanticFingerprint = inlineField == "echoes"
        and LoadoutFingerprint(inline) or nil
    local fingerprintConflict = type(row.fingerprint) == "string"
        and row.fingerprint ~= "" and row.fingerprint:sub(1, 1) ~= "@"
        and semanticFingerprint ~= nil
        and tostring(row.fingerprint) ~= semanticFingerprint
    local reference = evidence.Intern(inline, claimed, options)
    if not reference then
        Add(stats, "retainedConflicts")
        Add(stats, "afterInlineEchoRows", #inline)
        return false, false
    end
    if claimConflict or fingerprintConflict then
        Add(stats, "retainedConflicts")
        Add(stats, "afterInlineEchoRows", #inline)
        return false, false
    end

    local resolved
    if style == "build" then
        local materialized = evidence.ResolveBuildRow({
            evidenceKey=reference,
        })
        resolved = materialized and materialized.echoes
    else
        resolved = evidence.ResolveDpsEchoes({
            [referenceField]=reference,
        }, inlineField == "lockedEchoes")
    end
    if not DeepEqual(inline, resolved) then
        Add(stats, "retainedNonCanonical")
        Add(stats, "afterInlineEchoRows", #inline)
        return false, false
    end

    if row[referenceField] ~= reference then
        row[referenceField] = reference
        Add(stats, "referencesWritten")
    end
    row[inlineField] = nil
    Add(stats, "arraysCompacted")
    Add(stats, "removedInlineEchoRows", #inline)
    return true, true
end

function Compaction.CompactBuildRow(row, force, stats)
    return CompactField(row, "echoes", "evidenceKey", nil,
        "build", force == true, stats)
end

function Compaction.CompactDpsRow(row, force, stats)
    if type(row) ~= "table" then return false, 0 end
    local changed, compacted = false, 0
    local fieldChanged, fieldCompacted = CompactField(
        row, "echoes", "evidenceKey", nil, "dps", force == true, stats)
    changed = fieldChanged or changed
    if fieldCompacted then compacted = compacted + 1 end
    fieldChanged, fieldCompacted = CompactField(
        row, "lockedEchoes", "lockedEvidenceKey", {forceLocked=true},
        "dps", force == true, stats)
    changed = fieldChanged or changed
    if fieldCompacted then compacted = compacted + 1 end
    return changed, compacted
end

local function WalkDpsRows(value, visitor, seen)
    if type(value) ~= "table" then return 0 end
    seen = seen or {}
    if seen[value] then return 0 end
    seen[value] = true
    local count = 0
    if tonumber(value.dps) ~= nil then
        count = 1
        visitor(value)
    end
    for key, child in pairs(value) do
        if key ~= "echoes" and key ~= "lockedEchoes"
            and type(child) == "table" then
            count = count + WalkDpsRows(child, visitor, seen)
        end
    end
    return count
end

local function SortedKeys(source)
    local keys = {}
    for key in pairs(source or {}) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right)
        local lt, rt = type(left), type(right)
        if lt ~= rt then return lt < rt end
        return tostring(left) < tostring(right)
    end)
    return keys
end

local function Advance(event, reason)
    local revisions = Nexus and Nexus.Revisions
    if revisions and revisions.Advance and event then
        pcall(revisions.Advance, event, {scope="all", reason=reason})
    end
end

local function Run(database)
    local evidence = Evidence()
    local evidenceStats = evidence and evidence.Stats and evidence.Stats() or nil
    if not evidenceStats then error("loadout evidence pool unavailable") end
    if tonumber(evidenceStats.schemaVersion)
        and tonumber(evidenceStats.schemaVersion) > evidence.SchemaVersion() then
        error("future evidence schema is read-only")
    end

    local stats = {
        migrationVersion=MIGRATION_VERSION,
        overlayRecordsBefore=Count(database.communityBuilds),
        poolEntriesBefore=tonumber(evidenceStats.entries) or 0,
        arraysSeen=0, arraysCompacted=0, referencesWritten=0,
        beforeInlineEchoRows=0, afterInlineEchoRows=0,
        removedInlineEchoRows=0, retainedMalformed=0,
        retainedConflicts=0, retainedNonCanonical=0,
        retainedUnavailable=0,
    }
    local buildChanged, dpsChanged = false, false
    local overlay = type(database.communityBuilds) == "table"
        and database.communityBuilds or {}
    for _, id in ipairs(SortedKeys(overlay)) do
        local changed = Compaction.CompactBuildRow(overlay[id], true, stats)
        buildChanged = changed or buildChanged
    end

    local dps = type(database.dpsCapture) == "table"
        and database.dpsCapture or {}
    stats.dpsRecordsBefore = WalkDpsRows(dps, function(row)
        local changed = Compaction.CompactDpsRow(row, true, stats)
        dpsChanged = changed or dpsChanged
    end)
    stats.overlayRecordsAfter = Count(database.communityBuilds)
    stats.dpsRecordsAfter = WalkDpsRows(dps, function() end)

    local gc = evidence.CollectGarbage
        and evidence.CollectGarbage(database, false) or {removed=0, retained=0}
    if gc.blocked then error(gc.reason or "evidence GC blocked") end
    stats.gcRemoved = tonumber(gc.removed) or 0
    stats.gcRetained = tonumber(gc.retained) or 0
    stats.gcReferences = tonumber(gc.references) or 0
    stats.poolEntriesAfter = evidence.Stats().entries
    stats.recordCountsUnchanged = stats.overlayRecordsBefore == stats.overlayRecordsAfter
        and stats.dpsRecordsBefore == stats.dpsRecordsAfter

    local revisions = Nexus and Nexus.Revisions
    if buildChanged then
        Advance(revisions and revisions.BUILD_LIBRARY_CHANGED,
            "exact evidence compaction")
    end
    if dpsChanged then
        Advance(revisions and revisions.DPS_CHANGED,
            "exact evidence compaction")
    end
    return stats
end

function Compaction.Init(database)
    database = type(database) == "table" and database or {}
    local meta = Meta(database)
    if tonumber(meta.schemaVersion)
        and tonumber(meta.schemaVersion) > SCHEMA_VERSION then
        return {blocked=true, reason="future compaction schema is read-only"}
    end
    if (tonumber(meta.version) or 0) >= MIGRATION_VERSION then
        return DeepCopy(meta.last or {migrationVersion=MIGRATION_VERSION}), false
    end
    local ok, result = pcall(Run, database)
    if not ok then
        meta.lastError = tostring(result):sub(1, 500)
        return {blocked=true, reason=meta.lastError}, false
    end
    meta.version = MIGRATION_VERSION
    meta.last = DeepCopy(result)
    meta.lastError = nil
    return DeepCopy(result), true
end

function Compaction.CollectGarbage(database, dryRun)
    local evidence = Evidence()
    if not (evidence and evidence.CollectGarbage) then
        return {blocked=true, reason="loadout evidence pool unavailable"}
    end
    return evidence.CollectGarbage(database, dryRun == true)
end

function Compaction.Stats(database)
    database = type(database) == "table" and database
        or type(NexusDB) == "table" and NexusDB or {}
    local meta = type(database.dataCompaction) == "table"
        and database.dataCompaction or {}
    return DeepCopy(meta.last or {})
end

function Compaction.Version()
    return MIGRATION_VERSION
end
