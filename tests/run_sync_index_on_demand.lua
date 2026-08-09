-- Current peers reconcile complete builds; compact indexes remain a safe
-- compatibility path for an older summary-only peer.
local H=dofile('tests/harness.lua')
dofile('core/Codec.lua'); dofile('core/Sync.lua'); dofile('core/DpsCapture.lua')
local Sync=Nexus.Sync
local clock=1000; GetTime=function() return clock end; time=function() return 50000 end
local function Pump(steps) for _=1,steps do clock=clock+0.2; Sync.OnUpdate(0.2) end end
local who='Source'; UnitName=function() return who end
local echoes={}; for i=1,79 do echoes[i]={spellId=200000+i,stacks=(i%3)+1,quality=3} end
local build={id='build-79',title='Full Record Build',description=string.rep('description ',50),
    author='Source',ownerKey='source@ebonhold',class='MAGE',echoes=echoes,
    postedAt=10,lastModified=10,isMine=true}
NexusDB={communityBuilds={[build.id]=build},syncTombstones={},dpsCapture={}}
Sync.Init(Nexus.Codec,{}); Nexus.DpsCapture.Init({},Sync)

H.sentChatMessages={}
Sync.HandleIncoming('WLRQ|Receiver|0|0|req-current','Receiver')
Pump(300)
local complete={}; for _,m in ipairs(H.sentChatMessages) do
    if m.text:find('^WLRB') then complete[#complete+1]=m end
    assert(#m.text<=255,'full-loadout chunk exceeded 255 chars')
end
assert(#complete>1,'complete 79-Echo reconciliation was not chunked')

who='Receiver'; NexusDB={communityBuilds={},syncTombstones={},dpsCapture={}}
clock=1200; Sync.Init(Nexus.Codec,{})
for _,m in ipairs(complete) do Sync.HandleIncoming(m.text,'Source') end
local loaded=NexusDB.communityBuilds['build-79']
assert(loaded and loaded.echoes and #loaded.echoes==79,'complete loadout did not reassemble')
assert(loaded.description:find('description'),'full description was not restored')

-- Legacy compact summaries are accepted only from their direct author and
-- remain explicitly incomplete until a background recovery succeeds.
who='Source'; NexusDB={communityBuilds={[build.id]=build},syncTombstones={},dpsCapture={}}
clock=1400; Sync.Init(Nexus.Codec,{})
H.sentChatMessages={}; assert(Sync.BroadcastBuildSummary(build)); Pump(10)
local summaries=H.sentChatMessages
who='Receiver'; NexusDB={communityBuilds={},syncTombstones={},dpsCapture={}}
Sync.Init(Nexus.Codec,{})
for _,m in ipairs(summaries) do Sync.HandleIncoming(m.text,'Source') end
local placeholder=NexusDB.communityBuilds['build-79']
assert(placeholder and not placeholder.loadoutAvailable and not placeholder.echoes,
    'legacy summary was incorrectly treated as exact evidence')
local immediate,why=Sync.RequestLoadout('build-79')
assert(not immediate and why,'legacy recovery request did not remain background-only')
print('complete current sync and safe legacy-summary compatibility -- OK')
