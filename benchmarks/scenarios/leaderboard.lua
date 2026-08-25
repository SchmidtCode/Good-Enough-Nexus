local Scenario = {}

function Scenario.Run(options)
    options = options or {}
    local Benchmark = dofile("benchmarks/Benchmark.lua")
    Nexus = {}
    dofile("tests/harness.lua")
    NexusDB = {communityBuilds={},buildFilters={},dpsCapture={}}

    local rowCount = math.max(20, math.floor(tonumber(options.rows) or 1000))
    local iterations = math.max(1, math.floor(tonumber(options.iterations) or 100))
    local warmup = math.max(0, math.floor(tonumber(options.warmup) or 10))
    local boards = {dummy={},lk={}}
    for index = 1, rowCount do
        local player = string.format("Benchmark Player %05d", index)
        local buildId = string.format("benchmark-ranked-%05d", index)
        local fingerprint = string.format("benchmark-fp-%05d", index)
        local class = index % 2 == 0 and "MAGE" or "ROGUE"
        local echoes = {
            {spellId=720000 + index,stacks=2},
            {spellId=730000 + index,stacks=1},
        }
        local build = {
            id=buildId,title=string.format("Ranked Build %05d", index),
            author=player,class=class,
        }
        boards.dummy[index] = {
            player=player,dps=30000000-index,duration=60,level=80,ts=index,
            category="dummy",fingerprint=fingerprint,buildId=buildId,
            echoes=echoes,build=build,
        }
        boards.lk[index] = {
            player=player,dps=28000000-index,duration=90,level=80,ts=index,
            category="lk",fingerprint=fingerprint,buildId=buildId,
            echoes=echoes,build=build,
        }
    end
    Nexus.DpsCapture = {
        GetDpsBoard=function(category) return boards[category] or {} end,
    }
    Nexus.Sync = {
        GetLeaderboardSyncStatus=function() return "idle",0,0,{} end,
        GetEffectiveState=function() return {key="idle"} end,
        RequestSync=function() return true end,
    }
    dofile("ui/Theme.lua")
    dofile("ui/Leaderboard.lua")
    local Leaderboard = Nexus.Leaderboard
    Leaderboard.Init(nil)
    Leaderboard.Show("dummy")
    if Leaderboard.VirtualStats().results ~= rowCount then
        error("leaderboard benchmark fixture did not publish every ranked row")
    end

    local common = {
        iterations=iterations,warmup=warmup,
        latencyUnit="refresh",throughputUnit="refreshes",
    }
    local cached = Benchmark.Run(
        string.format("leaderboard.refresh.cached.%d_rows", rowCount),
        common, function() Leaderboard.RefreshData() end)
    local rebuild = Benchmark.Run(
        string.format("leaderboard.refresh.rebuild.%d_rows", rowCount),
        common, function(index)
            Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,
                {source="benchmark",sequence=index})
            Leaderboard.RefreshData()
        end)
    local scroll = Benchmark.Run(
        string.format("leaderboard.scroll.%d_rows", rowCount), {
            iterations=iterations,warmup=warmup,
            latencyUnit="scroll",throughputUnit="scrolls",
        }, function(index)
            Leaderboard.ScrollTo((index % rowCount) * 40)
        end)
    local category = Benchmark.Run(
        string.format("leaderboard.category_switch.%d_rows", rowCount), {
            iterations=iterations,warmup=warmup,
            latencyUnit="switch",throughputUnit="switches",
        }, function(index)
            Leaderboard.SetCategory(index % 2 == 0 and "dummy" or "lk")
        end)
    return {cached,rebuild,scroll,category}
end

return Scenario
