-- Current peers reconcile complete builds; compact indexes remain a safe
-- compatibility path for an older summary-only peer.
local H=dofile('tests/harness.lua')
dofile('core/Codec.lua'); dofile('core/Sync.lua'); dofile('core/DpsCapture.lua')
local Sync=Nexus.Sync
local clock=1000; GetTime=function() return clock end; time=function() return 50000 end
local function Pump(steps) for _=1,steps do clock=clock+0.2; Sync.OnUpdate(0.2) end end
local who='Source'; UnitName=function() return who end
local echoes={}; for i=1,79 do echoes[i]={spellId=200000+i,stacks=(i%3)+1,quality=3} end
local build={id='build-79',title='AoE | ST',description=string.rep('description ',50),
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
assert(placeholder.title=='AoE | ST',
    'Base64-encoded summary title containing a wire delimiter was rejected')
local immediate,why=Sync.RequestLoadout('build-79')
assert(not immediate and why,'legacy recovery request did not remain background-only')

-- A recovery rejected at the queue cap must remain immediately eligible once
-- a slot opens; rejected work must not receive the 120-second cooldown.
Sync.Init(Nexus.Codec,{})
local recoveryLimit=Sync.WorkState().maxRecoveryQueue
for i=1,recoveryLimit do
    local sent,reason=Sync.RequestLoadout('recovery-'..i)
    assert(not sent and reason=='queued for background recovery',
        'recovery queue rejected work before its documented cap')
end
assert(Sync.WorkState().recovery==recoveryLimit,
    'recovery queue did not reach its documented cap')
local sentOverflow,overflowReason=Sync.RequestLoadout('recovery-overflow')
assert(not sentOverflow and overflowReason=='awaiting sync',
    'overflow recovery request was not rejected explicitly')
Sync.OnUpdate(1.6)
assert(Sync.WorkState().recovery==recoveryLimit-1,
    'recovery pump did not release one queue slot')
local sentRetry,retryReason=Sync.RequestLoadout('recovery-overflow')
assert(not sentRetry and retryReason=='queued for background recovery',
    'rejected recovery request was incorrectly left on cooldown')
assert(Sync.WorkState().recovery==recoveryLimit,
    'immediate recovery retry did not enter the released slot')

-- Exact-build recovery is control-plane work: it must make progress even
-- while a large channel response is draining, otherwise compact DPS records
-- can expire before their required loadout is requested.
NexusDB={communityBuilds={},syncTombstones={},dpsCapture={}}
Sync.Init(Nexus.Codec,{})
H.sentChatMessages={}
local recoveryQueued,recoveryWhy=Sync.RequestLoadout('priority-recovery')
assert(not recoveryQueued and recoveryWhy=='queued for background recovery',
    'priority recovery fixture was not queued')
local bulkBacklog={}
for i=1,12 do
    bulkBacklog[i]='WLRB|Receiver|bulk-'..i..'|20|1/1|QQ=='
end
assert(Sync.EnqueueLogicalTransfer(bulkBacklog),
    'could not create saturated channel bulk fixture')
assert(Sync.WorkState().sending>8,
    'channel bulk fixture did not exceed the old recovery threshold')
Sync.OnUpdate(1.6)
local recoverySent=false
for _,message in ipairs(H.sentChatMessages) do
    if message.text:gsub('||','|')=='WLLQ|Receiver|priority-recovery' then
        recoverySent=true
    end
end
assert(recoverySent,
    'exact-build recovery was starved behind channel bulk backlog')

-- The legacy-compatible WLLQ response still uses channel WLRB packets, but
-- those packets must not sit behind an unrelated multi-minute bulk backlog.
-- It is a correctness dependency for deferred compact DPS evidence.
who='Source'
local requestedBuild={id='requested-exact',title='Requested exact',
    author='Source',class='MAGE',echoes=echoes,postedAt=30,lastModified=30}
NexusDB={communityBuilds={[requestedBuild.id]=requestedBuild},
    syncTombstones={},dpsCapture={},
    settings={syncDirectExperimental=true}}
Sync.Init(Nexus.Codec,{})
H.sentChatMessages={}
local ordinaryBacklog={}
for i=1,20 do
    ordinaryBacklog[i]='WLRB|Source|ordinary-'..i..'|30|1/1|QQ=='
end
assert(Sync.EnqueueLogicalTransfer(ordinaryBacklog),
    'could not queue ordinary channel backlog')
local directBacklog={}
for i=1,6 do
    directBacklog[i]='WLRB|Source|direct-backlog|30|'..i..'/6|QQ=='
end
assert(Sync.EnqueueLogicalTransfer(directBacklog,
    {requester='Receiver',requestId='req-priority',chatWhisper=true}),
    'could not queue direct bulk backlog')
assert(Sync.HandleIncoming('WLLQ|Receiver|requested-exact','Receiver'),
    'valid exact-build request was rejected')
Pump(30)
local requestedResponse=false
for _,message in ipairs(H.sentChatMessages) do
    local wire=message.text:gsub('||','|')
    if wire:find('^WLRB|Source|requested%-exact|') then
        requestedResponse=true
    end
end
assert(requestedResponse,
    'requested exact build remained behind ordinary channel bulk backlog')
assert(Sync.WorkState().directSending>0,
    'exact-build response did not overtake the direct dependency backlog')

print('complete current sync, legacy recovery, and cooldown admission -- OK')
