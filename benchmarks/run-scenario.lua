local name = tostring(arg and arg[1] or "")
local known = {
    automation="benchmarks/scenarios/automation.lua",
    community="benchmarks/scenarios/community.lua",
    leaderboard="benchmarks/scenarios/leaderboard.lua",
    scheduler="benchmarks/scenarios/scheduler.lua",
    sync="benchmarks/scenarios/sync.lua",
}
local path = known[name]
if not path then error("unknown benchmark scenario: " .. name) end

local quick = os.getenv and os.getenv("NEXUS_BENCHMARK_QUICK") == "1"
local options = {}
if quick then
    if name == "community" or name == "leaderboard" then
        options = {rows=200,iterations=10,warmup=2}
    elseif name == "automation" then
        options = {iterations=10,warmup=2}
    elseif name == "scheduler" then
        options = {iterations=100,warmup=10}
    else
        options = {requests=8,iterations=50,warmup=0}
    end
end

local Benchmark = dofile("benchmarks/Benchmark.lua")
local Scenario = dofile(path)
for _, result in ipairs(Scenario.Run(options)) do Benchmark.Print(result) end
