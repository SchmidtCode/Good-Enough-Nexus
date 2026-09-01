-- Mesh audit: a fresh client can recover exact DPS evidence through a relay.
local H=dofile("tests/harness.lua")
dofile("core/Codec.lua"); dofile("core/Sync.lua"); dofile("core/DpsCapture.lua")
local Sync, DPS=Nexus.Sync, Nexus.DpsCapture
local clock=1000; GetTime=function() return clock end; time=function() return 50000 end
local currentName="Relay"
UnitName=function() return currentName end; UnitLevel=function() return 80 end
GetNormalizedRealmName=function() return "Ebonhold" end
local echoes={}; for i=1,79 do echoes[i]={spellId=210000+i,stacks=1} end
local build={id="remote-record-build",title="Mesh Record",author="Origin",class="MAGE",echoes=echoes,postedAt=1,lastModified=1,isMine=false}
NexusDB={communityBuilds={[build.id]=build},syncTombstones={},dpsCapture={}}
Sync.Init(Nexus.Codec,{})
DPS.Init({},Sync)
local fp=DPS.GetEchoKey(echoes)
assert(DPS.ReceiveRecord({v=3,f=fp,e=echoes,c="dummy",d=31000000,u=65,
    t=50000,g=60000,p="Champion",k="MAGE",l=80,b=build.id,
    o="champion@ebonhold",r="ebonhold"}),"seed record failed")

H.sentChatMessages={}
clock=clock+100
local relayHash=DPS.GetSyncHash()
assert(relayHash~="0,0,0,0,0,0,0,0","seeded relay DPS hash was empty")
Sync.HandleIncoming("WLRQ|NewPeer|0","NewPeer")
for i=1,1000 do Sync.OnUpdate(0.2) end
local sawBuild=false
local relayedDpsMessages={}
for _,m in ipairs(H.sentChatMessages) do
    assert(#m.text<=255,"wire message exceeds WoW limit")
    if m.text:find("^WLBI|") then sawBuild=true end
    if m.text:find("^WLD2|") then
        relayedDpsMessages[#relayedDpsMessages+1]=m.text
    end
end
assert(not sawBuild,"relay redistributed a remotely authored build as its own")
local responseStats=Sync.ResponseStats()
local workState=Sync.WorkState()
assert(#relayedDpsMessages>0,string.format(
    "relay did not answer DPS request hash=%s pending=%s serialized=%s",
    relayHash,tostring(workState.pendingResponses),
    tostring(responseStats.dpsSerializations)))
assert(#relayedDpsMessages<=3,string.format(
    "relayed DPS recovery remained too fragile at %d chat chunks",
    #relayedDpsMessages))

-- The receiver can display and continue carrying the exact row, but it
-- remains marked as unverified relay evidence on every hop.
currentName="Fresh"
NexusDB={communityBuilds={[build.id]=build},syncTombstones={},dpsCapture={}}
DPS.Init({},Sync)
for _,text in ipairs(relayedDpsMessages) do Sync.HandleIncoming(text,"Relay") end
local recovered=DPS.GetDpsBoard("dummy")
assert(#recovered==1 and recovered[1].dps==31000000,
    "fresh receiver did not recover the relayed DPS row")
assert(recovered[1].generationAt==60000,
    "compact relay did not preserve the owner generation")
assert(recovered[1].legacy==true,
    "relayed DPS row was not marked as unverified legacy evidence")
assert(DPS.GetSyncHashUncached()==relayHash,
    "relayed DPS evidence did not converge to the source hash")
H.sentChatMessages={}
assert(DPS.BroadcastAllBuildBests("0")>0,
    "relayed owner snapshot was not redistributed to the next peer")
for i=1,1000 do Sync.OnUpdate(0.2) end
local secondHop={}
for _,m in ipairs(H.sentChatMessages) do
    if m.text:find("^WLD2|") then secondHop[#secondHop+1]=m.text end
end
assert(#secondHop>0,"second-hop relay produced no DPS chunks")

currentName="Third"
NexusDB={communityBuilds={[build.id]=build},syncTombstones={},dpsCapture={}}
DPS.Init({},Sync)
for _,text in ipairs(secondHop) do Sync.HandleIncoming(text,"Fresh") end
local thirdHop=DPS.GetDpsBoard("dummy")
assert(#thirdHop==1 and thirdHop[1].dps==31000000
    and thirdHop[1].generationAt==60000,
    "third peer did not converge on the relayed owner generation")
assert(DPS.ReceiveRecord({v=7,f=fp,e=echoes,c="dummy",d=30000000,
    u=65,t=50001,g=60001,p="Champion",k="MAGE",l=80,b=build.id,
    o="champion@ebonhold",r="ebonhold"},"Champion"),
    "direct owner evidence did not replace the relayed row")
local directReplacement=DPS.GetDpsBoard("dummy")
assert(#directReplacement==1 and directReplacement[1].dps==30000000
    and directReplacement[1].legacy==false,
    "direct owner evidence did not take precedence over relayed evidence")

-- The actual record owner can still publish the exact evidence.
currentName="Champion"
NexusDB={communityBuilds={[build.id]=build},syncTombstones={},dpsCapture={}}
DPS.Init({},Sync)
assert(DPS.ReceiveRecord({v=3,f=fp,e=echoes,c="dummy",d=31000000,
    u=65,t=50000,p="Champion",k="MAGE",l=80,b=build.id,
    o="champion@ebonhold",r="ebonhold"},"Champion"),
    "owner record reseed failed")
H.sentChatMessages={}
assert(DPS.BroadcastAllBuildBests("0")>0,"record owner did not queue its DPS evidence")
for i=1,1000 do Sync.OnUpdate(0.2) end
local dpsMessages={}
for _,m in ipairs(H.sentChatMessages) do
    if m.text:find("^WLD2|") then dpsMessages[#dpsMessages+1]=m.text end
end
assert(#dpsMessages>0,"record owner produced no DPS chunks")

-- Fresh receiver: the chunks reconstruct the exact authoritative record.
NexusDB={communityBuilds={[build.id]=build},syncTombstones={},dpsCapture={}}
DPS.Init({},Sync)
for _,text in ipairs(dpsMessages) do Sync.HandleIncoming(text,"Champion") end
local lb=DPS.GetLeaderboard(build.id,"dummy")
assert(#lb==1 and lb[1].dps==31000000 and lb[1].player=="Champion","DPS chunks did not reconstruct the highest record")
assert(not DPS.ReceiveRecord({v=3,f=fp,e=echoes,c="dummy",d=30000000,
    u=65,t=50001,g=50000,p="Champion",k="MAGE",l=80,b=build.id,
    o="champion@ebonhold",r="ebonhold"}),
    "lower record should be rejected")
assert(DPS.GetLeaderboard(build.id,"dummy")[1].dps==31000000,"stale data overwrote the record")
print("DPS origin authority, chunking, reconstruction and stale rejection -- OK")
