-- Characterize Store ownership and retry behavior before legacy retirement or
-- persistence extraction. This fixture intentionally does not change either
-- SavedVariables global.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

local Store = Nexus.Store

NexusDB = nil
WishlistRealizerDB = nil
UnitName = function() return "Unknown" end
local transientSettings = Store.Settings()
local transientState = Store.State()
assert(type(transientSettings) == "table" and type(transientState) == "table"
    and Store.Settings() == transientSettings and Store.State() == transientState
    and NexusDB == nil,
    "pre-init Store access latched or created persisted state")

local settings = {
    autoPick=false, autoActivate=false, updateNotifications=false,
    anchorNames={}, futurePreference={keep=true},
}
local hero = {
    tomeTogglePending={}, priorAutoAccept=false, flagDemotions={},
    recordedPicks={}, loadoutWishlists={}, futureSafety={keep=true},
}
local chars = {Hero=hero}
local builds = {preserved={future=true}}
local dps = {preserved={future=true}}
local tombstones = {preserved={stamp=1, author="Hero", future=true}}
local diagnostics = {preserved={future=true}}
local evidence = {preserved={future=true}}
local root = {
    settingsVersion=99,
    settings=settings,
    chars=chars,
    communityBuilds=builds,
    dpsCapture=dps,
    syncTombstones=tombstones,
    diagnosticLogs=diagnostics,
    loadoutEvidence=evidence,
    futureRoot={keep=true},
}
NexusDB = root
UnitName = function() return "Hero" end

local calls = {}
local bundle = {marker="bundle"}
Nexus.BundledBuilds = bundle
Nexus.LoadoutEvidence = {Init=function(db)
    calls[#calls + 1] = "evidence"
    assert(db == root, "evidence initializer received a replacement root")
end}
Nexus.BuildCatalog = {Init=function(db, receivedBundle)
    calls[#calls + 1] = "catalog"
    assert(db == root and receivedBundle == bundle,
        "catalog initializer received a replacement dependency")
    return {readOnly=false}
end}
Nexus.DataCompaction = {Init=function(db)
    calls[#calls + 1] = "compaction"
    assert(db == root, "compaction initializer received a replacement root")
end}

Store.Init()
assert(table.concat(calls, ",") == "evidence,catalog,compaction",
    "Store additive owners initialized out of order")
assert(NexusDB == root and NexusDB.settings == settings
    and NexusDB.chars == chars and NexusDB.chars.Hero == hero,
    "Store initialization replaced root, settings, chars, or character state")
assert(NexusDB.settingsVersion == 99 and settings.autoPick == false
    and settings.autoSave == true and #settings.anchorNames == 0
    and settings.futurePreference.keep and hero.priorAutoAccept == false
    and hero.futureSafety.keep and NexusDB.futureRoot.keep,
    "Store downgraded future schema or replaced explicit/unknown fields")
assert(NexusDB.communityBuilds == builds and NexusDB.dpsCapture == dps
    and NexusDB.syncTombstones == tombstones
    and NexusDB.diagnosticLogs == diagnostics
    and NexusDB.loadoutEvidence == evidence,
    "Store initialization replaced another SavedVariables owner")
assert(Store.SettingsVersion() == 2 and Store.Settings() == settings
    and Store.State() == hero,
    "Store public accessors changed version or live-table identity")

calls = {}
Store.Init()
assert(table.concat(calls, ",") == "evidence,catalog,compaction"
    and NexusDB == root and Store.Settings() == settings and Store.State() == hero,
    "repeat initialization changed order or live-table identity")

calls = {}
Nexus.BuildCatalog.Init = function(db, receivedBundle)
    calls[#calls + 1] = "catalog"
    assert(db == root and receivedBundle == bundle)
    return {readOnly=true}
end
Store.Init()
assert(table.concat(calls, ",") == "evidence,catalog",
    "read-only catalog path ran data compaction")

calls = {}
Nexus.LoadoutEvidence.Init = function(db)
    calls[#calls + 1] = "evidence"
    assert(db == root)
end
Nexus.BuildCatalog.Init = function(db, receivedBundle)
    calls[#calls + 1] = "catalog-fail"
    assert(db == root and receivedBundle == bundle)
    error("injected catalog failure")
end
local catalogOk, catalogWhy = pcall(Store.Init)
assert(not catalogOk and tostring(catalogWhy):find("injected catalog failure", 1, true)
    and table.concat(calls, ",") == "evidence,catalog-fail",
    "Store swallowed catalog failure or invoked compaction afterward")
assert(NexusDB == root and NexusDB.settings == settings
    and NexusDB.chars == chars and NexusDB.chars.Hero == hero,
    "mid-order initialization failure replaced persistence identity")

-- A dependency failure propagates without replacing persistence or invoking
-- later owners. A later retry reuses the same root and completes in order.
calls = {}
Nexus.LoadoutEvidence.Init = function(db)
    calls[#calls + 1] = "evidence-fail"
    assert(db == root)
    error("injected evidence failure")
end
local ok, why = pcall(Store.Init)
assert(not ok and tostring(why):find("injected evidence failure", 1, true)
    and table.concat(calls, ",") == "evidence-fail",
    "Store swallowed failure or invoked a later persistence owner")
assert(NexusDB == root and NexusDB.settings == settings
    and NexusDB.chars == chars and NexusDB.chars.Hero == hero
    and NexusDB.communityBuilds == builds and NexusDB.dpsCapture == dps
    and NexusDB.syncTombstones == tombstones
    and NexusDB.diagnosticLogs == diagnostics
    and NexusDB.loadoutEvidence == evidence
    and NexusDB.settingsVersion == 99 and NexusDB.futureRoot.keep,
    "failed initialization replaced or downgraded SavedVariables data")

calls = {}
Nexus.LoadoutEvidence.Init = function(db)
    calls[#calls + 1] = "evidence"
    assert(db == root)
end
Nexus.BuildCatalog.Init = function(db, receivedBundle)
    calls[#calls + 1] = "catalog"
    assert(db == root and receivedBundle == bundle)
    return {readOnly=false}
end
Nexus.DataCompaction.Init = function(db)
    calls[#calls + 1] = "compaction"
    assert(db == root)
end
Store.Init()
assert(table.concat(calls, ",") == "evidence,catalog,compaction"
    and NexusDB == root and Store.Settings() == settings and Store.State() == hero,
    "Store retry did not complete against the preserved live root")

print("Store order, identity, future fields, failure, and retry behavior -- OK")
