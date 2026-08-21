-- Registration and staged migration must preserve ambiguous account identity
-- evidence. Only a durable exact ownerKey carried by the source row is an
-- authority bridge from an @unknown map key to a canonical owner.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")
dofile("core/Codec.lua")

local Store, Codec = Nexus.Store, Nexus.Codec
local currentName, currentRealm = "Twin", "RealmA"
UnitName = function() return currentName end
GetNormalizedRealmName = function() return currentRealm end
GetRealmName = GetNormalizedRealmName
UnitClass = function() return "Mage", "MAGE" end
time = function() return 9000 end

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}; seen[value] = out
    for key, child in pairs(value) do out[Copy(key, seen)] = Copy(child, seen) end
    return out
end

local function Equal(left, right, seen)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then return false end
    seen = seen or {}
    if seen[left] then return seen[left] == right end
    seen[left] = right
    for key, value in pairs(left) do
        if not Equal(value, right[key], seen) then return false end
    end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
end

-- Registration happens before LegacyDataMigration in Store.Init. It may add
-- the exact current row, but it cannot retire same-name ambiguous evidence.
local unknown = {
    name="Twin",realm="unknown",lastSeen=1,
    futureIdentity={keep=true},note="ambiguous",
}
local unknownBefore = Copy(unknown)
local canonicalA = {
    name="Twin",realm="realma",lastSeen=2,
    futureCanonical={keep=true},note="canonical-a",
}
NexusDB = {settingsVersion=5,settings={},chars={},accountCharacters={
    ["twin@unknown"]=unknown,["twin@realma"]=canonicalA,
}}
Store.RegisterCurrentCharacter()
Check(NexusDB.accountCharacters["twin@unknown"] == unknown
        and Equal(unknown, unknownBefore),
    "RegisterCurrentCharacter deleted or rewrote Twin@unknown")
Check(NexusDB.accountCharacters["twin@realma"] == canonicalA
        and canonicalA.futureCanonical.keep,
    "registration replaced the existing canonical RealmA row")

currentRealm = "RealmB"
Store.RegisterCurrentCharacter()
Check(NexusDB.accountCharacters["twin@unknown"] == unknown
        and NexusDB.accountCharacters["twin@realma"] == canonicalA
        and type(NexusDB.accountCharacters["twin@realmb"]) == "table",
    "RealmB registration claimed or removed retained RealmA/unknown evidence")

-- Direct registration must also respect future-owned persistence; callers do
-- not gain a bypass merely by invoking the public registration seam.
local futureOwned = {
    settingsVersion=5,settings={},chars={},
    accountCharacters={ ["future@unknown"]={future={keep=true}} },
    legacyDataMigration={schemaVersion=99,version=1,state="future",
        future={keep=true}},
}
local futureBefore = Copy(futureOwned)
NexusDB = futureOwned
currentName, currentRealm = "Future", "RealmA"
Store.RegisterCurrentCharacter()
Check(Equal(futureOwned, futureBefore),
    "registration mutated a future-owned migration/account database")
currentName, currentRealm = "Twin", "RealmA"

local function MigrationInput()
    return {
        settingsVersion=5,settings={},chars={},communityBuilds={},
        accountCharacters={
            ["twin@unknown"]={name="Twin",realm="unknown",lastSeen=100,
                futureIdentity={keep=true},note="ambiguous"},
            ["twin@realma"]={name="Twin",realm="realma",lastSeen=10,
                futureCanonical={keep=true},note="canonical-a"},
            ["twin@realmb"]={name="Twin",realm="realmb",lastSeen=20,
                futureCanonical={keep=true},note="canonical-b"},
            ["orphan@unknown"]={name="Orphan",realm="unknown",lastSeen=30,
                futureOrphan={keep=true}},
            ["bridged@unknown"]={name="Bridged",realm="unknown",lastSeen=40,
                ownerKey="bridged@realma",futureBridge={keep=true}},
        },
        dpsCapture={personalBest={},buildBest={},
            characterBest={dummy={},lk={}}},
    }
end

local function FinishMigration(database, realm, interrupt)
    currentRealm = realm
    NexusDB = database
    if Nexus.Scheduler and Nexus.Scheduler.Cancel then
        Nexus.Scheduler.Cancel("legacy-data-migration")
    end
    dofile("core/LegacyDataMigration.lua")
    local summary = Nexus.LegacyDataMigration.Init(database)
    Check(summary.pending == true, "legacy account fixture did not enter staging")
    if interrupt then
        Nexus.LegacyDataMigration.Pump(1)
        dofile("core/LegacyDataMigration.lua")
        summary = Nexus.LegacyDataMigration.Init(database)
        Check(summary.pending == true, "interrupted migration did not resume")
    end
    local pumps = 0
    while not Nexus.LegacyDataMigration.Pump(32) do
        pumps = pumps + 1
        assert(pumps < 100, "migration did not converge")
    end
    if Nexus.Scheduler and Nexus.Scheduler.Cancel then
        Nexus.Scheduler.Cancel("legacy-data-migration")
    end
    return database
end

local inputA = MigrationInput()
local inputB = Copy(inputA)
local migratedA = FinishMigration(inputA, "RealmA", true)
local migratedB = FinishMigration(inputB, "RealmB", false)

local function CheckResult(database, label)
    local rows = database.accountCharacters
    Check(type(rows["twin@unknown"]) == "table"
            and rows["twin@unknown"].futureIdentity.keep
            and rows["twin@unknown"].note == "ambiguous",
        label .. " migration deleted or rewrote ambiguous Twin@unknown")
    Check(rows["twin@realma"].note == "canonical-a"
            and rows["twin@realma"].futureCanonical.keep,
        label .. " migration overwrote canonical RealmA from ambiguity")
    Check(rows["twin@realmb"].note == "canonical-b"
            and rows["twin@realmb"].futureCanonical.keep,
        label .. " migration overwrote canonical RealmB from ambiguity")
    Check(type(rows["orphan@unknown"]) == "table"
            and rows["orphan@unknown"].futureOrphan.keep,
        label .. " migration erased unresolved orphan evidence")
    Check(rows["bridged@unknown"] == nil
            and type(rows["bridged@realma"]) == "table"
            and rows["bridged@realma"].futureBridge.keep,
        label .. " migration did not consume the explicit exact owner bridge once")
end

CheckResult(migratedA, "RealmA-first")
CheckResult(migratedB, "RealmB-first")
Check(Codec.JSONEncode(migratedA.accountCharacters)
        == Codec.JSONEncode(migratedB.accountCharacters),
    "account migration result depended on same-name login realm/order")

local encoded = Codec.JSONEncode(migratedA)
dofile("core/LegacyDataMigration.lua")
local replay = Nexus.LegacyDataMigration.Init(migratedA)
Check(replay.complete == true and replay.pending ~= true
        and Codec.JSONEncode(migratedA) == encoded,
    "completed exact bridge or ambiguous preservation replayed after restart")

if #failures > 0 then
    error("EXPECTED RED conservative account identity:\n - "
        .. table.concat(failures, "\n - "))
end

print("Account registration, ambiguity, exact bridge, restart, and login order -- OK")
