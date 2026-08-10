-- Coalesced refreshes for noncritical data-browser views. Main HUD status and
-- all automation work remain direct and are intentionally not scheduled here.

Nexus = Nexus or {}
local ViewRefresh = {}
Nexus.ViewRefresh = ViewRefresh

local REFRESH_KEY = "ui.data-views.refresh"
local initialized = false
local schedulerReady = false

local function RecordError(source, err)
    local errors = Nexus and Nexus.Errors
    if errors and type(errors.Record) == "function" then
        pcall(errors.Record, source, err)
    end
end

local function SafeRefresh(source, callback)
    if type(callback) ~= "function" then return end
    local ok, err = pcall(callback)
    if not ok then RecordError(source, err) end
end

local function RefreshViews()
    SafeRefresh("ViewRefresh.CommunityBuilds",
        Nexus.CommunityBuilds and Nexus.CommunityBuilds.Refresh)
    SafeRefresh("ViewRefresh.Leaderboard",
        Nexus.Leaderboard and Nexus.Leaderboard.Refresh)
    SafeRefresh("ViewRefresh.Panel",
        Nexus.Panel and Nexus.Panel.Refresh)
end

function ViewRefresh.Request()
    local scheduler = Nexus.Scheduler
    if initialized and schedulerReady and scheduler
        and type(scheduler.After) == "function" then
        return scheduler.After(REFRESH_KEY, 0.05, RefreshViews)
    end
    RefreshViews()
    return true
end

function ViewRefresh.Init()
    if initialized then return true end
    initialized = true
    local scheduler = Nexus.Scheduler
    if scheduler and scheduler.Init then
        schedulerReady = scheduler.Init() ~= nil
    end
    local revisions = Nexus.Revisions
    if revisions and type(revisions.Subscribe) == "function" then
        revisions.Subscribe(revisions.BUILD_LIBRARY_CHANGED, ViewRefresh.Request)
        revisions.Subscribe(revisions.DPS_CHANGED, ViewRefresh.Request)
    end
    return true
end

function ViewRefresh.Key()
    return REFRESH_KEY
end
