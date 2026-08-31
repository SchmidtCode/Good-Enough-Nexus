Nexus = {}
dofile("core/CommandRouter.lua")

local calls = {}
local router = Nexus.CommandRouter.New({
    exact={
        status=function(message) calls[#calls + 1] = "status:" .. message end,
        ranks=function(message) calls[#calls + 1] = "ranks:" .. message end,
    },
    aliases={leaderboard="ranks"},
    patterns={
        {pattern="^anchor%s+",handler=function(message)
            calls[#calls + 1] = "anchor:" .. message
        end},
    },
    fallback=function(message) calls[#calls + 1] = "help:" .. message end,
})

router.Dispatch("  STATUS  ")
router.Dispatch("leaderboard")
router.Dispatch("anchor 700001")
router.Dispatch("unknown")

assert(table.concat(calls, "|")
    == "status:status|ranks:leaderboard|anchor:anchor 700001|help:unknown",
    "command router did not preserve exact, alias, pattern, and fallback behavior")

print("normalized exact, alias, pattern, and fallback command routing -- OK")
