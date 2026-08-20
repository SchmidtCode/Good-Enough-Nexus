-- Realm-qualified DPS identity migration and presentation regression coverage.
local H=dofile("tests/harness.lua")
dofile("core/Codec.lua"); dofile("core/Sync.lua"); dofile("core/DpsCapture.lua")

local DPS=Nexus.DpsCapture
GetNormalizedRealmName=function() return "Rogue-Lite (Live)" end
UnitName=function(unit) return unit=="player" and "Twin" or nil end
UnitClass=function() return "Mage", "MAGE" end
time=function() return 1000 end

local currentOld={{spellId=200201,stacks=1}}
local currentNew={{spellId=200202,stacks=2}}
local future={{spellId=200203,stacks=3}}
local currentOldFp=DPS.GetEchoKey(currentOld)
local currentNewFp=DPS.GetEchoKey(currentNew)
local futureFp=DPS.GetEchoKey(future)

local function Row(player,realm,ownerKey,ts,dps,echoes,fingerprint,locked)
    return {
        player=player,realm=realm,ownerKey=ownerKey,ts=ts,dps=dps,
        duration=65,level=80,class="MAGE",echoes=echoes,
        fingerprint=fingerprint,lockedEchoes=locked,
    }
end

NexusDB={communityBuilds={},syncTombstones={},dpsCapture={
    characterBest={
        dummy={
            ["Twin@Rogue-Lite (Live)"]=Row("Twin","Rogue-Lite (Live)","twin@roguelite(live)",
                100,30000000,currentOld,currentOldFp,{{spellId=200299,stacks=1}}),
            ["twin"]=Row("Twin",nil,nil,
                200,20000000,currentNew,currentNewFp,nil),
            ["twin@future"]=Row("Twin","future","twin@future",
                150,25000000,future,futureFp,{{spellId=200298,stacks=1}}),
        },
        lk={
            ["twin"]=Row("Twin",nil,nil,
                210,19000000,currentNew,currentNewFp,nil),
            ["twin@future"]=Row("Twin","future","twin@future",
                160,18000000,future,futureFp,nil),
            ["Tie@Rogue-Lite (Live)"]=Row("Tie","Rogue-Lite (Live)","tie@rogue-lite(live)",
                300,10000000,currentOld,currentOldFp,nil),
            ["tie"]=Row("Tie",nil,nil,
                300,11000000,currentNew,currentNewFp,nil),
        },
    },
}}

local adapter={LockedOwned=function()
    return {bySpell={[200297]=1}}
end}
DPS.Init(adapter,nil)

local store=NexusDB.dpsCapture.characterBest
assert(store.dummy["twin"]==nil and store.dummy["Twin@Rogue-Lite (Live)"]==nil,
    "legacy/original-case keys survived canonical migration")
local current=store.dummy["twin@roguelitelive"]
assert(current and current.ts==200 and current.dps==20000000,
    "newest duplicate did not win realm identity migration")
assert(current.ownerKey=="twin@roguelitelive" and current.realm=="roguelitelive"
    and current.characterKey=="twin@roguelitelive" and current.realmAssumed==true,
    "legacy row did not receive hidden assumed-realm metadata")
assert(store.dummy["twin@future"] and store.dummy["twin@future"].realmAssumed==false,
    "explicit future realm was collapsed or marked assumed")
assert(store.lk["tie@roguelitelive"] and store.lk["tie@roguelitelive"].dps==11000000,
    "equal-timestamp duplicate tie did not prefer higher DPS")

local dummy=DPS.GetDpsBoard("dummy")
assert(#dummy==2,"future realm identities did not remain distinct")
local sawCurrent,sawFuture=false,false
for _,row in ipairs(dummy) do
    assert(row.displayPlayer=="Twin-"..row.realm,
        "same-name cross-realm row was not visibly qualified")
    if row.characterKey=="twin@roguelitelive" then
        sawCurrent=true
        assert(row.lockedEchoes and row.lockedEchoes[1].spellId==200297,
            "current-realm locked Echoes were not backfilled")
    elseif row.characterKey=="twin@future" then
        sawFuture=true
        assert(row.lockedEchoes and row.lockedEchoes[1].spellId==200298,
            "locked Echo backfill mutated the other realm")
    end
end
assert(sawCurrent and sawFuture,"realm-qualified board identities missing")

-- Older, weaker Sync evidence resolves to the current realm but cannot
-- recreate a second key or replace the selected public row.
assert(not DPS.ReceiveRecord({v=7,f=currentOldFp,e=currentOld,c="dummy",
    d=15000000,u=65,t=50,p="Twin",k="MAGE",l=80}),
    "older weaker realm-less Sync record was accepted")
assert(store.dummy["twin"]==nil and store.dummy["twin@roguelitelive"]==current,
    "Sync recreated a legacy duplicate key")

-- Re-loading the module over the migrated SavedVariables is idempotent.
dofile("core/DpsCapture.lua")
DPS=Nexus.DpsCapture
DPS.Init(adapter,nil)
store=NexusDB.dpsCapture.characterBest
assert(store.dummy["twin@roguelitelive"] and store.dummy["twin@future"]
    and store.dummy["twin@roguelitelive"].realmAssumed==true
    and store.dummy["twin"]==nil,
    "realm identity migration was not reload-idempotent")

dofile("core/ViewProjections.lua")
local combined=Nexus.ViewProjections.Leaderboard("combined",{})
assert(#combined==2,"Combined board cross-paired or collapsed realm identities")
for _,row in ipairs(combined) do
    assert(row.characterKey=="twin@roguelitelive" or row.characterKey=="twin@future",
        "Combined board lost canonical realm identity")
    assert(row.displayPlayer=="Twin-"..row.realm,
        "Combined board did not qualify same-name realm collision")
end

print("realm-qualified DPS migration, Sync, locked metadata, reload, and presentation -- OK")
