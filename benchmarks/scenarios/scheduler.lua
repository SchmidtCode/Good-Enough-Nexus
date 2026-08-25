local Scenario = {}

function Scenario.Run(options)
    options = options or {}
    local Benchmark = dofile("benchmarks/Benchmark.lua")
    Nexus = {}
    local H = dofile("tests/harness.lua")
    NexusDB = {}
    Nexus.Errors.Init()
    local Scheduler = Nexus.Scheduler
    local iterations = math.max(1, math.floor(tonumber(options.iterations) or 1000))
    local warmup = math.max(0, math.floor(tonumber(options.warmup) or 50))

    local schedule = Benchmark.Run("scheduler.schedule.replace", {
        iterations=iterations,warmup=warmup,
        latencyUnit="schedule",throughputUnit="schedules",
    }, function()
        Scheduler.After("benchmark.replace", 1000000, function() end)
    end)
    Scheduler.Cancel("benchmark.replace")

    local cancel = Benchmark.Run("scheduler.schedule_cancel", {
        iterations=iterations,warmup=warmup,
        latencyUnit="cycle",throughputUnit="cycles",
    }, function()
        Scheduler.After("benchmark.cancel", 1000000, function() end)
        Scheduler.Cancel("benchmark.cancel")
    end)

    local callbacks = 0
    local tick = Benchmark.Run("scheduler.tick.32_due_callbacks", {
        iterations=iterations,warmup=warmup,operationsPerIteration=32,
        latencyUnit="tick",throughputUnit="callbacks",
    }, function()
        for index = 1, 32 do
            Scheduler.After(string.format("benchmark.due.%02d", index), 0,
                function() callbacks = callbacks + 1 end)
        end
        Scheduler.Tick(H.now)
    end)
    if callbacks ~= (tick.operationIterations + warmup) * 32 then
        error("scheduler benchmark did not execute every due callback")
    end

    local idle = Benchmark.Run("scheduler.tick.idle", {
        iterations=iterations,warmup=warmup,
        latencyUnit="tick",throughputUnit="ticks",
    }, function()
        Scheduler.Tick(H.now)
    end)
    return {schedule,cancel,tick,idle}
end

return Scenario
