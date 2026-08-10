-- Wishlist selection must support activeSlot=0 without weakening numbered
-- Saved Build validation.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("ui/WishlistEditor.lua")

NexusDB = {}
Nexus.Store.Init()
local A, E = Nexus.GameAdapter, Nexus.WishlistEditor
A.Init({}, Nexus.Store)
E.Init(A, Nexus.Model)

local wishlist = {
    slot=7, name="First Run Mage", verified=false,
    echoes={{spellId=200100,quality=3,stacks=1}},
}
H.DeliverSlots({[7]=wishlist}, 0)
local candidate = assert(A.GetWishlistCandidates()[1],
    "first-run wishlist candidate was unavailable")
local ok, err, target, firstRun = E.AssignWishlistCandidate(candidate)
assert(ok and err == nil and target == nil and firstRun == true,
    "activeSlot=0 did not use the first-run association: " .. tostring(err))
local selected = A.Wishlist()
assert(selected and selected.name == "First Run Mage"
    and selected.source == "first-run-wishlist",
    "first-run selection was not immediately resolvable")

H.DeliverSlots({
    [1]={slot=1,name="Saved Mage",verified=true,
        echoes={{spellId=200102,quality=2,stacks=1}}},
    [7]=wishlist,
}, 1)
candidate = assert(A.GetWishlistCandidates()[1])
ok, err, target, firstRun = E.AssignWishlistCandidate(candidate)
assert(ok and err == nil and target == 1 and firstRun == false,
    "numbered active loadout did not retain strict association behavior")
selected = A.Wishlist()
assert(selected and selected.name == "First Run Mage"
    and selected.source == "loadout-association",
    "numbered loadout association was not immediately resolvable")

print("wishlist first-run and numbered-loadout assignment routing -- OK")
