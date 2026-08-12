-- Bounded retention for durable Community and DPS mesh state.
--
-- Local/imported builds are never removed automatically. Remote overlay rows
-- are bounded globally, per class, and per author; referenced pages rank first,
-- and orphaned automatic DPS pages are reclaimed. Old exact tombstones are
-- replaced by a monotonic acceptance floor so a stale peer cannot resurrect a
-- deleted remote build after compaction.

Nexus = Nexus or {}
local Retention = {}
Nexus.DataRetention = Retention

local SCHEMA_VERSION = 1
local DEFAULT_LIMITS = {
    remoteOverlay = 300,
    remotePerClass = 50,
    remotePerAuthor = 24,
    characterBestPerCategory = 256,
    personalFingerprints = 128,
    buildBestFingerprints = 128,
    evictionMarkers = 2048,
    evictionMarkerAge = 30 * 24 * 60 * 60,
    exactTombstones = 2048,
    tombstoneAge = 180 * 24 * 60 * 60,
}

local CONFIGURED_LIMITS = {
    remoteOverlay={ key="communityRetentionMaxTotal", min=25, max=5000 },
    remotePerClass={ key="communityRetentionMaxPerClass", min=1, max=500 },
    remotePerAuthor={ key="communityRetentionMaxPerAuthor", min=1, max=250 },
    characterBestPerCategory={ key="communityRetentionCharacterBest", min=25, max=2000 },
    personalFingerprints={ key="communityRetentionPersonalFingerprints", min=16, max=1000 },
    buildBestFingerprints={ key="communityRetentionBuildFingerprints", min=16, max=1000 },
}

local function Count(source)
    local total = 0
    for _ in pairs(type(source) == "table" and source or {}) do
        total = total + 1
    end
    return total
end

local function Copy(source)
    local out = {}
    for key, value in pairs(type(source) == "table" and source or {}) do
        out[key] = value
    end
    return out
end

local function ResolveLimits(database)
    local limits = Copy(DEFAULT_LIMITS)
    local settings = type(database) == "table" and database.settings or nil
    for name, spec in pairs(CONFIGURED_LIMITS) do
        local value = type(settings) == "table" and tonumber(settings[spec.key]) or nil
        if value and value == value and value < math.huge and value > -math.huge then
            value = math.floor(value)
            limits[name] = math.max(spec.min, math.min(spec.max, value))
        end
    end
    limits.remotePerClass = math.min(limits.remotePerClass, limits.remoteOverlay)
    limits.remotePerAuthor = math.min(limits.remotePerAuthor, limits.remoteOverlay)
    return limits
end

local function EpochNow()
    if type(time) ~= "function" then return 0 end
    local ok, value = pcall(time)
    value = ok and tonumber(value) or 0
    return value and value > 0 and value or 0
end

local function PlayerKey(value)
    local name = tostring(value or ""):gsub("%s+", "")
    name = name:match("^([^%-]+)") or name
    return name:lower()
end

local function CurrentOwnerKey()
    local name = UnitName and UnitName("player") or nil
    if not name or name == "" or name == "Unknown" then return nil end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then realm = GetRealmName and GetRealmName() end
    realm = tostring(realm or "unknown"):lower():gsub("%s+", "")
    return PlayerKey(name) .. "@" .. realm
end

local function IsLocalBuild(build)
    if type(build) ~= "table" then return false end
    if build.isMine == true or build.importedSavedBuild == true then return true end
    local owner = CurrentOwnerKey()
    return owner ~= nil and type(build.ownerKey) == "string"
        and build.ownerKey:lower() == owner
end

local function IsLocalDpsRow(row)
    if type(row) ~= "table" then return false end
    local me = UnitName and PlayerKey(UnitName("player")) or ""
    if me ~= "" and PlayerKey(row.player) == me then return true end
    local owner = CurrentOwnerKey()
    return owner ~= nil and type(row.ownerKey) == "string"
        and row.ownerKey:lower() == owner
end

local function RowStamp(row)
    if type(row) ~= "table" then return 0 end
    return tonumber(row.ts or row.lastModified or row.postedAt) or 0
end

local function EntryStamp(value, seen)
    if type(value) ~= "table" then return 0 end
    seen = seen or {}
    if seen[value] then return 0 end
    seen[value] = true
    local newest = RowStamp(value)
    for _, child in pairs(value) do
        if type(child) == "table" then
            newest = math.max(newest, EntryStamp(child, seen))
        end
    end
    return newest
end

local function BetterRow(left, right)
    if left.protected ~= right.protected then return left.protected end
    if left.stamp ~= right.stamp then return left.stamp > right.stamp end
    if left.dps ~= right.dps then return left.dps > right.dps end
    return tostring(left.key) < tostring(right.key)
end

local function TrimCharacterBest(dps, limits)
    local removed = 0
    local source = type(dps) == "table" and dps.characterBest or nil
    if type(source) ~= "table" then return removed end
    for _, category in ipairs({ "dummy", "lk" }) do
        local bucket = source[category]
        if type(bucket) == "table" then
            local rows = {}
            for key, row in pairs(bucket) do
                rows[#rows + 1] = {
                    key=key, row=row, protected=IsLocalDpsRow(row),
                    stamp=RowStamp(row), dps=tonumber(row and row.dps) or 0,
                }
            end
            table.sort(rows, BetterRow)
            local kept = 0
            for _, entry in ipairs(rows) do
                if entry.protected or kept < limits.characterBestPerCategory then
                    kept = kept + 1
                else
                    bucket[entry.key] = nil
                    removed = removed + 1
                end
            end
        end
    end
    return removed
end

local function CharacterFingerprints(dps)
    local protected = {}
    local source = type(dps) == "table" and dps.characterBest or nil
    if type(source) ~= "table" then return protected end
    for _, category in ipairs({ "dummy", "lk" }) do
        for _, row in pairs(type(source[category]) == "table"
            and source[category] or {}) do
            if type(row) == "table" and IsLocalDpsRow(row)
                and type(row.fingerprint) == "string" then
                protected[row.fingerprint] = true
            end
        end
    end
    return protected
end

local function TrimFingerprintMap(source, limit, protected)
    if type(source) ~= "table" then return 0 end
    local rows = {}
    for key, value in pairs(source) do
        rows[#rows + 1] = {
            key=key, protected=protected and protected[key] == true or false,
            stamp=EntryStamp(value), dps=0,
        }
    end
    table.sort(rows, BetterRow)
    local removed, kept = 0, 0
    for _, entry in ipairs(rows) do
        if entry.protected or kept < limit then
            kept = kept + 1
        else
            source[entry.key] = nil
            removed = removed + 1
        end
    end
    return removed
end

local function CollectBuildReferences(dps)
    local referenced, seen = {}, {}
    local function Scan(value)
        if type(value) ~= "table" or seen[value] then return end
        seen[value] = true
        if type(value.buildId) == "string" and value.buildId ~= "" then
            referenced[value.buildId] = true
        end
        for _, child in pairs(value) do
            if type(child) == "table" then Scan(child) end
        end
    end
    if type(dps) == "table" then
        Scan(dps.personalBest)
        Scan(dps.buildBest)
        Scan(dps.characterBest)
    end
    return referenced
end

local function BuildStamp(build)
    return tonumber(build and (build.lastModified or build.postedAt)) or 0
end

local function CompleteBuild(build)
    if type(build) ~= "table" then return false end
    if build.loadoutAvailable ~= nil then return build.loadoutAvailable == true end
    return (type(build.echoes) == "table" and next(build.echoes) ~= nil)
        or (type(build.evidenceKey) == "string" and build.evidenceKey ~= "")
end

local function BetterBuild(left, right)
    if left.referenced ~= right.referenced then return left.referenced end
    if left.complete ~= right.complete then return left.complete end
    if left.stamp ~= right.stamp then return left.stamp > right.stamp end
    return tostring(left.id) < tostring(right.id)
end

local function AuthorKey(value)
    local key = PlayerKey(value)
    return key ~= "" and key or "<unknown>"
end

local function ClassKey(value)
    local key = tostring(value or "UNKNOWN"):upper():gsub("%s+", "")
    return key ~= "" and key or "UNKNOWN"
end

local function RemoveOverlayIds(database, ids)
    if #ids == 0 then return 0 end
    table.sort(ids, function(left, right) return tostring(left) < tostring(right) end)
    local catalog = Nexus and Nexus.BuildCatalog
    if catalog and type(catalog.RemoveOverlayBatch) == "function" then
        local ok, removed = pcall(catalog.RemoveOverlayBatch, ids)
        if ok then return tonumber(removed) or 0 end
    end
    local overlay = type(database.communityBuilds) == "table"
        and database.communityBuilds or {}
    local removed = 0
    for _, id in ipairs(ids) do
        if overlay[id] ~= nil then overlay[id] = nil; removed = removed + 1 end
    end
    return removed
end

local function MarkEvictions(database, overlay, ids)
    if #ids == 0 then return 0 end
    database.communityRetentionEvictions =
        type(database.communityRetentionEvictions) == "table"
        and database.communityRetentionEvictions or {}
    local markers, changed = database.communityRetentionEvictions, 0
    for _, id in ipairs(ids) do
        local stamp = math.max(1, BuildStamp(overlay[id]))
        local prior = tonumber(markers[id]) or 0
        if stamp > prior then markers[id] = stamp; changed = changed + 1 end
    end
    return changed
end

local function PruneOverlay(database, referenced, limits)
    local overlay = type(database.communityBuilds) == "table"
        and database.communityBuilds or {}
    local marked, orphaned = {}, 0
    local remoteBefore = 0
    for id, build in pairs(overlay) do
        if not IsLocalBuild(build) then
            remoteBefore = remoteBefore + 1
            if type(build) == "table" and build.autoDps == true
                and not referenced[id] then
                marked[id] = true
                orphaned = orphaned + 1
            end
        end
    end

    -- First prevent a single class from crowding out the rest of the library.
    -- Referenced builds rank first but are not exempt: maxTotal remains a hard
    -- cap even if a corrupt/hostile dataset creates thousands of references.
    local classes = {}
    for id, build in pairs(overlay) do
        if not marked[id] and not IsLocalBuild(build) then
            local class = ClassKey(type(build) == "table" and build.class)
            classes[class] = classes[class] or {}
            classes[class][#classes[class] + 1] = {
                id=id, referenced=referenced[id] == true,
                stamp=BuildStamp(build), complete=CompleteBuild(build),
            }
        end
    end
    local perClassRemoved = 0
    for _, rows in pairs(classes) do
        table.sort(rows, BetterBuild)
        for index = limits.remotePerClass + 1, #rows do
            local id = rows[index].id
            if not marked[id] then
                marked[id] = true
                perClassRemoved = perClassRemoved + 1
            end
        end
    end

    local groups = {}
    for id, build in pairs(overlay) do
        if not marked[id] and not IsLocalBuild(build) then
            local author = AuthorKey(type(build) == "table" and build.author)
            groups[author] = groups[author] or {}
            groups[author][#groups[author] + 1] = {
                id=id, referenced=referenced[id] == true,
                stamp=BuildStamp(build), complete=CompleteBuild(build),
            }
        end
    end
    local perAuthorRemoved = 0
    for _, rows in pairs(groups) do
        table.sort(rows, BetterBuild)
        for index = limits.remotePerAuthor + 1, #rows do
            local id = rows[index].id
            if not marked[id] then marked[id] = true; perAuthorRemoved = perAuthorRemoved + 1 end
        end
    end

    local candidates = {}
    for id, build in pairs(overlay) do
        if not marked[id] and not IsLocalBuild(build) then
            candidates[#candidates + 1] = {
                id=id, referenced=referenced[id] == true,
                stamp=BuildStamp(build), complete=CompleteBuild(build),
            }
        end
    end
    table.sort(candidates, BetterBuild)
    local globalRemoved = 0
    for index = limits.remoteOverlay + 1, #candidates do
        local id = candidates[index].id
        if not marked[id] then marked[id] = true; globalRemoved = globalRemoved + 1 end
    end

    local referencedKept = 0
    for id in pairs(referenced) do
        if not marked[id] and not IsLocalBuild(overlay[id])
            and overlay[id] ~= nil then referencedKept = referencedKept + 1 end
    end

    local ids = {}
    for id in pairs(marked) do ids[#ids + 1] = id end
    local markersAdded = MarkEvictions(database, overlay, ids)
    local removed = RemoveOverlayIds(database, ids)
    return {
        before=remoteBefore,
        after=math.max(0, remoteBefore - removed),
        removed=removed,
        orphaned=orphaned,
        perClass=perClassRemoved,
        perAuthor=perAuthorRemoved,
        global=globalRemoved,
        referencedKept=referencedKept,
        markersAdded=markersAdded,
    }
end

local function PruneEvictionMarkers(database, now)
    local source = type(database.communityRetentionEvictions) == "table"
        and database.communityRetentionEvictions or {}
    local before = Count(source)
    local floor = tonumber(database.communityBuildRetentionFloor) or 0
    local cutoff = now > DEFAULT_LIMITS.evictionMarkerAge
        and now - DEFAULT_LIMITS.evictionMarkerAge or 0
    local rows = {}
    for id, value in pairs(source) do
        local stamp = tonumber(value) or 0
        rows[#rows + 1] = {
            id=id, stamp=stamp,
            expired=stamp <= floor or (cutoff > 0 and stamp > 0 and stamp <= cutoff),
        }
    end
    table.sort(rows, function(left, right)
        if left.stamp ~= right.stamp then return left.stamp < right.stamp end
        return tostring(left.id) < tostring(right.id)
    end)
    local removed, remaining = 0, before
    for _, row in ipairs(rows) do
        if row.expired then
            source[row.id] = nil
            removed, remaining = removed + 1, remaining - 1
            floor = math.max(floor, row.stamp)
        end
    end
    if remaining > DEFAULT_LIMITS.evictionMarkers then
        for _, row in ipairs(rows) do
            if remaining <= DEFAULT_LIMITS.evictionMarkers then break end
            if source[row.id] ~= nil then
                source[row.id] = nil
                removed, remaining = removed + 1, remaining - 1
                floor = math.max(floor, row.stamp)
            end
        end
    end
    if removed > 0 then database.communityBuildRetentionFloor = floor end
    return {
        before=before, after=math.max(0, before - removed), removed=removed,
        floor=tonumber(database.communityBuildRetentionFloor) or 0,
    }
end

local function TombStamp(value)
    if type(value) == "table" then return tonumber(value.stamp) or 0 end
    return tonumber(value) or 0
end

local function PruneTombstones(database, now)
    local source = type(database.syncTombstones) == "table"
        and database.syncTombstones or {}
    local exactBefore = Count(source)
    local floor = tonumber(database.syncTombstoneFloor) or 0
    local cutoff = now > DEFAULT_LIMITS.tombstoneAge
        and now - DEFAULT_LIMITS.tombstoneAge or 0
    local candidates = {}
    local catalog = Nexus and Nexus.BuildCatalog
    for id, tomb in pairs(source) do
        local stamp = TombStamp(tomb)
        local pending = type(tomb) == "table" and tomb.pending == true
        local bundled = catalog and type(catalog.HasBaseline) == "function"
            and catalog.HasBaseline(id) or false
        if stamp > 0 and not pending and not bundled then
            candidates[#candidates + 1] = {
                id=id, stamp=stamp,
                expired=(stamp <= floor or (cutoff > 0 and stamp <= cutoff)),
            }
        end
    end
    table.sort(candidates, function(left, right)
        if left.stamp ~= right.stamp then return left.stamp < right.stamp end
        return tostring(left.id) < tostring(right.id)
    end)

    local marked, countAfter = {}, exactBefore
    for _, entry in ipairs(candidates) do
        if entry.expired then
            marked[entry.id] = true
            countAfter = countAfter - 1
            floor = math.max(floor, entry.stamp)
        end
    end
    if countAfter > DEFAULT_LIMITS.exactTombstones then
        for _, entry in ipairs(candidates) do
            if countAfter <= DEFAULT_LIMITS.exactTombstones then break end
            if not marked[entry.id] then
                marked[entry.id] = true
                countAfter = countAfter - 1
                floor = math.max(floor, entry.stamp)
            end
        end
    end

    local ids = {}
    for id in pairs(marked) do ids[#ids + 1] = id end
    table.sort(ids, function(left, right) return tostring(left) < tostring(right) end)
    local removed = 0
    if #ids > 0 then
        if catalog and type(catalog.RemoveTombstonesBatch) == "function" then
            local ok, value = pcall(catalog.RemoveTombstonesBatch, ids)
            if ok then removed = tonumber(value) or 0 end
        else
            for _, id in ipairs(ids) do
                if source[id] ~= nil then source[id] = nil; removed = removed + 1 end
            end
        end
    end
    if removed > 0 then database.syncTombstoneFloor = floor end
    return {
        before=exactBefore, after=math.max(0, exactBefore - removed),
        removed=removed, floor=tonumber(database.syncTombstoneFloor) or 0,
    }
end

local function CollectEvidence(database)
    local evidence = Nexus and Nexus.LoadoutEvidence
    if not (evidence and type(evidence.CollectGarbage) == "function") then
        return 0, false
    end
    local ok, summary = pcall(evidence.CollectGarbage, database, false)
    return ok and type(summary) == "table" and tonumber(summary.removed) or 0,
        ok and type(summary) == "table" and summary.blocked == true or false
end

local function BumpDpsAndViews(reason)
    local revisions = Nexus and Nexus.Revisions
    if revisions and type(revisions.Advance) == "function" then
        pcall(revisions.Advance, revisions.DPS_CHANGED, {
            scope="retention", reason=reason,
        })
    end
    local refresh = Nexus and Nexus.ViewRefresh
    if refresh and type(refresh.Request) == "function" then pcall(refresh.Request) end
end

function Retention.Enforce(database, reason)
    database = type(database) == "table" and database or NexusDB
    if type(database) ~= "table" then return nil, "database required" end
    local priorMeta = type(database.dataRetention) == "table"
        and database.dataRetention or nil
    local storedVersion = priorMeta and tonumber(priorMeta.schemaVersion) or nil
    if storedVersion and storedVersion > SCHEMA_VERSION then
        return { readOnly=true, schemaVersion=storedVersion, reason="future retention schema" }
    end
    local catalog = Nexus and Nexus.BuildCatalog
    local catalogSchema = catalog and type(catalog.SchemaVersion) == "function"
        and tonumber(catalog.SchemaVersion()) or 1
    if type(database.buildCatalog) == "table"
        and tonumber(database.buildCatalog.schemaVersion)
        and tonumber(database.buildCatalog.schemaVersion) > catalogSchema then
        return { readOnly=true, schemaVersion=storedVersion,
            reason="future build catalog schema" }
    end
    local evidence = Nexus and Nexus.LoadoutEvidence
    local evidenceSchema = evidence and type(evidence.SchemaVersion) == "function"
        and tonumber(evidence.SchemaVersion()) or 1
    if type(database.loadoutEvidence) == "table"
        and tonumber(database.loadoutEvidence.schemaVersion)
        and tonumber(database.loadoutEvidence.schemaVersion) > evidenceSchema then
        return { readOnly=true, schemaVersion=storedVersion,
            reason="future evidence schema" }
    end
    if type(database.dataCompaction) == "table"
        and tonumber(database.dataCompaction.schemaVersion)
        and tonumber(database.dataCompaction.schemaVersion) > 1 then
        return { readOnly=true, schemaVersion=storedVersion,
            reason="future compaction schema" }
    end
    database.dataRetention = priorMeta or {}
    database.dataRetention.schemaVersion = SCHEMA_VERSION

    local limits = ResolveLimits(database)
    local dps = type(database.dpsCapture) == "table" and database.dpsCapture or nil
    local characterRemoved = TrimCharacterBest(dps, limits)
    local fingerprints = CharacterFingerprints(dps)
    local personalRemoved = dps and TrimFingerprintMap(
        dps.personalBest, limits.personalFingerprints, fingerprints) or 0
    local buildBestRemoved = dps and TrimFingerprintMap(
        dps.buildBest, limits.buildBestFingerprints, nil) or 0
    local referenced = CollectBuildReferences(dps)
    local overlay = PruneOverlay(database, referenced, limits)
    local now = EpochNow()
    local evictions = PruneEvictionMarkers(database, now)
    local tombstones = PruneTombstones(database, now)
    local dpsRemoved = characterRemoved + personalRemoved + buildBestRemoved
    local evidenceRemoved, evidenceBlocked = 0, false
    if dpsRemoved > 0 or overlay.removed > 0 or tombstones.removed > 0 then
        evidenceRemoved, evidenceBlocked = CollectEvidence(database)
    end
    if dpsRemoved > 0 then BumpDpsAndViews(reason or "data retention") end

    local summary = {
        schemaVersion=SCHEMA_VERSION,
        reason=tostring(reason or "maintenance"):sub(1, 80),
        characterBestRemoved=characterRemoved,
        personalRemoved=personalRemoved,
        buildBestRemoved=buildBestRemoved,
        overlayBefore=overlay.before,
        overlayAfter=overlay.after,
        overlayRemoved=overlay.removed,
        orphanAutoBuildsRemoved=overlay.orphaned,
        perClassRemoved=overlay.perClass,
        perAuthorRemoved=overlay.perAuthor,
        globalRemoved=overlay.global,
        referencedBuildsKept=overlay.referencedKept,
        limits=Copy(limits),
        evictionMarkersAdded=overlay.markersAdded,
        evictionMarkersBefore=evictions.before,
        evictionMarkersAfter=evictions.after,
        evictionMarkersRemoved=evictions.removed,
        buildRetentionFloor=evictions.floor,
        tombstonesBefore=tombstones.before,
        tombstonesAfter=tombstones.after,
        tombstonesRemoved=tombstones.removed,
        tombstoneFloor=tombstones.floor,
        evidenceRemoved=evidenceRemoved,
        evidenceGcBlocked=evidenceBlocked,
    }
    local changed = dpsRemoved > 0 or overlay.removed > 0
        or evictions.removed > 0 or tombstones.removed > 0
        or evidenceRemoved > 0
    if changed or type(database.dataRetention.last) ~= "table" then
        database.dataRetention.lastRun = now
        database.dataRetention.last = Copy(summary)
    end
    return summary
end

function Retention.Init(database)
    return Retention.Enforce(database, "startup")
end

function Retention.Request(reason)
    local scheduler = Nexus and Nexus.Scheduler
    if not (scheduler and scheduler.IsInitialized and scheduler.IsInitialized()
        and type(scheduler.After) == "function") then
        return false, "scheduler unavailable"
    end
    if type(scheduler.Pending) == "function"
        and scheduler.Pending("data-retention.enforce") then
        return true
    end
    return scheduler.After("data-retention.enforce", 3, function()
        Retention.Enforce(NexusDB, reason or "scheduled")
    end)
end

function Retention.AllowsRemoteRevision(_, stamp, database, buildId)
    database = type(database) == "table" and database or NexusDB
    local tombstoneFloor = type(database) == "table"
        and tonumber(database.syncTombstoneFloor) or 0
    local buildFloor = type(database) == "table"
        and tonumber(database.communityBuildRetentionFloor) or 0
    local marker = type(database) == "table"
        and type(database.communityRetentionEvictions) == "table"
        and tonumber(database.communityRetentionEvictions[buildId]) or 0
    return (tonumber(stamp) or 0) > math.max(
        tombstoneFloor or 0, buildFloor or 0, marker or 0)
end

function Retention.ReleaseSupersededAutoBuild(buildId, database)
    if type(buildId) ~= "string" or buildId == "" then return false end
    database = type(database) == "table" and database or NexusDB
    if type(database) ~= "table" then return false end
    local overlay = type(database.communityBuilds) == "table"
        and database.communityBuilds or {}
    local build = overlay[buildId]
    if type(build) ~= "table" or build.autoDps ~= true or IsLocalBuild(build) then
        return false
    end
    if CollectBuildReferences(database.dpsCapture)[buildId] then return false end
    MarkEvictions(database, overlay, { buildId })
    local removed = RemoveOverlayIds(database, { buildId })
    if removed > 0 then CollectEvidence(database); return true end
    return false
end

function Retention.Limits(database)
    database = type(database) == "table" and database or NexusDB
    return ResolveLimits(database)
end

function Retention.Stats(database)
    database = type(database) == "table" and database or NexusDB
    local meta = type(database) == "table" and database.dataRetention or nil
    return type(meta) == "table" and Copy(meta.last) or nil
end

function Retention.SchemaVersion()
    return SCHEMA_VERSION
end
