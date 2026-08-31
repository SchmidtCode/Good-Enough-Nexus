-- A locally confirmed pick bridges the short GetGrantedPerks delay, then
-- retires once the server reports it. Later quality replacement must not leave
-- the old spell in current ownership.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Relay.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")

local A = Nexus.GameAdapter
NexusDB = {}
Nexus.Store.Init()
A.Init({}, Nexus.Store)
H.playerLevel = 5
H.granted = {}
A.OnEvent("PLAYER_ENTERING_WORLD")

H.DeliverBoard({
    { spellId=200110, quality=0 },
    { spellId=200202, quality=1 },
})
assert(A.Take(200110), "fixture could not select the Common quality")
H.ResolveSelect(true)
A.Poll()
local bridged = A.Owned()
assert(bridged.bySpell[200110] == 1,
    "confirmed local pick did not bridge the server ownership delay")

H.granted = { gamma={{spellId=200110,stack=1,quality=0}} }
A.RequestGranted()
local caughtUp = A.Owned()
assert(caughtUp.bySpell[200110] == 1,
    "server-confirmed pick was not retained")

H.granted = { gamma={{spellId=200112,stack=1,quality=2}} }
A.RequestGranted()
local replaced = A.Owned()
assert((replaced.bySpell[200110] or 0) == 0
    and replaced.bySpell[200112] == 1,
    "retired local pick survived after the server replaced its quality")

print("local pick bridge retires after server ownership catches up -- OK")
