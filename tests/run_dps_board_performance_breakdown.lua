-- DPS board diagnostics must distinguish repair, row construction, and sort.
local H = dofile("tests/harness.lua")
local Performance = Nexus.Performance
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")
dofile("core/DpsCapture.lua")

NexusDB = {
    communityBuilds={},
    dpsCapture={characterBest={dummy={},lk={}}},
}
Nexus.Store.Init()
Nexus.DpsCapture.Init({}, {})
Nexus.BuildCatalog.All = function()
    error("leaderboard repair requested a full catalog copy")
end
Performance.Reset()
local clock = 0
Performance.SetClock(function()
    clock = clock + 0.25
    return clock
end)
Performance.InstallDefaults()

NexusDB.dpsCapture.characterBest.lk.example = {
    player="Example", dps=100000, duration=60, level=80, ts=1,
    echoes={{spellId=200001, stacks=1}},
}
local board = Nexus.DpsCapture.GetDpsBoard("lk")
assert(#board == 1, "DPS board fixture did not produce one row")

for _, name in ipairs({
    "leaderboard.board",
    "leaderboard.board.migrations",
    "leaderboard.board.locked-baseline",
    "leaderboard.board.legacy",
    "leaderboard.board.class",
    "leaderboard.board.locked-backfill",
    "leaderboard.board.rows",
    "leaderboard.board.sort",
}) do
    local aggregate = Performance.Stats(name)
    assert(aggregate and aggregate.count > 0,
        "DPS board performance phase was not observed: " .. name)
end

print("DPS board performance phase breakdown -- OK")
