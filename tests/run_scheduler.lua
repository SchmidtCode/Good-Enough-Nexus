local H = dofile("tests/harness.lua")

NexusDB = {}
Nexus.Errors.Init()
dofile("core/Scheduler.lua")
local Scheduler = Nexus.Scheduler

-- One-shot replacement and cancellation are keyed and deterministic.
H.now = 1000
local calls = {}
assert(Scheduler.After("replace", 2, function() calls[#calls + 1] = "old" end))
assert(Scheduler.After("replace", 1, function() calls[#calls + 1] = "new" end))
assert(Scheduler.Tick(1000.9) == 0)
assert(Scheduler.Tick(1001) == 1 and table.concat(calls, ",") == "new",
    "same-key one-shot did not replace deterministically")
assert(Scheduler.After("cancel", 0, function() calls[#calls + 1] = "cancelled" end))
assert(Scheduler.Cancel("cancel") and not Scheduler.Cancel("cancel"))
assert(Scheduler.Tick(1001) == 0 and table.concat(calls, ",") == "new",
    "cancelled callback executed")

-- Repeating work runs at most once after a delayed frame and keeps its
-- original cadence rather than drifting from the delayed callback time.
H.now = 1001
local repeating = 0
assert(Scheduler.Every("repeat", 5, function() repeating = repeating + 1 end))
assert(Scheduler.Tick(1022) == 1 and repeating == 1)
assert(Scheduler.Pending("repeat").due == 1026,
    "delayed repeating task lost cadence")
assert(Scheduler.Tick(1025.9) == 0 and Scheduler.Tick(1026) == 1
    and repeating == 2, "repeating task was not bounded to one callback per tick")
assert(Scheduler.Cancel("repeat"))

-- A failed callback is retained while later keys still run.
local continued = false
assert(Scheduler.After("a.failure", 0, function() error("scheduled failure") end))
assert(Scheduler.After("b.continue", 0, function() continued = true end))
assert(Scheduler.Tick(1026) == 2 and continued,
    "callback failure stopped another due key")
local latest = Nexus.Errors.Latest()
assert(latest and latest.source == "Scheduler.a.failure"
    and latest.message:find("scheduled failure", 1, true),
    "scheduled callback failure was not retained")

-- Per-frame work is capped; remaining due keys continue on the next frame.
local capped = 0
for i = 1, 40 do
    assert(Scheduler.After(string.format("cap.%02d", i), 0, function()
        capped = capped + 1
    end))
end
assert(Scheduler.Tick(1026) == Scheduler.MaxCallbacksPerTick() and capped == 32)
assert(#Scheduler.Pending() == 8, "callback cap discarded remaining work")
assert(Scheduler.Tick(1026) == 8 and capped == 40 and #Scheduler.Pending() == 0)

-- Hostile timing/key values are rejected, and a module reload discards all
-- session-local tasks instead of replaying stale callbacks.
assert(not Scheduler.After("", 1, function() end))
assert(not Scheduler.After(string.rep("x", 129), 1, function() end))
assert(not Scheduler.After("nan", 0/0, function() end))
assert(not Scheduler.Every("zero", 0, function() end))
assert(Scheduler.After("reload", 1, function() error("stale task ran") end))
dofile("core/Scheduler.lua")
Scheduler = Nexus.Scheduler
assert(#Scheduler.Pending() == 0, "scheduler reload retained stale tasks")

-- A frame that rejects its update handler must not become a false initialized
-- scheduler; a later healthy initialization remains possible.
local realCreateFrame = CreateFrame
CreateFrame = function()
    return {SetScript=function() error("update handler rejected") end}
end
assert(not pcall(Scheduler.Init) and not Scheduler.IsInitialized(),
    "failed frame setup left a dead scheduler marked initialized")
CreateFrame = realCreateFrame
assert(Scheduler.Init() and Scheduler.IsInitialized(),
    "scheduler did not recover after frame setup became available")

-- Revision bursts coalesce the two noncritical data views. Status-only UI
-- remains an immediate direct repaint and does not enqueue another refresh.
dofile("core/Revisions.lua")
dofile("core/ViewRefresh.lua")
local Revisions = Nexus.Revisions
local communityRefreshes, leaderboardRefreshes, panelRefreshes, statusRefreshes = 0, 0, 0, 0
Nexus.CommunityBuilds = {Refresh=function() communityRefreshes = communityRefreshes + 1 end}
Nexus.Leaderboard = {Refresh=function() leaderboardRefreshes = leaderboardRefreshes + 1 end}
Nexus.Panel = {Refresh=function() panelRefreshes = panelRefreshes + 1 end}
assert(Nexus.ViewRefresh.Init())
assert(Revisions.Advance(Revisions.BUILD_LIBRARY_CHANGED, "one"))
assert(Revisions.Advance(Revisions.BUILD_LIBRARY_CHANGED, "two"))
assert(Revisions.Advance(Revisions.DPS_CHANGED, "three"))
statusRefreshes = statusRefreshes + 1
assert(statusRefreshes == 1 and communityRefreshes == 0 and leaderboardRefreshes == 0,
    "status-only UI stopped being immediate")
local pending = Scheduler.Pending()
assert(#pending == 1 and pending[1].key == Nexus.ViewRefresh.Key(),
    "data-view invalidations did not coalesce by key")
assert(Scheduler.Tick(H.now + 0.05) == 1)
assert(communityRefreshes == 1 and leaderboardRefreshes == 1 and panelRefreshes == 1,
    "coalesced data views did not refresh exactly once")

-- One view failure is recorded without suppressing the other view.
Nexus.CommunityBuilds.Refresh = function() error("community repaint failure") end
assert(Revisions.Advance(Revisions.DPS_CHANGED, "failure probe"))
assert(Scheduler.Tick(H.now + 0.10) == 1
    and leaderboardRefreshes == 2 and panelRefreshes == 2)
latest = Nexus.Errors.Latest()
assert(latest and latest.source == "ViewRefresh.CommunityBuilds"
    and latest.message:find("community repaint failure", 1, true),
    "view failure was not isolated and retained")

-- The real initialized scheduler owns one named Sync maintenance task. Sync
-- reinitialization replaces that key; it never creates automation tasks.
dofile("core/Codec.lua")
dofile("core/Sync.lua")
NexusDB.communityBuilds = {}
NexusDB.syncTombstones = {}
Nexus.Sync.Init(Nexus.Codec, {})
Nexus.Sync.Init(Nexus.Codec, {})
pending = Scheduler.Pending()
local syncTasks = 0
for _, task in ipairs(pending) do
    if task.key == "sync.pending-deletes" then
        syncTasks = syncTasks + 1
        assert(task.kind == "every" and task.interval == 1)
    end
    assert(not task.key:find("automation", 1, true)
        and not task.key:find("action", 1, true),
        "critical automation work entered the noncritical scheduler")
end
assert(syncTasks == 1, "Sync maintenance task was missing or duplicated")

print("keyed scheduling, bounded cadence, error isolation, coalescing, and Sync maintenance -- OK")
