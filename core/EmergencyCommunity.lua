-- Nexus emergency stutter-isolation mode.
--
-- The normal Community Builds, Leaderboard, DPS capture, bundled catalog, and
-- Sync transport modules are intentionally absent from this build's TOC. These
-- inert facades preserve callers while guaranteeing that no channel, catalog,
-- combat-capture, or community UI work can run. SavedVariables are not cleared
-- or migrated, so the disabled data remains available to a later build.

Nexus = Nexus or {}

local REASON = "Community Builds, Leaderboard, DPS capture, and Sync are temporarily disabled for stutter isolation."

Nexus.Emergency = {
    mode = "stutter-isolation",
    reason = REASON,
    communityDisabled = true,
    leaderboardDisabled = true,
    dpsDisabled = true,
    syncDisabled = true,
}

local function Notice()
    local text = "|cffffd200Nexus:|r " .. REASON
    if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        DEFAULT_CHAT_FRAME:AddMessage(text)
    elseif type(print) == "function" then
        print(text)
    end
    return false, REASON
end

local function Disabled() return false, REASON end
local function None() return nil end
local function Noop() return false end

------------------------------------------------------------------------
-- Sync: never joins, sends, receives, queues, hashes, or schedules work.
------------------------------------------------------------------------

local Sync = {}
Nexus.Sync = Sync

local syncStats = {
    disabled = true, sent = 0, received = 0, updated = 0,
    duplicatesSkipped = 0, malformedRejected = 0,
    ignoredOutsideWindow = 0, oversizeDropped = 0,
}

function Sync.Init() return true end
function Sync.EnsureChannel() return Disabled() end
function Sync.ChannelName() return "__nexus_sync_disabled__" end
function Sync.ChannelIndex() return nil end
function Sync.IsConnected() return false end
function Sync.IsReceiving() return false end
function Sync.ReceiveTimeLeft() return 0 end
function Sync.LastSyncNewCount() return 0 end
function Sync.Stats() return syncStats end
function Sync.WorkState() return {disabled=true,total=0} end
function Sync.ResponseStats() return {disabled=true,pending=0} end
function Sync.GetLeaderboardSyncStatus()
    return "disabled", 0, 0, {disabled=true,receiving=0}
end
function Sync.GetPeerInfo() return nil end
function Sync.IsKnownPeer() return false end
function Sync.TombstoneCount() return 0 end
function Sync.EventLog() return {} end
function Sync.RawLog() return {} end
function Sync.LogStats() return {disabled=true,count=0} end
function Sync.HashCacheStats() return {disabled=true} end
function Sync.GetCompatibilityHashes() return "disabled", "disabled" end
function Sync.GetCanonicalBuildHashes() return {} end
function Sync.GetLegacyBuildHash() return "disabled" end
function Sync.RequestSync() return Disabled() end
function Sync.RequestFullLoadoutSync() return Disabled() end
function Sync.RequestLoadout() return Disabled() end
function Sync.BroadcastBuild() return Disabled() end
function Sync.BroadcastBuildSummary() return Disabled() end
function Sync.BroadcastMine() return Disabled() end
function Sync.BroadcastDpsRecord() return Disabled() end
function Sync.BroadcastDps() return Disabled() end
function Sync.BroadcastDelete() return Disabled() end
function Sync.SendStatusTo() return Disabled() end
function Sync.HandleStatusRequest() return Disabled() end
function Sync.FlushStatusReply() return Disabled() end
function Sync.HandleIncoming() return Disabled() end
function Sync.CompactEncode() return Disabled() end
function Sync.RequestDataViewRefresh() return false end
function Sync.NoteTransportNotice() return false end
function Sync.LogEvent() return false end
function Sync.LogRaw() return false end
function Sync.ClearLog() return true end
function Sync.OnUpdate() return false end

------------------------------------------------------------------------
-- DPS capture: never inspects Details, combat, builds, or stored records.
------------------------------------------------------------------------

local DPS = {}
Nexus.DpsCapture = DPS

function DPS.Init() return true end
function DPS.IsEnabled() return false end
function DPS.IsDetailsAvailable() return false end
function DPS.OnCombatStart() return false end
function DPS.OnCombatEnd() return false end
function DPS.OnUpdate() return false end
function DPS.ReceiveRecord() return false end
function DPS.ReceiveSubmission() return false end
function DPS.BroadcastBestForBuild() return false end
function DPS.BroadcastAllBuildBests() return 0 end
function DPS.GetLeaderboard() return {} end
function DPS.GetLeaderboardForIdentity() return {} end
function DPS.GetLeaderboardForEchoes() return {} end
function DPS.GetDpsBoard() return {} end
function DPS.GetPersonalBest() return nil end
function DPS.GetPersonalBestForEchoes() return nil end
function DPS.GetBestRecordForEchoes() return nil end
function DPS.GetBuildVerification() return nil end
function DPS.GetCharacterBest() return nil end
function DPS.GetPlayerInfo() return nil end
function DPS.GetCurrentMatchingBuild() return nil end
function DPS.GetCurrentLeaderboard() return {} end
function DPS.GetCurrentPersonalBest() return nil end
function DPS.GetCurrentEchoCount() return 0 end
function DPS.GetCurrentEchoKey() return nil end
function DPS.GetEchoKey() return nil end
function DPS.GetEchoHash() return nil end
function DPS.MaterializeRecord() return nil end
function DPS.FindMatchingBuildPublic() return nil end
function DPS.GetSyncHash() return "disabled" end
function DPS.GetSyncHashUncached() return "disabled" end
function DPS.HashCacheStats() return {disabled=true} end
function DPS.IdentityLookupStats()
    return {disabled=true,rebuilds=0,rowsScanned=0,lookups=0,candidateChecks=0}
end
function DPS.DebugLogStats() return {disabled=true,count=0} end
function DPS.ClearDebugLog() return true end
function DPS.GetDebugLog()
    return "Nexus DPS capture log\n\nDPS capture is temporarily disabled for stutter isolation."
end

------------------------------------------------------------------------
-- UI facades: buttons and slash commands remain safe but open no windows.
------------------------------------------------------------------------

local Builds = {}
Nexus.CommunityBuilds = Builds

Builds.Init = function() return true end
Builds.Refresh = Noop
Builds.Hide = Noop
Builds.IsShown = Noop
Builds.MarkDataDirty = Noop
Builds.ScrollTo = Noop
Builds.GetSelectedBuildForPanel = None
Builds.IsOwnBuild = Noop
Builds.IsLockInPending = Noop
Builds.VirtualStats = function() return {disabled=true,results=0,active=0} end
Builds.GetViewMode = function() return "disabled" end
Builds.Show = Notice
Builds.Toggle = Notice
Builds.ShowBuild = Notice
Builds.ShowPostBuild = Notice
Builds.TogglePostPopup = Notice
Builds.ToggleEditPopup = Notice
Builds.Select = Disabled
Builds.SetViewMode = Disabled
Builds.PostCurrentWishlist = Disabled
Builds.PublishImportedBuild = Disabled
Builds.EditBuild = Disabled
Builds.UpdateFromWishlist = Disabled
Builds.DeleteBuild = Disabled
Builds.LockInSelected = Disabled
Builds.EnsureDpsBuildForEchoes = Disabled
Builds._PumpPendingLockIn = Noop

local Leaderboard = {}
Nexus.Leaderboard = Leaderboard

Leaderboard.Init = function() return true end
Leaderboard.Refresh = Noop
Leaderboard.RefreshData = Noop
Leaderboard.RefreshStatus = Noop
Leaderboard.Hide = Noop
Leaderboard.IsShown = Noop
Leaderboard.ScrollTo = Noop
Leaderboard.SelectKey = Noop
Leaderboard.SetCategory = Disabled
Leaderboard.SetClassFilter = Disabled
Leaderboard.VirtualStats = function() return {disabled=true,results=0,active=0} end
Leaderboard.Show = Notice
Leaderboard.Toggle = Notice
