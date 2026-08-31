-- Level-80 comparison uses the live active loadout but retains the wishlist's
-- exact Echo quality requirements.
local H = dofile("tests/harness.lua")
H.AddEcho(200110, "Gamma Bolt", { quality = 0, groupId = 50 })
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
    version = "1.96.4", baseVersion = "1.19.5", published = true,
    releasesUrl = "https://github.com/Viscerals/Better-Nexus/releases",
}
NexusDB = { settings = { updateNotifications = true } }
H.playerLevel = 80
H.locked = {}
H.granted = {}

local target = {
    { spellId = 200111, stacks = 1 },
    { spellId = 200120, stacks = 1 },
}
local activeEchoes = {
    { spellId = 200110, stacks = 1 },
    { spellId = 200111, stacks = 2 },
    { spellId = 200112, stacks = 2 },
    { spellId = 200122, stacks = 1 },
}
H.DeliverSlots({
    [4] = { slot = 4, name = "Saved progress", verified = true,
        echoes = activeEchoes },
    [102] = { slot = 102, name = "Ideal target", verified = false,
        echoes = target },
}, 4)

Nexus.Store.Init()
Nexus.GameAdapter.Init({}, Nexus.Store)
assert(Nexus.GameAdapter.SetLoadoutWishlistIdentity(4, "Ideal target", target))
dofile("core/Main.lua")
H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("PLAYER_ENTERING_WORLD")
H.Advance(0.5)

local progress = assert(Nexus.Panel._lastModel and Nexus.Panel._lastModel.progress,
    "HUD did not publish level-80 progress")
assert(progress.owned == 1 and progress.total == 2 and #progress.missing == 1,
    "Rare Expertise Drills incorrectly satisfied the Uncommon target: "
        .. tostring(progress.owned) .. "/" .. tostring(progress.total)
        .. " missing=" .. table.concat(progress.missing or {}, ","))

local shed = {}
for _, label in ipairs(progress.shed or {}) do shed[label] = true end
assert(shed["Expertise Drills (Rare)"],
    "wrong-quality Expertise Drills was not marked TO SHED")
assert(shed["Gamma Bolt (Common)"]
    and shed["Gamma Bolt (Uncommon)"]
    and shed["Gamma Bolt (Rare) ×2"],
    "exact-quality excess was not reported correctly")

print("level-80 live progress retains exact wishlist qualities -- OK")
