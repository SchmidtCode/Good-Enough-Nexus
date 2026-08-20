local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Relay.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("ui/Readout.lua")
dofile("ui/Panel.lua")
dofile("ui/JournalTab.lua")

local calls = {wishlist=0,slots=0,owned=0,compile=0,render=0,panelRefresh=0}
local A = Nexus.GameAdapter
local realWishlist, realSlots, realOwned = A.Wishlist, A.Slots, A.Owned
A.Wishlist = function(...) calls.wishlist=calls.wishlist+1; return realWishlist(...) end
A.Slots = function(...) calls.slots=calls.slots+1; return realSlots(...) end
A.Owned = function(...) calls.owned=calls.owned+1; return realOwned(...) end
local realCompile = Nexus.Strategy.Compile
Nexus.Strategy.Compile = function(...)
    calls.compile = calls.compile + 1
    return realCompile(...)
end
local realRender, realPanelRefresh = Nexus.Panel.Render, Nexus.Panel.Refresh
Nexus.Panel.Render = function(...)
    calls.render = calls.render + 1
    return realRender(...)
end
Nexus.Panel.Refresh = function(...)
    calls.panelRefresh = calls.panelRefresh + 1
    return realPanelRefresh(...)
end

dofile("core/Main.lua")

NexusDB = {}
H.playerLevel = 5
H.granted = {}
H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("PLAYER_ENTERING_WORLD")
H.Advance(1)

local function SnapshotCalls()
    local out = {}
    for key, value in pairs(calls) do out[key] = value end
    return out
end

-- Polling remains direct at 0.2 seconds, but an unchanged interval performs no
-- plan, wishlist, owned, slot, or panel recomputation.
local stableCalls = SnapshotCalls()
local stableStats = Nexus.RecomputeStats()
H.Advance(1)
local afterStable = Nexus.RecomputeStats()
assert(afterStable.polls >= stableStats.polls + 5,
    "unchanged interval stopped the 0.2-second safety poll")
assert(afterStable.fullSteps == stableStats.fullSteps
    and calls.wishlist == stableCalls.wishlist
    and calls.slots == stableCalls.slots
    and calls.owned == stableCalls.owned
    and calls.compile == stableCalls.compile
    and calls.render == stableCalls.render,
    "unchanged ticks rebuilt plan/data/panel state")
assert(afterStable.skipped >= stableStats.skipped + 5,
    "unchanged safety polls were not counted as skipped recomputation")

-- Status-only presentation changes update the retained model without a full
-- adaptive render or an automation step.
local statusSteps, statusRenders = afterStable.fullSteps, calls.render
Nexus.Panel.SetStatus("status-only probe")
assert(Nexus.Panel._lastModel.status == "status-only probe"
    and Nexus.RecomputeStats().fullSteps == statusSteps
    and calls.render == statusRenders,
    "status-only update rebuilt a view or entered automation")

-- An explicit user refresh authorizes exactly one full step on the next safe
-- heartbeat; it does not bypass the direct tick or create a repeating task.
local explicitBefore = Nexus.RecomputeStats()
local explicitSlotReads = calls.slots
assert(Nexus.RequestRecompute())
H.Advance(0.2)
local explicitAfter = Nexus.RecomputeStats()
assert(explicitAfter.fullSteps == explicitBefore.fullSteps + 1
    and explicitAfter.forced == explicitBefore.forced + 1,
    "explicit refresh did not run exactly once on the next safe tick")
assert(calls.slots == explicitSlotReads + 1,
    "one full step materialized the server-slot payload more than once: before="
        .. tostring(explicitSlotReads) .. " after=" .. tostring(calls.slots))
H.Advance(0.2)
assert(Nexus.RecomputeStats().fullSteps == explicitAfter.fullSteps,
    "explicit refresh leaked into a repeating recomputation")

-- A burst of game-data invalidations is consumed once on the next safe tick.
local burstBefore = Nexus.RecomputeStats().fullSteps
local expensiveBefore = calls.wishlist + calls.slots + calls.owned + calls.compile
H.DeliverSlots({}, 0)
H.DeliverSlots({}, 0)
H.DeliverSlots({}, 0)
H.Advance(0.2)
local burstAfter = Nexus.RecomputeStats()
assert(burstAfter.fullSteps == burstBefore + 1 and burstAfter.dirty >= 1,
    "dirty burst did not coalesce into one full recomputation")
assert((calls.wishlist + calls.slots + calls.owned + calls.compile) > expensiveBefore,
    "dirty game data did not rebuild represented state")

-- Build/DPS revision bursts repaint noncritical views once through the keyed
-- scheduler and never authorize a full Main step.
local viewSteps = Nexus.RecomputeStats().fullSteps
local panelRefreshes = calls.panelRefresh
Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED, "one")
Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED, "two")
Nexus.Revisions.Advance(Nexus.Revisions.BUILD_LIBRARY_CHANGED, "three")
Nexus.Scheduler.Tick(H.now + 0.05)
assert(calls.panelRefresh == panelRefreshes + 1
    and Nexus.RecomputeStats().fullSteps == viewSteps,
    "revision burst failed to coalesce or entered automation")

-- Manual mode is fully reactive: a missed invalidation must not resurrect the
-- expensive five-second heartbeat while the player is idle.
local beforeManualIdle = Nexus.RecomputeStats()
local manualSlotRequests = H.slotRequests or 0
H.playerLevel = 6 -- intentionally bypass PLAYER_LEVEL_UP
H.Advance(beforeManualIdle.fallbackSeconds + 0.5)
assert(Nexus.RecomputeStats().fullSteps == beforeManualIdle.fullSteps,
    "manual idle mode ran an unconditional fallback recomputation")
assert((H.slotRequests or 0) == manualSlotRequests,
    "manual idle mode continued requesting an unchanged server-slot payload")

-- A concrete native build action schedules one settled refresh even though it
-- bypasses the Adapter's own write helpers.
assert(ProjectEbonhold.PerkService.ActivateServerBuildSlot(1))
H.Advance(0.6)
assert((H.slotRequests or 0) == manualSlotRequests + 1,
    "native build action did not schedule one dynamic slot refresh")

-- Active automation retains the slow self-healing heartbeat in case a client
-- invalidation hook is missed during a live run.
SlashCmdList.NEXUS("auto")
H.Advance(0.2)
local beforeFallback = Nexus.RecomputeStats()
H.playerLevel = 7 -- intentionally bypass PLAYER_LEVEL_UP
local remaining = beforeFallback.fallbackSeconds
    - (H.now - beforeFallback.lastFullStepAt)
if remaining > 0.3 then H.Advance(remaining - 0.2) end
assert(Nexus.RecomputeStats().fullSteps == beforeFallback.fullSteps,
    "active fallback recomputation ran before its slow heartbeat")
H.Advance(0.3)
local afterFallback = Nexus.RecomputeStats()
assert(afterFallback.fullSteps == beforeFallback.fullSteps + 1
    and afterFallback.fallbacks == beforeFallback.fallbacks + 1,
    "active automation fallback did not self-heal a missed invalidation")

-- A completed character has no recurring automation work; exact save/readback
-- checks already schedule their own deadlines.
H.playerLevel = 80
local completedIdle = Nexus.RecomputeStats()
H.Advance(completedIdle.fallbackSeconds + 0.5)
assert(Nexus.RecomputeStats().fullSteps == completedIdle.fullSteps,
    "level-80 idle mode ran an unconditional fallback recomputation")
SlashCmdList.NEXUS("auto") -- restore manual mode for the next scenario

-- The intent-to-action beat is an exact Main deadline: no dirty event is
-- needed between showing the decision and issuing the safe action.
H.wishlist = {name="Dirty Goal",class="MAGE",echoes={
    {spellId=200100,quality=3,stacks=1},
}}
H.DeliverSlots({
    [3]={slot=3,name="Dirty Goal",verified=false,echoes={
        {spellId=200100,quality=3,stacks=1},
    }},
}, 0)
assert(A.SetFirstRunWishlistIdentity(H.wishlist.name, H.wishlist.echoes))
H.granted = {}
A.RequestGranted()
H.playerLevel = 20
SlashCmdList.NEXUS("auto")
H.PushRunData({remainingBanishes=0,totalFreezes=0,usedFreezes=0,
    totalRerolls=0,usedRerolls=0})
local selectedBefore = #H.selectCalls
local deadlinesBefore = Nexus.RecomputeStats().deadlines
H.DeliverBoard({{spellId=200100,quality=3}})
H.Advance(0.2)
assert(#H.selectCalls == selectedBefore,
    "action fired before the visible intent deadline")
H.Advance(0.4)
assert(#H.selectCalls == selectedBefore + 1
    and Nexus.RecomputeStats().deadlines >= deadlinesBefore + 1,
    "due action deadline did not run on the next safe tick: selects="
        .. tostring(#H.selectCalls - selectedBefore)
        .. " deadlines=" .. tostring(Nexus.RecomputeStats().deadlines - deadlinesBefore)
        .. " full=" .. tostring(Nexus.RecomputeStats().fullSteps))

print("dirty, deadline, status, dynamic fallback, slot snapshot, and safety poll -- OK")
