-- Nexus: core/CommandRouter.lua
-- Normalized slash-command routing. Command handlers retain domain behavior;
-- this module owns only exact, alias, pattern, and fallback selection.

Nexus = Nexus or {}
local CommandRouter = {}
Nexus.CommandRouter = CommandRouter

local function Normalize(message)
    return tostring(message or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function TableOrEmpty(value)
    if type(value) == "table" then return value end
    return {}
end

local function FunctionOrNoop(value)
    if type(value) == "function" then return value end
    return function() end
end

function CommandRouter.New(options)
    options = options or {}
    local exact = TableOrEmpty(options.exact)
    local aliases = TableOrEmpty(options.aliases)
    local patterns = TableOrEmpty(options.patterns)
    local fallback = FunctionOrNoop(options.fallback)
    local router = {}

    function router.Dispatch(rawMessage)
        local message = Normalize(rawMessage)
        local command = aliases[message] or message
        local handler = exact[command]
        if handler then return handler(message) end
        for _, route in ipairs(patterns) do
            if message:match(route.pattern) then return route.handler(message) end
        end
        return fallback(message)
    end

    return router
end

return CommandRouter
