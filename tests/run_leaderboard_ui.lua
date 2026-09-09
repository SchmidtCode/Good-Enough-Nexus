-- Dedicated leaderboard is separate from Builds and renders dense ranked rows.
local H=dofile("tests/harness.lua")
dofile("core/Codec.lua"); dofile("core/Sync.lua"); dofile("core/DpsCapture.lua")
dofile("data/DefaultProfile.lua"); dofile("logic/Model.lua"); dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua"); dofile("logic/Policy.lua"); dofile("core/Store.lua")
dofile("core/GameAdapter.lua"); dofile("ui/CommunityBuilds.lua"); dofile("ui/Leaderboard.lua")
UnitName=function(unit) return unit=="player" and "Viewer" or nil end
UnitClass=function() return "Mage","MAGE" end
NexusDB={communityBuilds={},syncTombstones={},dpsCapture={}}
local DPS=Nexus.DpsCapture
DPS.Init({}, {BroadcastBuild=function() return true end})
date=function(_,stamp)
    if tonumber(stamp)==1700000000 then return "2023-11-14 22:13" end
    return "unexpected"
end
local a={{spellId=200001,stacks=2},{spellId=200002,stacks=1}}
local b={{spellId=200010,stacks=1},{spellId=200011,stacks=3}}
assert(DPS.ReceiveRecord({v=4,f=DPS.GetEchoKey(a),e=a,c="dummy",d=24000000,u=65,t=1700000000,p="Alpha",k="MAGE",l=80},"Alpha"))
assert(DPS.ReceiveRecord({v=4,f=DPS.GetEchoKey(b),e=b,c="dummy",d=28000000,u=65,t=0,p="Bravo",k="MAGE",l=80},nil,"legacy-relay"))
Nexus.CommunityBuilds.Init(Nexus.GameAdapter,Nexus.Model)
Nexus.Leaderboard.Init(Nexus.GameAdapter)

-- Capture the actual row widgets created by the UI. Assertions below inspect
-- rendered text, not a formatting helper that could pass while the screen is
-- wired incorrectly.
local createdFrames={}
local createFrame=CreateFrame
CreateFrame=function(...)
    local widget=createFrame(...)
    createdFrames[#createdFrames+1]=widget
    return widget
end
Nexus.Leaderboard.Show("dummy")
assert(H.frames.NexusLeaderboardFrame and H.frames.NexusLeaderboardFrame:IsShown(),"leaderboard window did not open")

local function BoardRow(player)
    for _,row in ipairs(DPS.GetDpsBoard("dummy")) do
        if row.player==player then return row end
    end
end
local function RenderedRow(player)
    for _,widget in ipairs(createdFrames) do
        if widget.data and widget.data.player==player then
            return widget
        end
    end
end

local relay=BoardRow("Bravo")
local owner=BoardRow("Alpha")
assert(relay and relay.evidence=="relay" and relay.verified==false,
    "relay fixture did not expose explicit presentation provenance")
assert(owner and owner.evidence=="owner" and owner.verified==true,
    "owner fixture did not expose explicit presentation provenance")
local relayWidget=RenderedRow("Bravo")
local ownerWidget=RenderedRow("Alpha")
assert(relayWidget and relayWidget.extra:GetText():find("Relayed",1,true),
    "relay leaderboard row did not show a concise provenance marker: "
        .. tostring(relayWidget and relayWidget.extra:GetText()))
assert(ownerWidget and not ownerWidget.extra:GetText():find("Relayed",1,true),
    "owner leaderboard row was incorrectly marked as relayed")
assert(ownerWidget.extra:GetText():find("2023-11-14",1,true),
    "leaderboard row did not display its capture date")
assert(relayWidget.extra:GetText():find("Date unavailable",1,true),
    "legacy leaderboard row invented or omitted an unavailable capture date")

local detail=H.frames.NexusLeaderboardFrame._leaderboardDetail
assert(Nexus.Leaderboard.SelectKey(Nexus.DpsRanking.RecordKey(relay)))
assert(detail.owner:GetText():find("Relayed",1,true),
    "relay leaderboard detail did not show a provenance marker")
assert(detail.record:GetText():find("Capture date unavailable",1,true),
    "legacy leaderboard detail did not explain its missing capture date")
assert(Nexus.Leaderboard.SelectKey(Nexus.DpsRanking.RecordKey(owner)))
assert(not detail.owner:GetText():find("Relayed",1,true),
    "owner leaderboard detail was incorrectly marked as relayed")
assert(detail.record:GetText():find("Captured 2023-11-14 22:13",1,true),
    "leaderboard detail did not display its capture date and time")
print("leaderboard list and detail distinguish relay evidence -- OK")

-- Refreshing a selected record must use WoW 3.3.5 Button:Enable/Disable, not modern SetEnabled.
Nexus.Leaderboard.Refresh()
assert(not H.frames.NexusCommunityBuildsFrame or not H.frames.NexusCommunityBuildsFrame:IsShown(),"build browser should not be required for leaderboard")
Nexus.CommunityBuilds.SetViewMode("lk")
assert(Nexus.Leaderboard.IsShown(),"legacy leaderboard route did not open dedicated window")
print("dedicated dense leaderboard window and legacy routing -- OK")
