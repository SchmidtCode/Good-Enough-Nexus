-- Optional read-only smoke test for a real SavedVariables backup.
-- Usage: luajit tests/run_legacy_backup_smoke.lua <Nexus backup.lua>
local path = arg and arg[1]
assert(type(path) == "string" and path ~= "", "SavedVariables path required")

local chunk = assert(loadfile(path))
local loaded = {}
setfenv(chunk, loaded)
assert(pcall(chunk), "SavedVariables backup could not be evaluated")
assert(type(loaded.NexusDB) == "table", "backup did not contain NexusDB")

local H = dofile("tests/harness.lua")
UnitName = function() return "Ogie" end
GetNormalizedRealmName = function() return "Rogue-Lite(Live)" end
GetRealmName = GetNormalizedRealmName
UnitClass = function() return "Paladin", "PALADIN" end

local function Count(source)
    local total = 0
    for _ in pairs(type(source) == "table" and source or {}) do total=total+1 end
    return total
end

NexusDB = loaded.NexusDB
local root = NexusDB
local settings, builds = root.settings, root.communityBuilds
local retention, catalog = root.dataRetention, root.buildCatalog
local dps = assert(root.dpsCapture, "backup had no DPS store")
local before = {
    accounts=Count(root.accountCharacters),
    personal=Count(dps.personalBest),build=Count(dps.buildBest),
    dummy=Count(dps.characterBest and dps.characterBest.dummy),
    lk=Count(dps.characterBest and dps.characterBest.lk),
}

Nexus.DataCompaction = {Init=function() return {} end}
Nexus.DataRetention = {Request=function() return true end}
Nexus.ViewRefresh = {Request=function() return true end}

local started = os.clock()
local result = Nexus.LegacyDataMigration.Init(root)
assert(result.pending, "known v5 backup did not enter migration")
local pumps = 0
while not Nexus.LegacyDataMigration.Pump(32) do
    pumps = pumps + 1
    assert(pumps < 10000, "backup migration did not converge")
end
local elapsed = os.clock() - started
local after = {
    accounts=Count(root.accountCharacters),
    personal=Count(dps.personalBest),build=Count(dps.buildBest),
    dummy=Count(dps.characterBest and dps.characterBest.dummy),
    lk=Count(dps.characterBest and dps.characterBest.lk),
}
local status = Nexus.LegacyDataMigration.Status(root)

assert(root == NexusDB and root.settings == settings
    and root.communityBuilds == builds and root.dataRetention == retention
    and root.buildCatalog == catalog,
    "converter replaced a table owned by another subsystem")
assert(root.legacyDataMigration.state == "complete"
    and root.legacyDataMigration.staging == nil,
    "backup migration did not commit cleanly")
assert(after.accounts >= before.accounts
    and after.personal == before.personal and after.build == before.build,
    "backup migration unexpectedly lost valid account or fingerprint maps")
assert(after.dummy > 0 and after.lk > 0
    and status.runtime.maxWork <= Nexus.LegacyDataMigration.BatchSize(),
    "backup migration lost a DPS category or exceeded its batch budget")

print(string.format(
    "real backup migration: accounts=%d/%d personal=%d build=%d DPS=%d/%d -> %d/%d pumps=%d elapsed=%.3fs quarantined=%d -- OK",
    before.accounts,after.accounts,after.personal,after.build,
    before.dummy,before.lk,after.dummy,after.lk,pumps,elapsed,
    tonumber(root.legacyDataMigration.lastResult.quarantined) or 0))
