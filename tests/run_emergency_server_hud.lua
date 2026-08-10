-- The community-off build must not hide Project Ebonhold's stock Ashes /
-- Intensity HUD, even when an existing save prefers Nexus's mirrored HUD.
local H = dofile("tests/harness.lua")
dofile("data/Release.lua")

local stock = H.NewRegion()
stock.hooks = {}
function stock:HookScript(which, fn) self.hooks[which] = fn end
function stock:Show()
    self.shown = true
    if self.hooks.OnShow then self.hooks.OnShow(self) end
end
_G.ProjectEbonholdPlayerRunFrame = stock

NexusDB = { soulAshHudMode = "nexus" }
dofile("ui/ServerStatus.lua")
Nexus.ServerStatus.Init()

stock:Show()
H.Advance(1.1)
assert(stock:IsShown(),
    "community-off scanner hid the stock Ashes / Intensity HUD")
assert(Nexus.ServerStatus.IsUsingNexusHud() == false,
    "community-off release did not force the stock server HUD")
assert(NexusDB.soulAshHudMode == "nexus",
    "emergency HUD fallback overwrote the user's saved preference")

stock:Show()
assert(stock:IsShown(),
    "community-off OnShow hook re-hid the stock server HUD")

print("emergency community-off stock server HUD -- OK")
