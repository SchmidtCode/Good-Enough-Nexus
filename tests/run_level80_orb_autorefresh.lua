-- A level-80 Orb of Lost Memories changes GetActiveEchoLoadout without
-- changing the leveling-run granted table or necessarily firing a journal
-- event. The open HUD must notice that live loadout change promptly.
local H = dofile("tests/harness.lua")
H.AddEcho(200111, "Gamma Bolt", { quality = 1, groupId = 50 })
H.AddEcho(200112, "Gamma Bolt", { quality = 2, groupId = 50 })
H.AddEcho(200120, "Delta Ward", { quality = 1, groupId = 51 })
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Relay.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("ui/Theme.lua")
dofile("ui/Readout.lua")
dofile("ui/Panel.lua")
dofile("ui/JournalTab.lua")

Nexus.DpsCapture = { Init = function() end, OnUpdate = function() end }
Nexus.Release = {
    version = "1.96.5", baseVersion = "1.19.5", published = true,
    releasesUrl = "https://github.com/Viscerals/Better-Nexus/releases",
}
NexusDB = { settings = { updateNotifications = true } }
H.playerLevel = 80
H.locked = {}

local wrongQuality = {{ spellId = 200111, stacks = 1 }}
local orbResult = {{ spellId = 200112, stacks = 1 }}
local desired = {
    { spellId = 200112, stacks = 1 },
    { spellId = 200120, stacks = 1 },
}
H.granted = { current = wrongQuality }
H.wishlist = wrongQuality
H.DeliverSlots({
    [4] = { slot = 4, name = "Current saved build", verified = true,
        echoes = wrongQuality },
    [102] = { slot = 102, name = "Selected target", verified = false,
        echoes = desired },
}, 4)

Nexus.Store.Init()
Nexus.GameAdapter.Init({}, Nexus.Store)
assert(Nexus.GameAdapter.SetLoadoutWishlistIdentity(4, "Selected target", desired))
dofile("core/Main.lua")
H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("PLAYER_ENTERING_WORLD")
H.Advance(0.5)

local before = assert(Nexus.Panel._lastModel and Nexus.Panel._lastModel.progress,
    "HUD did not publish initial level-80 progress")
assert(#before.missing == 2 and #before.shed == 1,
    "test setup did not expose the wrong-quality active Echo")
local panel = assert(_G.NexusPanel, "visible HUD frame was not created")
local beforeNeeded = panel._needText:GetText()
local beforeShed = panel._shedText:GetText()

-- Ebonhold's live orb board updates GetGrantedPerks while the persisted
-- GetActiveEchoLoadout mirror can remain on the previously saved loadout.
-- No resave, reload, slash command, board hook, or journal event assists it.
H.granted = { current = orbResult }
H.Advance(6)

local after = assert(Nexus.Panel._lastModel and Nexus.Panel._lastModel.progress,
    "HUD disappeared after the orb replacement")
assert(#after.missing == 1 and #after.shed == 0,
    "open level-80 HUD stayed stale after the active Echo loadout changed")
local afterNeeded = panel._needText:GetText()
local afterShed = panel._shedText:GetText()
assert(afterNeeded ~= beforeNeeded and afterNeeded:find("Delta Ward", 1, true),
    "visible STILL NEEDED text did not repaint after the orb replacement")
assert(afterShed ~= beforeShed and afterShed:find("None", 1, true),
    "visible TO SHED text did not repaint after the orb replacement")

print("level-80 orb replacement refreshes the open HUD without resaving -- OK")
