-- Keyed noncritical scheduler. Critical automation/FSM work must not be
-- registered here; Main keeps that work on its direct 0.2-second tick.

Nexus = Nexus or {}
local Scheduler = {}
Nexus.Scheduler = Scheduler

local tasks = {}
local generation = 0
local frame
local MAX_CALLBACKS_PER_TICK = 32

local function Finite(value)
    return type(value) == "number" and value == value
        and value < math.huge and value > -math.huge
end

local function Clock()
    if type(GetTime) == "function" then
        local ok, value = pcall(GetTime)
        value = ok and tonumber(value) or nil
        if Finite(value) then return value end
    end
    return 0
end

local function ValidKey(key)
    return type(key) == "string" and key ~= "" and #key <= 128
end

local function RecordError(key, err)
    local errors = Nexus and Nexus.Errors
    if errors and type(errors.Record) == "function" then
        pcall(errors.Record, "Scheduler." .. tostring(key), err)
    end
end

local function Schedule(kind, key, delay, callback)
    delay = tonumber(delay)
    if not ValidKey(key) or not Finite(delay)
        or delay < 0 or type(callback) ~= "function" then
        return false, "valid key, delay, and callback required"
    end
    if kind == "every" and delay <= 0 then
        return false, "repeating interval must be positive"
    end
    generation = generation + 1
    tasks[key] = {
        key=key, kind=kind, callback=callback, generation=generation,
        due=Clock() + delay, interval=kind == "every" and delay or nil,
    }
    return true
end

function Scheduler.After(key, delay, callback)
    return Schedule("after", key, delay, callback)
end

function Scheduler.Every(key, interval, callback)
    return Schedule("every", key, interval, callback)
end

function Scheduler.Cancel(key)
    if not ValidKey(key) or tasks[key] == nil then return false end
    tasks[key] = nil
    return true
end

function Scheduler.Tick(now)
    now = tonumber(now) or Clock()
    if not Finite(now) then return 0 end
    local due = {}
    for key, task in pairs(tasks) do
        if task.due <= now then
            due[#due + 1] = {
                key=key, due=task.due, generation=task.generation,
            }
        end
    end
    table.sort(due, function(left, right)
        if left.due ~= right.due then return left.due < right.due end
        return left.key < right.key
    end)

    local ran = 0
    for _, ready in ipairs(due) do
        if ran >= MAX_CALLBACKS_PER_TICK then break end
        local task = tasks[ready.key]
        if task and task.generation == ready.generation and task.due <= now then
            if task.kind == "after" then
                tasks[ready.key] = nil
            else
                local skipped = math.floor((now - task.due) / task.interval) + 1
                task.due = task.due + skipped * task.interval
            end
            ran = ran + 1
            local ok, err = pcall(task.callback, ready.key, now)
            if not ok then RecordError(ready.key, err) end
        end
    end
    return ran
end

function Scheduler.Pending(key)
    if key ~= nil then
        local task = tasks[key]
        if not task then return nil end
        return {key=task.key,kind=task.kind,due=task.due,interval=task.interval}
    end
    local out = {}
    for taskKey, task in pairs(tasks) do
        out[#out + 1] = {
            key=taskKey,kind=task.kind,due=task.due,interval=task.interval,
        }
    end
    table.sort(out, function(left, right)
        if left.due ~= right.due then return left.due < right.due end
        return left.key < right.key
    end)
    return out
end

function Scheduler.Init()
    if frame then return frame end
    if type(CreateFrame) ~= "function" then return nil end
    local candidate = CreateFrame("Frame")
    candidate:SetScript("OnUpdate", function()
        Scheduler.Tick()
    end)
    -- Publish initialized state only after the frame owns its update handler.
    -- A transient frame/API failure can then be recorded by Main and retried.
    frame = candidate
    return frame
end

function Scheduler.IsInitialized()
    return frame ~= nil
end

function Scheduler.MaxCallbacksPerTick()
    return MAX_CALLBACKS_PER_TICK
end
