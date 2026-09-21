-- A level-80 Orb can replace a missing requested Echo with a higher-quality
-- sibling. The HUD must count the better sibling toward progress while still
-- refusing the inverse, where a lower-quality sibling cannot satisfy a higher
-- target.
local H = dofile("tests/harness.lua")
H.AddEcho(200111, "Unbridled Fury", { quality = 1, groupId = 249 })
H.AddEcho(200112, "Unbridled Fury", { quality = 2, groupId = 249 })
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

local starting = {{ spellId = 200200, stacks = 1 }}
local requested = {{ spellId = 200111, stacks = 1 }}
H.granted = { current = starting }
H.wishlist = starting
H.DeliverSlots({
    [4] = { slot = 4, name = "Current saved build", verified = true,
        echoes = starting },
    [102] = { slot = 102, name = "Selected target", verified = false,
        echoes = requested },
}, 4)

Nexus.Store.Init()
Nexus.GameAdapter.Init({}, Nexus.Store)
assert(Nexus.GameAdapter.SetLoadoutWishlistIdentity(4, "Selected target", requested))
dofile("core/Main.lua")
H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("PLAYER_ENTERING_WORLD")
H.Advance(0.5)

local before = assert(Nexus.Panel._lastModel and Nexus.Panel._lastModel.progress)
assert(before.owned == 0 and before.total == 1 and #before.missing == 1,
    "test setup did not begin with Unbridled Fury missing")

assert(NexusPanel._needText.text:find("|cff1eff00Uncommon|r", 1, true),
    "Still Needed omitted the single-tier target quality/color")
GameTooltip = {
    lines = {}, SetOwner = function(self) self.lines = {} end,
    AddLine = function(self, text) self.lines[#self.lines + 1] = tostring(text or "") end,
    Show = function() end, Hide = function() end,
}
NexusPanel._needHit:GetScript("OnEnter")(NexusPanel._needHit)
assert(table.concat(GameTooltip.lines, "\n"):find("|cff1eff00Uncommon|r", 1, true),
    "Still Needed tooltip omitted the single-tier target quality/color")
-- The orb grants Rare while the selected target only asks for Uncommon.
H.granted = { current = {{ spellId = 200112, stacks = 1 }} }
H.Advance(6)

local current = Nexus.GameAdapter.CurrentOwned()
assert(current.source == "level80-granted" and current.bySpell[200112] == 1,
    "test setup did not expose the newer Rare orb result")
local after = assert(Nexus.Panel._lastModel and Nexus.Panel._lastModel.progress)
assert(after.owned == 1 and after.total == 1 and #after.missing == 0,
    "Rare Unbridled Fury did not satisfy the selected Uncommon target")
assert(#(after.shed or {}) == 0,
    "Rare Unbridled Fury was incorrectly listed to shed from an Uncommon target")

print("level-80 higher-quality Orb result satisfies lower-quality target -- OK")
