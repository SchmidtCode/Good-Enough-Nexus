-- Small observational benchmark reporter. Results describe the current run;
-- this module contains no thresholds and never decides whether a metric passed.

local Benchmark = {}

local NowMs = function() return os.clock() * 1000 end
do
    local loaded, ffi = pcall(require, "ffi")
    if loaded and ffi.os == "Windows" then
        pcall(ffi.cdef, [[
            int QueryPerformanceCounter(int64_t *value);
            int QueryPerformanceFrequency(int64_t *value);
        ]])
        local frequency = ffi.new("int64_t[1]")
        if ffi.C.QueryPerformanceFrequency(frequency) ~= 0 then
            local ticksPerSecond = tonumber(frequency[0])
            NowMs = function()
                local counter = ffi.new("int64_t[1]")
                ffi.C.QueryPerformanceCounter(counter)
                return tonumber(counter[0]) * 1000 / ticksPerSecond
            end
        end
    end
end

Benchmark.NowMs = NowMs

local function Finite(value, label)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        error((label or "value") .. " must be a finite number", 3)
    end
    return value
end

local function PositiveInteger(value, fallback, label)
    value = value == nil and fallback or Finite(value, label)
    value = math.floor(value)
    if value < 1 then error((label or "value") .. " must be positive", 3) end
    return value
end

local function Percentile(sorted, fraction)
    if #sorted == 0 then return 0 end
    local index = math.max(1, math.ceil(#sorted * fraction))
    return sorted[index]
end

function Benchmark.Summarize(name, samples, options)
    options = options or {}
    if type(name) ~= "string" or name == "" then error("benchmark name required", 2) end
    if type(samples) ~= "table" or #samples == 0 then
        error("at least one benchmark sample required", 2)
    end
    local sorted, sampleTotal = {}, 0
    for index, sample in ipairs(samples) do
        sample = Finite(sample, "sample " .. index)
        if sample < 0 then error("benchmark samples cannot be negative", 2) end
        sorted[index] = sample
        sampleTotal = sampleTotal + sample
    end
    table.sort(sorted)
    local operationsPerIteration = PositiveInteger(
        options.operationsPerIteration, 1, "operationsPerIteration")
    local operationIterations = PositiveInteger(
        options.operationIterations, #samples, "operationIterations")
    local workItems = options.workItems == nil
        and operationIterations * operationsPerIteration
        or Finite(options.workItems, "workItems")
    local totalMs = options.totalMs == nil
        and sampleTotal
        or Finite(options.totalMs, "totalMs")
    if workItems < 0 or totalMs < 0 then
        error("benchmark totals cannot be negative", 2)
    end
    return {
        name=name,
        latencyUnit=tostring(options.latencyUnit or "operation"),
        throughputUnit=tostring(options.throughputUnit or "operations"),
        iterations=#samples,
        operationIterations=operationIterations,
        operationsPerIteration=operationsPerIteration,
        workItems=workItems,
        totalMs=totalMs,
        minimumMs=sorted[1],
        averageMs=sampleTotal / #samples,
        medianMs=Percentile(sorted, 0.50),
        p95Ms=Percentile(sorted, 0.95),
        maximumMs=sorted[#sorted],
        throughputPerSecond=totalMs > 0 and workItems * 1000 / totalMs or math.huge,
    }
end

function Benchmark.Run(name, options, operation)
    options = options or {}
    if type(operation) ~= "function" then error("benchmark operation required", 2) end
    local iterations = PositiveInteger(options.iterations, 100, "iterations")
    local warmup = math.max(0, math.floor(Finite(options.warmup or 0, "warmup")))
    local minimumSampleMs = Finite(
        options.minimumSampleMs == nil and 5 or options.minimumSampleMs,
        "minimumSampleMs")
    if minimumSampleMs < 0 then error("minimumSampleMs cannot be negative", 2) end
    local maximumBatchIterations = PositiveInteger(
        options.maximumBatchIterations, 100000, "maximumBatchIterations")
    local clock = options.clock or Benchmark.NowMs
    if type(clock) ~= "function" then error("benchmark clock must be callable", 2) end
    for index = 1, warmup do operation(index, true) end
    local samples, totalMs, operationIterations = {}, 0, 0
    for index = 1, iterations do
        local startedAt = Finite(clock(), "benchmark start clock")
        local elapsed, batchIterations = 0, 0
        repeat
            operationIterations = operationIterations + 1
            batchIterations = batchIterations + 1
            operation(operationIterations, false)
            local finishedAt = Finite(clock(), "benchmark finish clock")
            elapsed = finishedAt - startedAt
            if elapsed < 0 then error("benchmark clock moved backward", 2) end
        until elapsed >= minimumSampleMs
            or batchIterations >= maximumBatchIterations
        samples[index] = elapsed / batchIterations
        totalMs = totalMs + elapsed
    end
    local summaryOptions = {}
    for key, value in pairs(options) do summaryOptions[key] = value end
    summaryOptions.operationIterations = operationIterations
    summaryOptions.totalMs = totalMs
    return Benchmark.Summarize(name, samples, summaryOptions)
end

function Benchmark.FormatLine(result)
    if type(result) ~= "table" then error("benchmark result required", 2) end
    return table.concat({
        "BENCHMARK", tostring(result.name), tostring(result.latencyUnit),
        tostring(result.throughputUnit), tostring(result.iterations),
        tostring(result.workItems), string.format("%.6f", result.totalMs),
        string.format("%.6f", result.minimumMs),
        string.format("%.6f", result.averageMs),
        string.format("%.6f", result.medianMs),
        string.format("%.6f", result.p95Ms),
        string.format("%.6f", result.maximumMs),
        string.format("%.6f", result.throughputPerSecond),
    }, "\t")
end

function Benchmark.Print(result)
    print(Benchmark.FormatLine(result))
    return result
end

return Benchmark
