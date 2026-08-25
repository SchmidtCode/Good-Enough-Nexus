local Scenario = {}

function Scenario.Run(options)
    options = options or {}
    local Benchmark = dofile("benchmarks/Benchmark.lua")
    Nexus = {}
    local H = dofile("tests/harness.lua")
    dofile("ui/Theme.lua")
    dofile("data/DefaultProfile.lua")
    dofile("core/Store.lua")

    UnitName = function() return "BenchmarkMage" end
    GetNormalizedRealmName = function() return "Ebonhold" end
    local rowCount = math.max(20, math.floor(tonumber(options.rows) or 1000))
    local iterations = math.max(1, math.floor(tonumber(options.iterations) or 100))
    local warmup = math.max(0, math.floor(tonumber(options.warmup) or 10))
    NexusDB = {
        communityBuilds={}, buildFilters={sortMode="title"},
        dpsCapture={characterBest={dummy={},lk={}},personalBest={},buildBest={}},
    }
    for index = 1, rowCount do
        local id = string.format("benchmark-build-%05d", index)
        NexusDB.communityBuilds[id] = {
            id=id, title=string.format("Benchmark Build %05d", index),
            author="Peer", ownerKey="peer@ebonhold", class="MAGE",
            postedAt=index, lastModified=index,
            fingerprint="benchmark-fingerprint-" .. index,
            echoes={{spellId=720000 + index,quality=3,stacks=1}},
        }
    end
    Nexus.Store.Init()
    dofile("core/DpsCapture.lua")
    Nexus.DpsCapture.Init({}, {})
    Nexus.Sync = {
        IsReceiving=function() return false end,
        LastSyncNewCount=function() return 0 end,
        ReceiveTimeLeft=function() return 0 end,
        Stats=function() return {received=0} end,
    }
    dofile("ui/CommunityBuilds.lua")
    local Builds = Nexus.CommunityBuilds
    Builds.Init(nil, nil)
    Builds.Show()
    if Builds.VirtualStats().results ~= 20 then
        error("community benchmark fixture did not open the bounded browser")
    end

    local common = {
        iterations=iterations, warmup=warmup,
        latencyUnit="refresh", throughputUnit="refreshes",
    }
    local cached = Benchmark.Run(
        string.format("community.refresh.cached.%d_rows", rowCount),
        common, function() Builds.Refresh() end)

    local rebuild = Benchmark.Run(
        string.format("community.refresh.rebuild.%d_rows", rowCount),
        common, function(index)
            Nexus.Revisions.Advance(Nexus.Revisions.BUILD_LIBRARY_CHANGED,
                {source="benchmark",sequence=index})
            Builds.Refresh()
        end)

    local scroll = Benchmark.Run(
        string.format("community.scroll.%d_rows", rowCount), {
            iterations=iterations, warmup=warmup,
            latencyUnit="scroll", throughputUnit="scrolls",
        }, function(index)
            Builds.ScrollTo((index % 20) * 92)
        end)

    return {cached, rebuild, scroll}
end

return Scenario
