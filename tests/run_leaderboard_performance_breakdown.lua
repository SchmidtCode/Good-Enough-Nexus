-- Leaderboard diagnostics must split a visible open into actionable phases.
local H = dofile("tests/harness.lua")
local Performance = Nexus.Performance

NexusDB = {communityBuilds={}, buildFilters={}, dpsCapture={}}
local boards = {dummy={}, lk={}}
for index = 1, 20 do
    local row = {
        player="Player " .. index,
        dps=1000000 - index,
        duration=60,
        level=80,
        ts=index,
        category="lk",
        fingerprint="fingerprint-" .. index,
        buildId="build-" .. index,
        echoes={{spellId=200000 + index, stacks=1}},
        build={id="build-" .. index, title="Build " .. index, class="MAGE"},
    }
    boards.lk[index] = row
    boards.dummy[index] = row
end

Nexus.DpsCapture = {
    GetDpsBoard=function(category) return boards[category] or {} end,
}
Nexus.Sync = {
    GetLeaderboardSyncStatus=function() return "idle", 0, 0, {} end,
    GetEffectiveState=function() return {key="idle"} end,
    RequestSync=function() return true end,
}

dofile("ui/Theme.lua")
dofile("ui/Leaderboard.lua")
local clock = 0
Performance.SetClock(function()
    clock = clock + 0.25
    return clock
end)
Performance.Reset()
Performance.InstallDefaults()
Nexus.Leaderboard.Init(nil)
Nexus.Leaderboard.Show("lk")

for _, name in ipairs({
    "leaderboard.open",
    "leaderboard.frame",
    "leaderboard.refresh",
    "leaderboard.projection",
    "leaderboard.board",
    "leaderboard.bind",
    "leaderboard.detail",
    "leaderboard.status",
}) do
    local aggregate = Performance.Stats(name)
    assert(aggregate and aggregate.count > 0,
        "leaderboard performance phase was not observed: " .. name)
end

assert(Performance.Stats("leaderboard.refresh").count == 1
    and Performance.Stats("leaderboard.open").count == 1,
    "one leaderboard open produced duplicate top-level measurements")

print("leaderboard performance phase breakdown -- OK")
