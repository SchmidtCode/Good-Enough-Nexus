local H = dofile("tests/harness.lua")

local Adapter = Nexus.GameAdapter
H.playerLevel = 80
H.PushRunData({
    remainingBanishes = 0,
    totalRerolls = 0,
    usedRerolls = 0,
    totalFreezes = 1,
    usedFreezes = 0,
})
H.DeliverBoard({
    { spellId = 200100, quality = 1 },
    { spellId = 200200, quality = 1 },
})

assert(Adapter.Charges().freeze == 1,
    "level-80 final board should expose the available Freeze charge")
local ok, reason = Adapter.Freeze(0)
assert(ok, "level-80 final board refused an available Freeze: "
    .. tostring(reason))
assert(H.freezeCalls[#H.freezeCalls] == 0,
    "final-board Freeze did not reach the client service")

print("level-80 final wishlist pair can use Freeze -- OK")
