local testPath = assert(arg[1], "test path required")
local outputPath = assert(arg[2], "output path required")
local root = assert(arg[3], "repository root required"):gsub("\\", "/")
local hits = {}

local function Normalize(source)
    if type(source) ~= "string" or source:sub(1, 1) ~= "@" then return nil end
    local path = source:sub(2):gsub("\\", "/")
    if path:lower():sub(1, #root) == root:lower() then
        path = path:sub(#root + 1):gsub("^/", "")
    end
    return path:gsub("^%./", "")
end

debug.sethook(function(_, line)
    local info = debug.getinfo(2, "S")
    local source = info and Normalize(info.source)
    if source then
        local lines = hits[source]
        if not lines then lines = {}; hits[source] = lines end
        lines[line] = true
    end
end, "l")

local ok, failure = xpcall(function() dofile(testPath) end, debug.traceback)
debug.sethook()

local output = assert(io.open(outputPath, "w"))
for source, lines in pairs(hits) do
    for line in pairs(lines) do
        output:write(source, "\t", tostring(line), "\n")
    end
end
output:close()

if not ok then error(failure, 0) end

