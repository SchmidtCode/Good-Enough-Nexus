-- Independent Lua globals and real sync/DPS modules on both endpoints.
local function Client(name)
    local env=setmetatable({}, {__index=_G})
    env._G=env
    env.Nexus={}
    env.SlashCmdList={}
    env.dofile=function(path)
        local chunk=assert(loadfile(path)); setfenv(chunk,env); return chunk()
    end
    local h=env.dofile('tests/harness.lua')
    local send=env.SendChatMessage
    local lastSent
    env.SendChatMessage=function(...)
        local text=(...)
        if text:find('^WLTB:') then assert(not text:find('|',1,true),'pipe in lab bulk') end
        if text:find('^WLD2') or text:find('^WLRB') then
            error('SIMULATED_CHAT_PIPE_REJECTION')
        end
        if lastSent then assert(h.now-lastSent>=1.099,'lab increased send rate') end
        lastSent=h.now
        return send(...)
    end
    env.UnitName=function() return name end
    env.GetNormalizedRealmName=function() return 'Ebonhold' end
    env.GetRealmName=env.GetNormalizedRealmName
    env.time=function() return 50000 end
    env.dofile('core/Codec.lua')
    env.dofile('core/DpsWireValidator.lua')
    env.dofile('core/Sync.lua')
    env.dofile('core/DpsCapture.lua')
    env.dofile('core/SyncLab.lua')
    env.NexusDB={communityBuilds={},syncTombstones={},dpsCapture={},settings={}}
    env.Nexus.SyncPolicy={Mode=function() return 'manual' end,
        Allows=function() return true end}
    env.Nexus.Sync.Init(env.Nexus.Codec,{})
    env.Nexus.DpsCapture.Init({},env.Nexus.Sync)
    return {env=env,h=h,name=name,sync=env.Nexus.Sync,lab=env.Nexus.SyncLab,
        dps=env.Nexus.DpsCapture, sent=0}
end
local a,b=Client('Wrand'),Client('Daradorla')
b.env.NexusDB.syncTombstoneFloor=40000
local echoes={{spellId=200100,quality=3,stacks=1}}
for i=1,5 do
    local echoes=echoes
    if i==5 then
        echoes={}
        for n=1,63 do echoes[n]={spellId=200100+n,quality=3,stacks=1} end
    end
    local category=i%2==1 and 'dummy' or 'lk'
    local player='History'..i
    local id='historic-'..i
    a.env.NexusDB.communityBuilds[id]={id=id,title='Historic',author=player,
        class='MAGE',echoes=echoes,postedAt=40000,lastModified=40000}
    local store=a.env.NexusDB.dpsCapture.characterBest
    store[category][player:lower()..'@ebonhold']={player=player,category=category,
        ownerKey=player:lower()..'@ebonhold',realm='ebonhold',class='MAGE',level=80,
        echoes=echoes,fingerprint=a.dps.GetEchoKey(echoes),
        loadoutHash=a.dps.GetEchoHash(echoes),buildId=id,
        dps=10000000+i,duration=60,ts=40000,generationAt=40000}
end
-- A malformed historical row is inventoried but never made valid by the lab.
a.env.NexusDB.dpsCapture.characterBest.dummy.bad={player='Bad',dps=2,
    duration=0,level=0,class='?',buildId='bad'}
assert(not b.sync.HandleIncoming('WLTQ|Wrand|Daradorla|lab-1-1|5|CW1','Wrand'))
assert(b.lab.Start('receive','Wrand'))
assert(not b.sync.HandleIncoming('WLTQ|Intruder|Daradorla|lab-1-1|5|CW1','Intruder'))
assert(a.lab.Start('send','Daradorla',5))
assert(not b.sync._DecodeLabBulk('WLTB:WLD2~1Wrand~1id~11/1~1AAAA','Intruder'))
assert(not b.sync._DecodeLabBulk('WLTB:WLD2~9','Wrand'))
local lostAck=false
local function Deliver(from,to)
    while from.sent<#from.h.sentChatMessages do
        from.sent=from.sent+1
        local m=from.h.sentChatMessages[from.sent]
        assert(#m.text<=255,'lab exceeded wire envelope')
        if from==b and m.text:find('^WLA2') and not lostAck then
            lostAck=true -- exercise real timeout and channel fallback
        elseif m.kind=='CHANNEL' or m.target==to.name then
            if m.kind=='WHISPER' then
                assert(to.sync.IsDirectBulkWhisper(m.text,from.name),'chat event would reject lab envelope')
            end
            to.sync.HandleIncoming(m.text,from.name,m.kind)
        end
    end
end
for _=1,2900 do
    for _,client in ipairs({a,b}) do
        client.h.now=client.h.now+0.2
        client.sync.OnUpdate(0.2)
    end
    Deliver(a,b); Deliver(b,a)
end
local report=a.lab.Report()
local canonical='WLD2|Wrand|id~value|1/1|AAAA'
local wrapped=a.sync._EncodeLabBulk(canonical)
assert(b.sync._DecodeLabBulk(wrapped,'Wrand')==canonical,'envelope changed canonical bytes')
assert(not b.sync._DecodeLabBulk(wrapped,'Intruder'),'wrong-peer envelope accepted')
assert(not b.sync._DecodeLabBulk('WLTB:WLD2~9','Wrand'),'malformed escape accepted')
assert(not b.sync._DecodeLabBulk('WLTB:WLRQ~1Wrand','Wrand'),'control envelope accepted')
assert(report:find('finished=true',1,true),report)
assert(report:find('eligible third-party dummy=3 lk=2',1,true),report)
assert(report:find('BLOCKED Bad',1,true),report)
assert((a.sync.Stats().directContentAck or 0)>0,
    'real lab transfers received no ACKs\n'..b.lab.Report())
assert(b.sync.Stats().dpsIdempotentAccepted>0,'replay did not exercise idempotence')
assert((b.sync.Stats().dpsRelayAccepted or 0)>=5,
    'third-party history did not replicate\n'..b.lab.Report())
assert(b.lab.Report():find('older than compacted deletion floor',1,true),
    'test did not exercise the live deletion-floor dependency')
assert(lostAck and a.sync.Stats().directAckTimeout>0,'lost ACK was not exercised')
for i=1,5 do
    local category=i%2==1 and 'dummy' or 'lk'
    local row=b.dps.GetCharacterBest(category,'History'..i)
    assert(row and row.dps==10000000+i,'missing third-party record '..i)
    assert(row.legacy,'lab elevated relay into owner evidence')
end
assert(#report<60000,'lab report exceeded export limit')
print(string.format('lab five historical rows, replay, full/compact, channel: OK; TX=%d ACK=%d fallbacks=%d',
    a.sync.Stats().directBulkTx,a.sync.Stats().directContentAck,a.sync.Stats().directFallback))
a.lab.Stop('test'); b.lab.Stop('test')
assert(not b.sync._DecodeLabBulk(wrapped,'Wrand'),'unarmed envelope accepted')
assert(not a.sync._diagnostic and not b.sync._diagnostic)
assert(not a.sync.DirectTransportEnabled(),'lab did not restore direct setting')
assert(a.lab.Report():find('NEXUS SYNC LAB 1',1,true),'report lost on stop')

local lonely=Client('Lonely')
assert(lonely.lab.Start('send','Absent',1))
for _=1,300 do
    lonely.h.now=lonely.h.now+0.2
    lonely.sync.OnUpdate(0.2)
end
assert(not lonely.sync._diagnostic,'unarmed peer did not time out')
assert(lonely.lab.Report():find('peer did not arm/respond',1,true))
local unsafe=Client('Unsafe')
assert(unsafe.lab.Start('receive','Wrand'))
unsafe.env.Nexus.SyncPolicy.Allows=function() return false,'combat' end
unsafe.sync.OnUpdate(0.2)
assert(not unsafe.sync._diagnostic,'lab continued in unsafe context')
assert(unsafe.lab.Report():find('unsafe context',1,true))
print('lab pacing, opt-in, no-peer timeout, context stop, retained logs: OK')

-- A persistent API exception must produce actionable diagnostics and stop
-- the lab, not spend its entire deadline retrying the same channel packet.
assert(b.lab.Start('receive','Wrand'))
assert(a.lab.Start('send','Daradorla',1))
local originalSend=a.env.SendChatMessage
a.env.SendChatMessage=function(text,...)
    if text:find('^WLTB:WLD2') then error('LAB_TEST_INVALID_ESCAPE') end
    return originalSend(text,...)
end
for _=1,450 do
    for _,client in ipairs({a,b}) do
        client.h.now=client.h.now+0.2
        client.sync.OnUpdate(0.2)
    end
    Deliver(a,b); Deliver(b,a)
end
local failed=a.lab.Report()
assert(failed:find('LAB_TEST_INVALID_ESCAPE',1,true),'API exception was swallowed')
assert(failed:find('chunk=1/',1,true),'failed chunk missing')
assert(failed:find('wireBytes=',1,true),'escaped wire length missing')
assert(not a.sync._diagnostic,'persistent channel failure stalled the lab\n'..failed)
assert(failed:find('repeated channel API failure',1,true),'missing stop reason')
b.lab.Stop('test')
print('lab persistent send exception: bounded stop and retained error details OK')

-- Normal reconciliation, no lab session: a fresh recipient with a deletion
-- floor must receive the five peer-held records through negotiated CW2.
a.env.SendChatMessage=originalSend
b=Client('Daradorla')
b.env.NexusDB.syncTombstoneFloor=40000
a.env.NexusDB.settings.syncDirectExperimental=true
b.env.NexusDB.settings.syncDirectExperimental=true
assert(a.sync.RequestSync())
assert(b.sync.RequestSync())
lostAck=false
for _=1,2900 do
    for _,client in ipairs({a,b}) do
        client.h.now=client.h.now+0.2
        client.sync.OnUpdate(0.2)
    end
    Deliver(a,b); Deliver(b,a)
end
for i=1,5 do
    local category=i%2==1 and 'dummy' or 'lk'
    local row=b.dps.GetCharacterBest(category,'History'..i)
    assert(row and row.dps==10000000+i and row.legacy,
        'normal CW2 reconciliation lost historical record '..i)
end
assert(not a.sync._diagnostic and not b.sync._diagnostic,'normal test used lab mode')
assert(a.sync.Stats().directContentAck>0,'normal CW2 got no ACKs')
print('normal CW2 reconciliation transfers five historical records across deletion floor: OK')
