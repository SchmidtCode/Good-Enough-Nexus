-- Level-80 HUD comparison must read the live active Echo loadout. The
-- leveling-run granted table can differ after loading a saved build or using
-- Orb of Lost Memories and must not feed STILL NEEDED or TO SHED.
local H = dofile("tests/harness.lua")
H.AddEcho(200111, "Gamma Bolt", { quality = 1, groupId = 50 })
H.AddEcho(200112, "Gamma Bolt", { quality = 2, groupId = 50 })
H.AddEcho(200120, "Expertise Drills", { quality = 1, groupId = 51 })
H.AddEcho(200122, "Expertise Drills", { quality = 2, groupId = 51 })
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
    version = "1.96.3", baseVersion = "1.19.5", published = true,
    releasesUrl = "https://github.com/Viscerals/Better-Nexus/releases",
}
NexusDB = { settings = { updateNotifications = true } }
H.playerLevel = 80
H.locked = {}

H.granted = { stale = {{ spellId = 200200 }, { spellId = 200200 }} }
local current = {
    { spellId = 200112, stacks = 1 },
    { spellId = 200122, stacks = 1 },
}
H.wishlist = current
local target = {
    { spellId = 200112, stacks = 1 },
    { spellId = 200122, stacks = 1 },
}
H.DeliverSlots({
    [4] = { slot = 4, name = "Current saved build", verified = true,
        echoes = current },
    [102] = { slot = 102, name = "Selected target", verified = false,
        echoes = target },
}, 4)

Nexus.Store.Init()
Nexus.GameAdapter.Init({}, Nexus.Store)
assert(Nexus.GameAdapter.SetLoadoutWishlistIdentity(4, "Selected target", target))
dofile("core/Main.lua")
H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("PLAYER_ENTERING_WORLD")
H.Advance(0.5)

local progress = assert(Nexus.Panel._lastModel and Nexus.Panel._lastModel.progress,
    "HUD did not publish level-80 progress")
assert(progress.owned == 2 and progress.total == 2 and #progress.missing == 0,
    "STILL NEEDED used stale GetGrantedPerks instead of current level-80 Echoes")
assert(#(progress.shed or {}) == 0,
    "TO SHED used stale GetGrantedPerks instead of current level-80 Echoes")

-- The live mirror can briefly be an empty table while a saved loadout is
-- activating. That is unavailable data, not proof that the character has no
-- Echoes; use the verified active server slot during that window.
H.wishlist = {}
local fallback = Nexus.GameAdapter.CurrentOwned()
assert(fallback.source == "active-server-slot" and fallback.total == 2,
    "empty active-loadout mirror did not fall back to the verified server slot")

print("level-80 HUD compares current active Echoes against the selected build -- OK")
