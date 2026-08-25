local Benchmark = dofile("benchmarks/Benchmark.lua")

local firstClock = Benchmark.NowMs()
local secondClock = Benchmark.NowMs()
assert(type(firstClock) == "number" and secondClock >= firstClock,
    "benchmark clock should be a monotonic public timing seam")

local summary = Benchmark.Summarize("sync.request", {1, 2, 3, 4, 10}, {
    latencyUnit="request", throughputUnit="requests",
    operationsPerIteration=1,
})
assert(summary.iterations == 5 and summary.workItems == 5
    and summary.totalMs == 20 and summary.averageMs == 4
    and summary.medianMs == 3 and summary.p95Ms == 10
    and summary.maximumMs == 10 and summary.throughputPerSecond == 250,
    "benchmark summary did not report known latency and throughput values")

local clockValues = {0, 2, 2, 6}
local calls = 0
local measured = Benchmark.Run("scheduler.tick", {
    iterations=2, warmup=1, operationsPerIteration=5,
    minimumSampleMs=0,
    latencyUnit="tick", throughputUnit="callbacks",
    clock=function() return table.remove(clockValues, 1) end,
}, function()
    calls = calls + 1
end)
assert(calls == 3 and measured.averageMs == 3
    and measured.medianMs == 2 and measured.p95Ms == 4
    and measured.workItems == 10
    and math.abs(measured.throughputPerSecond - (10000 / 6)) < 0.0001,
    "benchmark runner did not separate warmup, latency, and throughput work")

local batchClock = {0, 0, 0, 2}
local batchCalls = 0
local batched = Benchmark.Run("scheduler.schedule", {
    iterations=1, warmup=0, operationsPerIteration=4,
    minimumSampleMs=2, maximumBatchIterations=10,
    latencyUnit="schedule", throughputUnit="callbacks",
    clock=function() return table.remove(batchClock, 1) end,
}, function()
    batchCalls = batchCalls + 1
end)
assert(batchCalls == 3 and batched.iterations == 1
    and batched.operationIterations == 3 and batched.workItems == 12
    and math.abs(batched.averageMs - (2 / 3)) < 0.0001
    and batched.totalMs == 2 and batched.throughputPerSecond == 6000,
    "benchmark runner did not amortize operations below the clock resolution")

local line = Benchmark.FormatLine(summary)
assert(line:find("^BENCHMARK\t")
    and line:find("sync.request", 1, true)
    and line:find("\t4.000000\t3.000000\t10.000000\t10.000000\t250.000000$"),
    "machine-readable benchmark line is incomplete")

print("benchmark averages, p95 latency, and throughput calculations -- OK")
