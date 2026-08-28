local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")

local Adapter = Nexus.GameAdapter
NexusDB = {}
H.playerLevel = 20
H.granted = { first={{spellId=200100}} }
H.locked = {}
H.discovered = {}

Adapter.OnEvent("PLAYER_ENTERING_WORLD")
Adapter.Poll()
Adapter.ConsumeDirty()

Adapter.Poll()
local _, _, unchanged = Adapter.ConsumeDirty()
assert(not unchanged, "unchanged progress repainted the HUD")

H.granted.second = {{spellId=200200}}
Adapter.OnEvent("SPELLS_CHANGED")
Adapter.Poll()
local _, _, learnedEcho = Adapter.ConsumeDirty()
assert(learnedEcho, "learning an Echo did not refresh progress")

H.discovered[200300] = true
Adapter.OnEvent("LEARNED_SPELL_IN_TAB")
Adapter.Poll()
local _, _, learnedTome = Adapter.ConsumeDirty()
assert(learnedTome, "learning a tome did not refresh Missing Tomes")

H.now = H.now + 6
Adapter.Poll()
local _, _, stablePoll = Adapter.ConsumeDirty()
assert(not stablePoll, "stable learning data dirtied progress on its timed poll")

print("Echo and tome learning refresh only changed HUD progress -- OK")
