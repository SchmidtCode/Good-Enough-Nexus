local community = dofile("benchmarks/scenarios/community.lua")
local results = community.Run({rows=100,iterations=2,warmup=0})

assert(type(results) == "table" and #results == 4,
    "community benchmark did not return its four public operations")
for _, result in ipairs(results) do
    assert(type(result.name) == "string" and result.iterations == 2
        and result.latencyUnit ~= "" and result.throughputUnit ~= ""
        and result.averageMs >= 0 and result.p95Ms >= result.medianMs
        and result.maximumMs >= result.p95Ms
        and result.throughputPerSecond > 0,
        "community benchmark returned an incomplete observation")
end

local automation = dofile("benchmarks/scenarios/automation.lua")
local automationResults = automation.Run({iterations=2,warmup=0})
assert(type(automationResults) == "table" and #automationResults == 3,
    "automation benchmark did not return its three public operations")
for _, result in ipairs(automationResults) do
    assert(result.iterations == 2 and result.averageMs >= 0
        and result.p95Ms >= result.medianMs
        and result.throughputPerSecond > 0,
        "automation benchmark returned an incomplete observation")
end

local leaderboard = dofile("benchmarks/scenarios/leaderboard.lua")
local leaderboardResults = leaderboard.Run({rows=100,iterations=2,warmup=0})
assert(type(leaderboardResults) == "table" and #leaderboardResults == 4,
    "leaderboard benchmark did not return its four public operations")
for _, result in ipairs(leaderboardResults) do
    assert(result.iterations == 2 and result.averageMs >= 0
        and result.p95Ms >= result.medianMs
        and result.throughputPerSecond > 0,
        "leaderboard benchmark returned an incomplete observation")
end

local scheduler = dofile("benchmarks/scenarios/scheduler.lua")
local schedulerResults = scheduler.Run({iterations=2,warmup=0})
assert(type(schedulerResults) == "table" and #schedulerResults == 4,
    "scheduler benchmark did not return its four public operations")
for _, result in ipairs(schedulerResults) do
    assert(result.iterations == 2 and result.averageMs >= 0
        and result.p95Ms >= result.medianMs
        and result.throughputPerSecond > 0,
        "scheduler benchmark returned an incomplete observation")
end

local sync = dofile("benchmarks/scenarios/sync.lua")
local syncResults = sync.Run({requests=4,iterations=2,warmup=0})
assert(type(syncResults) == "table" and #syncResults == 3,
    "Sync benchmark did not return its three public operations")
for _, result in ipairs(syncResults) do
    assert(result.iterations >= 2 and result.averageMs >= 0
        and result.p95Ms >= result.medianMs
        and result.throughputPerSecond > 0,
        "Sync benchmark returned an incomplete observation")
end

print("automation, community, leaderboard, scheduler, and Sync benchmark scenarios -- OK")
