-- Durable diagnostic histories backed by the established NexusDB arrays.
--
-- These accessors retain observations only. They deliberately know nothing
-- about automation, represented-data revisions, or Sync queues. Existing
-- array names and record fields remain compatible with old saves and exports.

Nexus = Nexus or {}

local Logs = {}
Nexus.DiagnosticLogs = Logs

local DEFINITIONS = {
    decision = {key="decisionLog", cap=200},
    runAudit = {key="runAudit", cap=240},
    autoLock = {key="autoLockLog", cap=150},
    uiProbe = {key="uiProbeLog", cap=120},
}
local ORDER = {"decision", "runAudit", "autoLock", "uiProbe"}
local META_SCHEMA = 1
local MAX_COPY_DEPTH = 16
local cachedDB = nil
local cachedHistories = {}

local function SafeError(value)
    local safe = Nexus.DiagnosticHistory and Nexus.DiagnosticHistory.SafeText
    if type(safe) == "function" then return safe(value, 512) end
    local ok, text = pcall(tostring, value)
    return ok and tostring(text or "") or "unprintable diagnostic error"
end

local function IsArrayIndex(key)
    return type(key) == "number" and key >= 1 and key == math.floor(key)
end

local function CopyValue(value, seen, depth)
    local kind = type(value)
    if kind == "nil" or kind == "string" or kind == "number"
        or kind == "boolean" then
        return value
    end
    if kind ~= "table" then return SafeError(value) end
    if seen[value] then return "<cycle>" end
    if depth >= MAX_COPY_DEPTH then return "<depth-limit>" end

    seen[value] = true
    local copy = {}
    for key, child in pairs(value) do
        local keyKind = type(key)
        local copiedKey = (keyKind == "string" or keyKind == "number"
            or keyKind == "boolean") and key or SafeError(key)
        if copy[copiedKey] == nil then
            copy[copiedKey] = CopyValue(child, seen, depth + 1)
        end
    end
    seen[value] = nil
    return copy
end

local function DefensiveCopy(value)
    local ok, copy = pcall(CopyValue, value, {}, 0)
    if not ok then return nil, SafeError(copy) end
    return copy
end

local function CurrentDB(database)
    if type(database) == "table" then return database end
    if type(NexusDB) ~= "table" then NexusDB = {} end
    return NexusDB
end

local function Number(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge
        or number == -math.huge then return 0 end
    return number
end

local function Metadata(database)
    local meta = database.diagnosticMeta
    if type(meta) ~= "table" then
        meta = {}
        database.diagnosticMeta = meta
    end
    if meta.schemaVersion == nil then meta.schemaVersion = META_SCHEMA end
    if type(meta.histories) ~= "table" then meta.histories = {} end
    return meta
end

local function HistoryMeta(database, name, definition)
    local histories = Metadata(database).histories
    local meta = histories[name]
    if type(meta) ~= "table" then
        meta = {}
        histories[name] = meta
    end
    meta.key = definition.key
    meta.cap = definition.cap
    return meta
end

local function Bump(meta, key, amount)
    meta[key] = Number(meta[key]) + (tonumber(amount) or 1)
end

local function CopyExtensions(source, target)
    for key, value in pairs(source) do
        if not IsArrayIndex(key) then target[key] = value end
    end
end

local function NormalizeUnsafe(name, database)
    local definition = DEFINITIONS[name]
    if not definition then error("unknown diagnostic history: " .. SafeError(name)) end
    local db = CurrentDB(database)
    local meta = HistoryMeta(db, name, definition)
    local source = db[definition.key]
    if type(source) ~= "table" then
        db[definition.key] = {}
        Bump(meta, "repaired", 1)
        meta.retained = 0
        source = db[definition.key]
        if cachedDB ~= db then cachedDB, cachedHistories = db, {} end
        cachedHistories[name] = source
        return db, source, meta, definition
    end

    local indexed = {}
    for key, value in pairs(source) do
        if IsArrayIndex(key) then
            indexed[#indexed + 1] = {key=key, value=value}
        end
    end
    table.sort(indexed, function(left, right) return left.key < right.key end)

    local records = {}
    local repairs = 0
    local malformed = 0
    for position, item in ipairs(indexed) do
        if item.key ~= position then repairs = repairs + 1 end
        if type(item.value) == "table" then
            records[#records + 1] = item.value
        else
            repairs = repairs + 1
            malformed = malformed + 1
        end
    end
    local overflow = math.max(0, #records - definition.cap)
    if overflow > 0 then repairs = repairs + overflow end

    if repairs > 0 then
        local normalized = {}
        CopyExtensions(source, normalized)
        local first = overflow + 1
        for index = first, #records do
            normalized[#normalized + 1] = records[index]
        end
        db[definition.key] = normalized
        source = normalized
        Bump(meta, "repaired", repairs)
        if malformed + overflow > 0 then
            Bump(meta, "dropped", malformed + overflow)
        end
    end
    meta.retained = #source
    if cachedDB ~= db then cachedDB, cachedHistories = db, {} end
    cachedHistories[name] = source
    return db, source, meta, definition
end

local function EnsureUnsafe(name)
    local definition = DEFINITIONS[name]
    if not definition then error("unknown diagnostic history: " .. SafeError(name)) end
    local db = CurrentDB()
    local source = db[definition.key]
    if cachedDB == db and cachedHistories[name] == source
        and type(source) == "table" then
        local meta = HistoryMeta(db, name, definition)
        meta.retained = #source
        return db, source, meta, definition
    end
    return NormalizeUnsafe(name, db)
end

local function TrimNewest(database, source, definition, overflow)
    local trimmed = {}
    CopyExtensions(source, trimmed)
    local first = overflow + 1
    for index = first, #source do
        trimmed[#trimmed + 1] = source[index]
    end
    database[definition.key] = trimmed
    return trimmed
end

local function Protected(defaultValue, callback, ...)
    local ok, first, second = pcall(callback, ...)
    if not ok then return defaultValue, SafeError(first) end
    return first, second
end

function Logs.Init(database)
    return Protected(false, function()
        local db = CurrentDB(database)
        for _, name in ipairs(ORDER) do NormalizeUnsafe(name, db) end
        return true
    end)
end

function Logs.Append(name, record)
    return Protected(false, function()
        if type(record) ~= "table" then return false, "record must be a table" end
        local db, history, meta, definition = EnsureUnsafe(name)
        local copy, copyError = DefensiveCopy(record)
        if not copy then return false, copyError end
        history[#history + 1] = copy
        Bump(meta, "appended", 1)
        local overflow = math.max(0, #history - definition.cap)
        if overflow > 0 then
            history = TrimNewest(db, history, definition, overflow)
            cachedHistories[name] = history
            Bump(meta, "dropped", overflow)
        end
        meta.retained = #history
        return true
    end)
end

function Logs.UpdateLast(name, updater)
    return Protected(false, function()
        if type(updater) ~= "function" then return false, "updater must be a function" end
        local _, history, meta = EnsureUnsafe(name)
        if #history == 0 then return false, "history is empty" end
        local copy, copyError = DefensiveCopy(history[#history])
        if not copy then return false, copyError end
        local okUpdate, accepted = pcall(updater, copy)
        if not okUpdate then return false, SafeError(accepted) end
        if accepted == false then return false, "update rejected" end
        history[#history] = copy
        Bump(meta, "updated", 1)
        return true
    end)
end

function Logs.Snapshot(name)
    return Protected({}, function()
        local _, history = NormalizeUnsafe(name)
        local copy, copyError = DefensiveCopy(history)
        if not copy then return {}, copyError end
        return copy
    end)
end

function Logs.Clear(name)
    return Protected(false, function()
        local definition = DEFINITIONS[name]
        if not definition then return false, "unknown diagnostic history" end
        local db = CurrentDB()
        db[definition.key] = {}
        if cachedDB ~= db then cachedDB, cachedHistories = db, {} end
        cachedHistories[name] = db[definition.key]
        local meta = HistoryMeta(db, name, definition)
        meta.retained, meta.appended, meta.dropped = 0, 0, 0
        meta.repaired, meta.updated = 0, 0
        Bump(meta, "clears", 1)
        return true
    end)
end

function Logs.ClearAll()
    return Protected(false, function()
        local db = CurrentDB()
        for _, name in ipairs(ORDER) do
            local definition = DEFINITIONS[name]
            db[definition.key] = {}
            if cachedDB ~= db then cachedDB, cachedHistories = db, {} end
            cachedHistories[name] = db[definition.key]
            local meta = HistoryMeta(db, name, definition)
            meta.retained, meta.appended, meta.dropped = 0, 0, 0
            meta.repaired, meta.updated = 0, 0
            Bump(meta, "clears", 1)
        end
        return true
    end)
end

function Logs.Stats(name)
    return Protected({available=false, name=name}, function()
        local _, history, meta, definition = NormalizeUnsafe(name)
        return {
            available=true,
            name=name,
            key=definition.key,
            cap=definition.cap,
            retained=#history,
            appended=Number(meta.appended),
            dropped=Number(meta.dropped),
            repaired=Number(meta.repaired),
            updated=Number(meta.updated),
            clears=Number(meta.clears),
        }
    end)
end

function Logs.Definitions()
    local definitions = {}
    for _, name in ipairs(ORDER) do
        definitions[name] = {key=DEFINITIONS[name].key, cap=DEFINITIONS[name].cap}
    end
    return definitions
end
