local Scenario = {}

function Scenario.Run(options)
    options = options or {}
    local Benchmark = dofile("benchmarks/Benchmark.lua")
    Nexus = {}
    local H = dofile("tests/harness.lua")
    dofile("data/DefaultProfile.lua")
    dofile("logic/Model.lua")
    dofile("logic/Strategy.lua")
    dofile("logic/Ratchet.lua")
    dofile("logic/Relay.lua")
    dofile("logic/Policy.lua")
    dofile("core/Store.lua")
    dofile("core/GameAdapter.lua")
    dofile("ui/Readout.lua")
    dofile("ui/Panel.lua")
    dofile("ui/JournalTab.lua")
    dofile("core/Main.lua")

    NexusDB = {}
    H.playerLevel = 5
    H.granted = {}
    H.FireEvent("ADDON_LOADED", "Nexus")
    H.FireEvent("PLAYER_ENTERING_WORLD")
    H.Advance(1)

    local iterations = math.max(1,
        math.floor(tonumber(options.iterations) or 100))
    local warmup = math.max(0, math.floor(tonumber(options.warmup) or 10))
    local common = {
        iterations=iterations,warmup=warmup,
        minimumSampleMs=0,
        latencyUnit="heartbeat",throughputUnit="heartbeats",
    }

    local idleBefore = Nexus.RecomputeStats().fullSteps
    local idleOptions = {
        iterations=math.min(iterations, 10),
        warmup=math.min(warmup, 10),
        minimumSampleMs=0,
        latencyUnit="heartbeat",throughputUnit="heartbeats",
    }
    local idle = Benchmark.Run("automation.heartbeat.idle", idleOptions, function()
        H.Advance(0.2, 0.2)
    end)
    if Nexus.RecomputeStats().fullSteps ~= idleBefore then
        error("idle heartbeat entered a full automation step")
    end

    local dirtyBefore = Nexus.RecomputeStats().fullSteps
    local dirty = Benchmark.Run("automation.full_step.dirty", common, function()
        H.DeliverSlots({}, 0)
        H.Advance(0.2, 0.2)
    end)
    if Nexus.RecomputeStats().fullSteps
        ~= dirtyBefore + dirty.operationIterations + warmup then
        error("dirty benchmark did not run one full step per invalidation")
    end

    H.playerLevel = 80
    local fallbackBefore = Nexus.RecomputeStats().fallbacks
    local fallback = Benchmark.Run("automation.full_step.level80_fallback", common,
        function()
            local seconds = Nexus.RecomputeStats().fallbackSeconds
            H.Advance(seconds + 0.1, seconds + 0.1)
        end)
    if Nexus.RecomputeStats().fallbacks
        < fallbackBefore + fallback.operationIterations + warmup then
        error("level-80 fallback benchmark did not enter the recovery step")
    end

    return {idle, dirty, fallback}
end

return Scenario
