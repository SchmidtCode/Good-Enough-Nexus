-- Locked-baseline migration authority and recovery regressions.
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")

UnitName = function(unit)
    if unit == "player" then return "Local" end
end
GetNormalizedRealmName = function() return "Ebonhold" end
GetRealmName = function() return "Ebonhold" end

local Codec = Nexus.Codec
local A, B, C = 200100, 200200, 200300

local function Echoes(...)
    local values = {...}
    local out = {}
    for index=1,#values,2 do
        out[#out+1] = {spellId=values[index],count=values[index+1]}
    end
    return out
end

local function Key(rows)
    local out = {}
    for _, row in ipairs(rows) do
        out[#out+1] = tostring(row.spellId) .. "x" .. tostring(row.count)
    end
    return table.concat(out, ",")
end

local function Hash(rows)
    local key = Key(rows)
    local hash = 5381
    for index=1,#key do
        hash = ((hash * 33) + key:byte(index)) % 2147483648
    end
    return string.format("%x", hash)
end

local function Signature(value)
    return Codec.JSONEncode(H.CloneValue(value))
end

local function NewRow(player, ownerKey, rows, extra)
    local row = {
        dps=31415926,duration=67,ts=50000,player=player,level=80,
        class="MAGE",category="dummy",ownerKey=ownerKey,
        ownerVerified=true,echoes=H.CloneValue(rows),
        fingerprint=Key(rows),loadoutHash=Hash(rows),
        futureField={sentinel="keep"},
    }
    for key, value in pairs(extra or {}) do row[key] = H.CloneValue(value) end
    return row
end

local function LoadDps(database)
    NexusDB = database
    dofile("core/LoadoutEvidence.lua")
    dofile("core/DpsCapture.lua")
    return Nexus.DpsCapture
end

local function Adapter(lockedBySpell)
    return {
        LockedOwned=function()
            return {synced=true,bySpell=H.CloneValue(lockedBySpell or {})}
        end,
    }
end

local function EmptyDps(extra)
    local db = {
        personalBest={},buildBest={},
        characterBest={dummy={},lk={}},
    }
    for key, value in pairs(extra or {}) do db[key] = value end
    return db
end

-- The confirmed issue #39 red: local A must not be removed from remote A+B.
local remote = NewRow("Remote", "remote@otherrealm", Echoes(A,1,B,1))
local build = NewRow("Builder", "builder@otherrealm", Echoes(A,1,C,1))
local alt = NewRow("Alt", "alt@ebonhold", Echoes(A,1,B,1))
local localUnknown = NewRow("Local", "local@ebonhold", Echoes(A,1,B,1))
local prevention = EmptyDps()
prevention.buildBest[build.fingerprint]={dummy=build}
prevention.characterBest.dummy[remote.ownerKey]=remote
prevention.characterBest.dummy[alt.ownerKey]=alt
prevention.characterBest.dummy[localUnknown.ownerKey]=localUnknown
local preventionRoot = {loadoutEvidence={schemaVersion=1,entries={}},
    dpsCapture=prevention}
local DPS = LoadDps(preventionRoot)
Nexus.LoadoutEvidence.Init(preventionRoot)
assert(Nexus.LoadoutEvidence.ReferenceDpsRow(build))
local remoteBefore, buildBefore = Signature(remote), Signature(build)
local altBefore, localBefore = Signature(alt), Signature(localUnknown)
local unrelatedBroadcasts = 0
DPS.Init(Adapter({[A]=1}),{
    BroadcastDpsRecord=function() unrelatedBroadcasts=unrelatedBroadcasts+1 end,
})
assert(Signature(remote)==remoteBefore,
    "current local locked baseline rewrote an unrelated remote DPS row")
assert(Signature(build)==buildBefore,
    "buildBest changed without record-specific historical proof")
assert(Signature(alt)==altBefore,
    "another local account character was treated as current-login history")
assert(Signature(localUnknown)==localBefore,
    "exact current owner was treated as proof of unknown historical locks")
assert(prevention.lockedMigrationVersion==1,
    "fail-closed prevention did not complete the one-time migration")
assert(unrelatedBroadcasts==0,
    "preserved fingerprints fabricated unrelated Sync churn")

-- Exact locked evidence attached to this row may authorize correction.
local provenSource = Echoes(A,2,B,1)
local provenFinal = Echoes(A,1,B,1)
local proven = NewRow("Proven", "proven@otherrealm", provenSource, {
    lockedEchoes=Echoes(A,1),
})
local provenDb = EmptyDps()
provenDb.personalBest[proven.fingerprint]={dummy=proven}
DPS = LoadDps({loadoutEvidence={schemaVersion=1,entries={}},dpsCapture=provenDb})
DPS.Init(Adapter({[C]=9}),{})
local provenKey = Key(provenFinal)
assert(provenDb.personalBest[provenKey]
    and provenDb.personalBest[provenKey].dummy == proven
    and not provenDb.personalBest[Key(provenSource)]
    and Signature(proven.echoes)==Signature(provenFinal)
    and proven.fingerprint==provenKey,
    "exact row-specific locked baseline did not authorize its correction")
assert(proven.dps==31415926 and proven.duration==67
    and proven.category=="dummy" and proven.ownerKey=="proven@otherrealm"
    and proven.futureField.sentinel=="keep",
    "authorized correction changed unrelated DPS or future metadata")

-- An interruption restores the immutable pre-pass source, never partial output.
local interruptedSource = NewRow("Interrupted", "interrupted@otherrealm",
    provenSource, {lockedEchoes=Echoes(A,1)})
local partial = NewRow("Interrupted", "interrupted@otherrealm",
    provenFinal, {lockedEchoes=Echoes(A,1)})
local interrupted = EmptyDps({
    lockedMigrationSource={
        personalBest={[Key(provenSource)]={dummy=H.CloneValue(interruptedSource)}},
        buildBest={},characterBest={dummy={},lk={}},
    },
})
interrupted.personalBest[Key(provenFinal)]={dummy=partial}
DPS = LoadDps({loadoutEvidence={schemaVersion=1,entries={}},
    dpsCapture=interrupted})
DPS.Init(Adapter({[B]=5}),{})
local resumed = interrupted.personalBest[provenKey]
    and interrupted.personalBest[provenKey].dummy
assert(resumed and Signature(resumed.echoes)==Signature(provenFinal)
    and interrupted.lockedMigrationSource==nil,
    "interrupted source was not restored and transformed exactly once")
local resumedOnce = Signature(interrupted)
DPS.Init(Adapter({[A]=99}),{})
assert(Signature(interrupted)==resumedOnce,
    "repeated initialization double-transformed interrupted recovery")

-- The same local row can be referenced by personal and character stores.
-- Identity sharing must not authorize a second subtraction.
local shared = NewRow("Shared", "shared@ebonhold", provenSource, {
    lockedEchoes=Echoes(A,1),
})
local sharedDb = EmptyDps()
sharedDb.personalBest[shared.fingerprint]={dummy=shared}
sharedDb.characterBest.dummy[shared.ownerKey]=shared
DPS = LoadDps({loadoutEvidence={schemaVersion=1,entries={}},dpsCapture=sharedDb})
DPS.Init(Adapter({[C]=4}),{})
assert(sharedDb.personalBest[provenKey]
    and sharedDb.personalBest[provenKey].dummy==shared
    and sharedDb.characterBest.dummy[shared.ownerKey]==shared
    and Signature(shared.echoes)==Signature(provenFinal),
    "one row shared by two stores was subtracted more than once")

-- Completed v1 is ambiguous without a direct immutable pre-state relationship.
local ambiguous = NewRow("Ambiguous", "ambiguous@otherrealm", Echoes(B,1))
local ambiguousDb = EmptyDps({lockedMigrationVersion=1})
ambiguousDb.characterBest.dummy[ambiguous.ownerKey]=ambiguous
local ambiguousBefore = Signature(ambiguousDb)
DPS = LoadDps({loadoutEvidence={schemaVersion=1,entries={}},
    dpsCapture=ambiguousDb})
DPS.Init(Adapter({[A]=1}),{})
assert(Signature(ambiguousDb)==ambiguousBefore,
    "completed-v1 ambiguous inverse was reconstructed")

-- A direct self-verifying pre-state plus exact empty row baseline proves that
-- old v1 removed an unrelated A. Recover only this linked row.
local preState = Echoes(A,1,B,1)
local recoverable = NewRow("Recoverable", "recoverable@otherrealm",
    Echoes(B,1), {lockedEchoes={}})
local recoverDb = EmptyDps({lockedMigrationVersion=1})
recoverDb.characterBest.dummy[recoverable.ownerKey]=recoverable
local recoverRoot = {loadoutEvidence={schemaVersion=1,entries={}},
    dpsCapture=recoverDb}
DPS = LoadDps(recoverRoot)
Nexus.LoadoutEvidence.Init(recoverRoot)
local preReference = assert(Nexus.LoadoutEvidence.Intern(preState))
recoverable.evidenceKey = preReference
local stablePeer = NewRow("Stable", "stable@otherrealm", Echoes(C,1))
recoverDb.characterBest.dummy[stablePeer.ownerKey]=stablePeer
local stableBefore = Signature(stablePeer)
DPS.Init(Adapter({[C]=7}),{})
assert(Signature(recoverable.echoes)==Signature(preState)
    and recoverable.fingerprint==Key(preState)
    and recoverable.loadoutHash==DPS.GetEchoHash(preState),
    "completed-v1 exact direct pre-state did not recover its linked row")
assert(Signature(stablePeer)==stableBefore,
    "completed-v1 recovery changed an unrelated peer row")
local recoveredOnce = Signature(recoverDb)
DPS.Init(Adapter({[A]=99}),{})
assert(Signature(recoverDb)==recoveredOnce,
    "repeated init changed an exact completed-v1 recovery")

-- A completed row already equal to its exact row-specific correction is
-- unaffected even when an old direct pre-state reference survives.
local legitimatePre = Echoes(A,2,B,1)
local legitimate = NewRow("Legitimate", "legitimate@otherrealm",
    Echoes(A,1,B,1), {lockedEchoes=Echoes(A,1)})
local legitimateDb = EmptyDps({lockedMigrationVersion=1})
legitimateDb.characterBest.dummy[legitimate.ownerKey]=legitimate
local legitimateRoot = {loadoutEvidence={schemaVersion=1,entries={}},
    dpsCapture=legitimateDb}
DPS = LoadDps(legitimateRoot)
Nexus.LoadoutEvidence.Init(legitimateRoot)
legitimate.evidenceKey = assert(Nexus.LoadoutEvidence.Intern(legitimatePre))
local legitimateBefore = Signature(legitimateDb)
DPS.Init(Adapter({[C]=8}),{})
assert(Signature(legitimateDb)==legitimateBefore,
    "completed-v1 row already matching exact authority was reversed")

-- The same exact pool entry is not authority when it is orphaned.
local orphan = NewRow("Orphan", "orphan@otherrealm", Echoes(B,1), {
    lockedEchoes={},
})
local orphanDb = EmptyDps({lockedMigrationVersion=1})
orphanDb.characterBest.dummy[orphan.ownerKey]=orphan
local orphanRoot = {loadoutEvidence={schemaVersion=1,entries={}},
    dpsCapture=orphanDb}
DPS = LoadDps(orphanRoot)
Nexus.LoadoutEvidence.Init(orphanRoot)
assert(Nexus.LoadoutEvidence.Intern(preState))
local orphanBefore = Signature(orphanDb)
DPS.Init(Adapter({[A]=1}),{})
assert(Signature(orphanDb)==orphanBefore,
    "orphan LoadoutEvidence was similarity-attached to a completed row")

-- Current-login locks cannot make the result depend on login order.
local function LoginOrderResult(currentLocks)
    local first = NewRow("First", "first@ebonhold", Echoes(A,1,B,1))
    local second = NewRow("Second", "second@ebonhold", Echoes(A,1,B,1))
    local db = EmptyDps()
    db.characterBest.dummy[first.ownerKey]=first
    db.characterBest.dummy[second.ownerKey]=second
    local runner = LoadDps({loadoutEvidence={schemaVersion=1,entries={}},
        dpsCapture=db})
    runner.Init(Adapter(currentLocks),{})
    return Signature(db)
end
assert(LoginOrderResult({[A]=1})==LoginOrderResult({[B]=1}),
    "two characters with different locks produced login-order-dependent history")

-- Authoritative no-lock readiness is a no-op for rows without exact proof.
local noLock = NewRow("NoLock", "nolock@otherrealm", Echoes(A,1,B,1))
local noLockDb = EmptyDps()
noLockDb.characterBest.dummy[noLock.ownerKey]=noLock
local noLockBefore = Signature(noLock)
DPS = LoadDps({loadoutEvidence={schemaVersion=1,entries={}},dpsCapture=noLockDb})
DPS.Init(Adapter({}),{})
assert(Signature(noLock)==noLockBefore,
    "authoritative no-lock state rewrote historical evidence")
local noLockOnce = Signature(noLockDb)
DPS.Init(Adapter({[A]=1}),{})
assert(Signature(noLockDb)==noLockOnce,
    "repeated no-lock initialization changed migration state")

-- Future-owned storage is read-only; migration may only use transient state.
local previousCatalog = Nexus.BuildCatalog
local futureDps = EmptyDps({futureField={sentinel="future"}})
local futureRow = NewRow("Future", "future@otherrealm", Echoes(A,1,B,1), {
    lockedEchoes=Echoes(A,1),
})
futureDps.characterBest.dummy[futureRow.ownerKey]=futureRow
local futureRoot = {
    dpsCapture=futureDps,futureOwner={sentinel="keep"},
    loadoutEvidence={schemaVersion=99,entries={},futureField="opaque"},
}
local futureBefore = Signature(futureRoot)
Nexus.BuildCatalog = {Status=function() return {readOnly=true} end}
DPS = LoadDps(futureRoot)
DPS.Init(Adapter({[A]=1}),{})
assert(Signature(futureRoot)==futureBefore,
    "future-schema/read-only state was mutated")
Nexus.BuildCatalog = previousCatalog

print("locked migration uses exact row authority -- OK")
