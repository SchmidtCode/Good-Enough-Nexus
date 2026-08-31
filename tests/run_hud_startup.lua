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
dofile("core/Main.lua")

NexusDB = { hasSeenQuickStart=true }
H.playerLevel = 80
H.granted = {}
H.locked = {}
H.DeliverSlots({
    [6]={slot=6, name="Level 80 Goal", verified=false, echoes={
        {spellId=200100, quality=3, stacks=1},
    }},
}, 6)

H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("PLAYER_ENTERING_WORLD")
H.Advance(1)

local model = Nexus.Panel._lastModel
assert(model and model.progress and model.progress.wishlistName == "Level 80 Goal",
    "level-80 startup with no board left the compact HUD blank")
assert(_G.NexusPanel and _G.NexusPanel:IsShown(),
    "level-80 startup did not show the compact HUD")

print("level-80 startup renders idle wishlist progress without a board -- OK")
