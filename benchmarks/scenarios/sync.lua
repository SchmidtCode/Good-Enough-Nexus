local Scenario = {}

function Scenario.Run(options)
    options = options or {}
    local Benchmark = dofile("benchmarks/Benchmark.lua")
    Nexus = {}
    local H = dofile("tests/harness.lua")
    dofile("core/Codec.lua")
    dofile("core/BuildHashCache.lua")
    dofile("core/Sync.lua")

    local Sync = Nexus.Sync
    local clock = 1000
    GetTime = function() return clock end
    time = function() return 50000 end
    UnitName = function() return "BenchmarkAlice" end
    GetNormalizedRealmName = function() return "Ebonhold" end
    local requestCount = math.max(2,
        math.min(64, math.floor(tonumber(options.requests) or 16)))
    local iterations = math.max(2, math.floor(tonumber(options.iterations) or 200))
    NexusDB = {
        settings={syncMode="automatic",syncOnlyWhileResting=false},
        communityBuilds={},syncTombstones={},dpsCapture={},
    }
    Sync.Init(Nexus.Codec, {})
    H.joinedChannels[Sync.ChannelName()] = 7
    local buildHash, dpsHash = Sync.GetCompatibilityHashes()

    local admission = Benchmark.Run(
        string.format("sync.request.admission.%d_requests", requestCount), {
            iterations=requestCount,warmup=0,
            minimumSampleMs=0,
            latencyUnit="request",throughputUnit="requests",
        }, function(index)
            local peer = "BenchmarkPeer" .. index
            local message = table.concat({
                "WLRQ",peer,buildHash,dpsHash,"benchmark-" .. index,"1.20.0",
            }, "|")
            if not Sync.HandleIncoming(message, peer) then
                error("Sync benchmark request admission failed")
            end
        end)

    local requestSamples = {}
    local startingWork = Sync.ResponseStats().workUnits
    local safety = 0
    while Sync.WorkState().pendingResponses > 0 do
        safety = safety + 1
        if safety > requestCount + 40 then
            error("Sync benchmark responder did not drain scheduled requests")
        end
        clock = clock + 0.1
        local before = Sync.ResponseStats().workUnits
        local startedAt = Benchmark.NowMs()
        Sync.OnUpdate(0.1)
        local elapsed = Benchmark.NowMs() - startedAt
        if Sync.ResponseStats().workUnits > before then
            requestSamples[#requestSamples + 1] = elapsed
        end
    end
    if Sync.ResponseStats().workUnits - startingWork ~= requestCount
        or #requestSamples ~= requestCount then
        error("Sync benchmark did not process exactly one work unit per request")
    end
    local response = Benchmark.Summarize(
        string.format("sync.request.response.%d_requests", requestCount),
        requestSamples, {
            latencyUnit="request",throughputUnit="requests",
        })

    local idle = Benchmark.Run("sync.update.idle", {
        iterations=iterations,warmup=math.floor(iterations / 10),
        latencyUnit="update",throughputUnit="updates",
    }, function()
        clock = clock + 0.001
        Sync.OnUpdate(0.001)
    end)
    return {admission,response,idle}
end

return Scenario
