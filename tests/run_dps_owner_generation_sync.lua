local H = dofile("tests/harness.lua")

dofile("core/DpsCapture.lua")

local DPS = Nexus.DpsCapture
local now = 50000
time = function() return now end
GetServerTime = function() return now end
UnitName = function() return "Relay" end
UnitClass = function() return "Mage", "MAGE" end
UnitLevel = function() return 80 end
GetNormalizedRealmName = function() return "Ebonhold" end

local echoes = {{spellId=200100, stacks=1}}
local fingerprint = DPS.GetEchoKey(echoes)
local build = {
    id="generation-build", title="Generation Build", author="Owner",
    class="MAGE", echoes=echoes, postedAt=1, lastModified=1,
}

local broadcasts = {}
local function reset()
    NexusDB = {
        communityBuilds={[build.id]=build}, syncTombstones={}, dpsCapture={},
    }
    broadcasts = {}
    DPS.Init({}, {
        BroadcastDpsRecord=function(record)
            broadcasts[#broadcasts + 1] = record
            return true
        end,
    })
end

local function record(dps, generation)
    return {
        v=7, f=fingerprint, h=DPS.GetEchoHash(echoes), e=echoes,
        c="dummy", d=dps, u=65, t=generation,
        g=generation, p="Owner", k="MAGE", l=80, b=build.id,
        o="owner@ebonhold", r="ebonhold",
    }
end

reset()
assert(DPS.ReceiveRecord(record(31000000, 100), "Owner"),
    "initial owner snapshot was rejected")
local staleHash = DPS.GetSyncHash()
assert(DPS.ReceiveRecord(record(30000000, 200), "Owner"),
    "newer owner generation did not replace the older higher DPS snapshot")
local ownerBoard = DPS.GetDpsBoard("dummy")
assert(ownerBoard[1].dps == 30000000 and ownerBoard[1].generationAt == 200,
    "owner generation was not retained on the canonical row")
assert(DPS.GetSyncHash() ~= staleHash,
    "owner generation did not participate in the sync digest")

reset()
assert(DPS.ReceiveRecord(record(31000000, 100), "Owner"),
    "downstream stale owner snapshot was rejected")
assert(DPS.ReceiveRecord(record(30000000, 200), nil, "legacy-relay"),
    "newer relayed owner generation did not replace stale direct evidence")
assert(not DPS.ReceiveRecord(record(32000000, 150), nil, "legacy-relay"),
    "older relayed generation rolled back newer owner state")
local downstream = DPS.GetDpsBoard("dummy")
assert(downstream[1].dps == 30000000
    and downstream[1].generationAt == 200
    and downstream[1].legacy == true,
    "downstream row did not preserve generation and local relay trust")

assert(DPS.BroadcastAllBuildBests("0") == 1,
    "relayed owner snapshot was not exportable to the next peer")
assert(#broadcasts == 1 and broadcasts[1].generationAt == 200,
    "next-hop export lost the owner generation")

print("DPS owner generation convergence and multi-hop relay: OK")
