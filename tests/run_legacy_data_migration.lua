-- Atomic/resumable conversion of pre-refactor account and DPS storage.
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")
dofile("core/DpsCapture.lua")

UnitName = function() return "Localhero" end
GetNormalizedRealmName = function() return "Ebonhold" end
GetRealmName = GetNormalizedRealmName
UnitClass = function() return "Mage", "MAGE" end

local compactions, retentions, repairs = 0, 0, 0
Nexus.DataCompaction = {Init=function() compactions=compactions+1; return {} end}
Nexus.DataRetention = {
    Request=function() retentions=retentions+1; return true end,
    Init=function() error("retention ran before conversion commit") end,
}
Nexus.LegacyQualificationRepair = {
    Request=function() repairs=repairs+1; return true end,
}

local function Row(player, dps, fingerprint, owner, realm, ts)
    return {
        player=player,dps=dps,fingerprint=fingerprint,duration=65,
        ownerKey=owner,realm=realm,ts=ts or 100,class="MAGE",
    }
end

local localDummy = Row("Localhero", 100, "local-fp",
    "localhero@ebonhold", "ebonhold", 100)
local localLegacyHigh = Row("Localhero", 125, nil,
    "localhero@ebonhold", "ebonhold", 90)
local peerA = Row("Same", 200, "peer-a", "same@alpha", "alpha", 80)
local peerB = Row("Same", 300, "peer-b", "same@beta", "beta", 70)
local peerLegacy = Row("Peer", 250, nil, nil, nil, 60)

NexusDB = {
    settingsVersion=5,settings={},chars={},communityBuilds={},
    accountCharacters={
        ["localhero@unknown"]={name="Localhero",realm="unknown",lastSeen=1},
        ["same@alpha"]={name="Same",realm="alpha",lastSeen=2},
        ["orphan@unknown"]={name="Orphan",realm="unknown",lastSeen=3},
    },
    dpsCapture={
        personalBest={
            ["local-fp"]={dummy=localDummy,futureCategory={keep=true}},
        },
        characterBest={
            dummy={same=peerA,["same@beta"]=peerB},lk={},
        },
        leaderboard={
            ["local-fp"]={dummy={Localhero=localLegacyHigh}},
            ["legacy-peer"]={lk={Peer=peerLegacy}},
        },
        buildBest={
            ["build-peer"]={dummy=Row("Buildpeer", 350, nil,
                "buildpeer@gamma", "gamma", 50)},
        },
        futureDpsField={keep=true},
    },
}

local sourceAccounts = NexusDB.accountCharacters
local sourceCharacter = NexusDB.dpsCapture.characterBest
local sourceLegacy = NexusDB.dpsCapture.leaderboard
local summary = Nexus.LegacyDataMigration.Init(NexusDB)
assert(summary.pending and Nexus.LegacyDataMigration.BlocksDpsMigration(NexusDB),
    "known legacy database did not begin a blocking staged conversion")
assert(NexusDB.accountCharacters == sourceAccounts
    and NexusDB.dpsCapture.characterBest == sourceCharacter
    and NexusDB.dpsCapture.leaderboard == sourceLegacy,
    "converter mutated live owners before its transaction commit")

-- The old eager owner must stand down while staging is incomplete.
Nexus.DpsCapture.MigrateLegacyLeaderboard()
assert(NexusDB.dpsCapture.leaderboard == sourceLegacy,
    "eager DPS migration raced the staged converter")

-- Simulate an interrupted login, then reload only the migration module. The
-- durable phase/staging tables must be sufficient to resume.
assert(not Nexus.LegacyDataMigration.Pump(3),
    "tiny pump unexpectedly completed the whole migration")
local durablePhase = NexusDB.legacyDataMigration.phase
dofile("core/LegacyDataMigration.lua")
assert(Nexus.LegacyDataMigration.Init(NexusDB).pending
    and NexusDB.legacyDataMigration.phase == durablePhase,
    "reload did not resume the durable migration phase")

-- A represented DPS write during staging invalidates the snapshot. The job
-- restarts and the new row must be present in the committed database.
NexusDB.dpsCapture.characterBest.lk["late@delta"] =
    Row("Late", 400, "late-fp", "late@delta", "delta", 40)
Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,
    {scope="record",reason="test concurrent write"})

local pumps = 0
while not Nexus.LegacyDataMigration.Pump(32) do
    pumps = pumps + 1
    assert(pumps < 100, "migration did not converge")
end

local migration = NexusDB.legacyDataMigration
local dps = NexusDB.dpsCapture
assert(migration.state == "complete" and migration.version == 1
    and migration.staging == nil and dps.leaderboard == nil,
    "migration did not commit and retire staging/legacy ownership")
assert(NexusDB.accountCharacters["localhero@ebonhold"]
    and NexusDB.accountCharacters["same@alpha"]
    and NexusDB.accountCharacters["orphan@unknown"] == nil,
    "account ledger was not canonicalized conservatively")
assert((migration.lastResult.quarantined or 0) >= 1,
    "unresolved account identity was not reported")
assert(dps.characterBest.dummy["same@alpha"] == peerA
    or dps.characterBest.dummy["same@alpha"].dps == 200,
    "first same-name realm was lost")
assert(dps.characterBest.dummy["same@beta"].dps == 300,
    "second same-name realm collided with the first")
assert(dps.characterBest.lk.peer.dps == 250
    and dps.characterBest.lk["late@delta"].dps == 400
    and dps.characterBest.dummy["buildpeer@gamma"].dps == 350,
    "legacy, concurrent, or build-best rows were not promoted")
assert(dps.personalBest["local-fp"].dummy.dps == 125
    and dps.personalBest["local-fp"].futureCategory.keep,
    "local legacy best or unknown personal category was lost")
assert(dps.futureDpsField.keep and compactions == 1
    and retentions == 1 and repairs == 1,
    string.format("post-commit owners did not resume exactly once (%d/%d/%d)",
        compactions, retentions, repairs))
assert(Nexus.LegacyDataMigration.Status(NexusDB).runtime.maxWork <= 32,
    "migration exceeded its per-pump work budget")

local encoded = Nexus.Codec.JSONEncode(NexusDB)
local complete = Nexus.LegacyDataMigration.Init(NexusDB)
assert(complete.complete and not complete.pending
    and Nexus.Codec.JSONEncode(NexusDB) == encoded,
    "completed conversion was not byte-stable and idempotent")

-- Unknown future settings and future migration metadata are both preserved.
local futureSettings = {settingsVersion=6,dpsCapture={future=true}}
local futureSummary = Nexus.LegacyDataMigration.Init(futureSettings)
assert(futureSummary.complete and futureSummary.skipped
    and futureSettings.legacyDataMigration == nil
    and futureSettings.dpsCapture.future,
    "future settings owner was changed or blocked")

local futureMigration = {
    settingsVersion=5,
    legacyDataMigration={schemaVersion=2,version=1,state="future"},
    dpsCapture={leaderboard={future=true}},
}
local futureMarker = Nexus.LegacyDataMigration.Init(futureMigration)
assert(futureMarker.readOnly and not futureMarker.complete
    and futureMigration.legacyDataMigration.state == "future"
    and futureMigration.dpsCapture.leaderboard.future,
    "future migration schema was not treated as read-only")

print("legacy data conversion is atomic, resumable, realm-safe, and idempotent -- OK")
