-- Nexus: core/Store.lua
-- SavedVariables ownership ONLY (global: NexusDB): settings
-- plus per-character safety state. core/ may touch SavedVariables and
-- UnitName; nothing else. Main calls Store.Init() at ADDON_LOADED --
-- never earlier (the client replaces the global when the file loads).

Nexus = Nexus or {}
local Store = {}
Nexus.Store = Store

-- Versioned shape changes are additive and ordered. User preferences,
-- per-character safety state, and unknown/future fields are never rebuilt
-- merely because the shipped defaults or schema version changed.
local SETTINGS_VERSION = 2
local LEGACY_MIGRATION_NAMESPACE = "nexusStoreMigrations"
local LEGACY_MIGRATION_KEY = "wishlistRealizerDB"
local LEGACY_MIGRATION_VERSION = 1

local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = DeepCopy(v) end
    return out
end

local function FillMissing(target, defaults)
    if type(target) ~= "table" or type(defaults) ~= "table" then return end
    for key, default in pairs(defaults) do
        local current = target[key]
        if current == nil then
            target[key] = DeepCopy(default)
        elseif type(current) == "table" and type(default) == "table" then
            -- Lists are atomic user choices: an explicitly empty anchorNames
            -- list must not be repopulated from shipped numeric entries.
            local isList = false
            for defaultKey in pairs(default) do
                if type(defaultKey) == "number" then isList = true; break end
            end
            if not isList then FillMissing(current, default) end
        end
    end
end

local function FreshState()
    return {
        tomeTogglePending = {}, -- [leverId] = { t=sentAtTime, want=bool }
        priorAutoAccept = nil,  -- autoAcceptLoadoutEchoes before we touched it
        flagDemotions = {},     -- [flagName] = reason (runtime self-check)
        recordedPicks = {},     -- [spellId] = count (session; adapter-managed)
        loadoutWishlists = {},  -- [numbered loadout slot] = stable designed-wishlist identity
    }
end

local function EnsureStateShape(state)
    if type(state) ~= "table" then return FreshState() end
    for _, field in ipairs({
        "tomeTogglePending", "flagDemotions", "recordedPicks", "loadoutWishlists",
    }) do
        if type(state[field]) ~= "table" then state[field] = {} end
    end
    return state
end

-- Returned while the real store is unusable (pre-Init call, or
-- UnitName not yet real -- addendum B5: never latch a bad char key).
-- Deliberately never merged into the persisted store.
local transientState
local transientSettings

local function NormalizeVersion(value)
    value = tonumber(value)
    if not value or value ~= value or value < 0 or value >= math.huge
        or value ~= math.floor(value) then
        return 0
    end
    return value
end

local function ReadLegacyMigrationMarker(db)
    local migrations = rawget(db, LEGACY_MIGRATION_NAMESPACE)
    if migrations == nil then return nil, nil end
    if type(migrations) ~= "table" then
        error("NexusDB legacy migration namespace is owned by an incompatible value")
    end

    local marker = rawget(migrations, LEGACY_MIGRATION_KEY)
    if marker == nil then return nil, migrations end
    local version = type(marker) == "table" and tonumber(marker.version) or nil
    if type(marker) ~= "table" or marker.completed ~= true
        or not version or version ~= version or version >= math.huge
        or version ~= math.floor(version) or version < 1 then
        error("NexusDB legacy migration marker is malformed")
    end
    return marker, migrations
end

-- Select an authority without clearing either SavedVariables name. A shared
-- table is an interrupted adoption retry: once NexusDB is rebound, the next
-- call must finish against that exact root instead of reclassifying it.
local function SelectDatabaseForLegacyMigration()
    local current = NexusDB
    local legacy = WishlistRealizerDB

    if current ~= nil and type(current) ~= "table" then
        error("NexusDB is malformed; preserving it for recovery")
    end

    if type(current) == "table" then
        local marker = ReadLegacyMigrationMarker(current)
        if marker then return current, marker.decision or "completed" end
    end

    if legacy ~= nil and type(legacy) ~= "table" then
        error("WishlistRealizerDB is malformed; preserving it for recovery")
    end

    if type(current) == "table" and current == legacy then
        return current, "adoptedLegacy"
    end

    if type(current) == "table" and next(current) ~= nil then
        return current, "keptCurrent"
    end

    if type(legacy) == "table" and next(legacy) ~= nil then
        ReadLegacyMigrationMarker(legacy)
        return legacy, "adoptedLegacy"
    end

    local db = type(current) == "table" and current or {}
    ReadLegacyMigrationMarker(db)
    return db, legacy == nil and "noLegacy" or "ignoredEmptyLegacy"
end

local function CompleteLegacyMigration(db, decision)
    -- Re-read after every ordered owner. A future owner or interrupted write
    -- that occupied this namespace must block legacy release, not be replaced.
    local marker, migrations = ReadLegacyMigrationMarker(db)
    if not marker then
        if not migrations then
            migrations = {}
            db[LEGACY_MIGRATION_NAMESPACE] = migrations
        end
        marker = {
            version=LEGACY_MIGRATION_VERSION,
            completed=true,
            decision=decision,
        }
        migrations[LEGACY_MIGRATION_KEY] = marker
    end

    -- The durable marker is visible before the old global is released. If a
    -- later load sees the marker and a reintroduced legacy value, current wins.
    WishlistRealizerDB = nil
end

local function MigratePendingToggleRecords(db)
    for _, state in pairs(db.chars) do
        local pending = type(state) == "table" and state.tomeTogglePending
        if type(pending) == "table" then
            for lever, value in pairs(pending) do
                if type(value) == "number" and value == value
                    and value < math.huge and value > -math.huge then
                    pending[lever] = { t=value, want=true }
                end
            end
        end
    end
end

local MIGRATIONS = {
    [1] = function() end, -- baseline for previously unversioned saves
    [2] = MigratePendingToggleRecords,
}

local function ApplyMigrations(db)
    local version = NormalizeVersion(db.settingsVersion)
    if version > SETTINGS_VERSION then return end -- future owner wins
    while version < SETTINGS_VERSION do
        local nextVersion = version + 1
        local migrate = MIGRATIONS[nextVersion]
        if migrate then migrate(db) end
        version = nextVersion
        -- Stamp only after the idempotent migration completed successfully.
        db.settingsVersion = version
    end
    if db.settingsVersion ~= SETTINGS_VERSION then
        db.settingsVersion = SETTINGS_VERSION
    end
end

function Store.Init()
    -- Binding is the first half of the legacy rename migration. Completion is
    -- deliberately last so dependency failures retain the recovery reference.
    local db, legacyDecision = SelectDatabaseForLegacyMigration()
    NexusDB = db
    if type(db.chars) ~= "table" then db.chars = {} end
    if type(db.settings) ~= "table" then db.settings = {} end

    local profile = Nexus.DefaultProfile
    local defaults = profile and profile.defaultSettings or {}

    ApplyMigrations(db)
    FillMissing(db.settings, defaults)

    -- Per-character shape drift is filled recursively without replacing the
    -- state table, its safety latches, or fields owned by newer builds.
    for name, state in pairs(db.chars) do
        state = EnsureStateShape(state)
        db.chars[name] = state
        FillMissing(state, FreshState())
    end

    -- The evidence pool is bound before BuildCatalog so overlay writes can
    -- attach content-addressed references without ever touching the immutable
    -- release bundle.
    if Nexus.LoadoutEvidence and Nexus.LoadoutEvidence.Init then
        Nexus.LoadoutEvidence.Init(db)
    end

    -- BuildCatalog owns the versioned release-baseline migration. During the
    -- staged cutover, communityBuilds remains the single canonical overlay
    -- table so existing runtime consumers keep working without duplicating the
    -- same records under two SavedVariables keys.
    local catalogSummary
    if Nexus.BuildCatalog and Nexus.BuildCatalog.Init then
        catalogSummary = Nexus.BuildCatalog.Init(db, Nexus.BundledBuilds)
    end
    if Nexus.DataCompaction and Nexus.DataCompaction.Init
        and not (catalogSummary and catalogSummary.readOnly) then
        Nexus.DataCompaction.Init(db)
    end

    CompleteLegacyMigration(db, legacyDecision)
end

function Store.SettingsVersion()
    return SETTINGS_VERSION
end

-- Live subtable; callers re-fetch rather than caching so rename migration and
-- invalid pre-init globals are never latched.
function Store.Settings()
    local db = NexusDB
    if db and type(db.settings) == "table" then return db.settings end
    if not transientSettings then
        local profile = Nexus.DefaultProfile
        transientSettings = DeepCopy(profile and profile.defaultSettings or {})
    end
    return transientSettings
end

-- Per-char live subtable. The key is re-read from UnitName on EVERY
-- call: while it reads nil/"Unknown" (login order) a transient table is
-- returned instead, and the first call with a real name switches to the
-- persisted one -- a bad key is never latched (addendum B5).
function Store.State()
    local name = UnitName and UnitName("player") or nil
    local db = NexusDB
    if not name or name == "" or name == "Unknown"
        or not db or type(db.chars) ~= "table" then
        transientState = transientState or FreshState()
        return transientState
    end
    local state = db.chars[name]
    state = EnsureStateShape(state)
    db.chars[name] = state
    return state
end
