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

-- The server slot mirror may disappear between drawing the candidate button
-- and handling its click.  Selection must use the already validated candidate
-- instead of performing a second fragile lookup.
local getCandidates = A.GetWishlistCandidates
A.GetWishlistCandidates = function() return {} end
local ok, err, target, firstRun = E.AssignWishlistCandidate(candidate)
A.GetWishlistCandidates = getCandidates
assert(ok and err == nil and target == nil and firstRun == true,
    "activeSlot=0 did not use the first-run association: " .. tostring(err))
local selected = A.Wishlist()
assert(selected and selected.name == "First Run Mage"
    and selected.source == "first-run-wishlist",
    "first-run selection was not immediately resolvable")

-- A transient empty SS-540 snapshot must not erase or hide the target.  The
-- stored identity is enough to retain the ordinary wishlist until live rows
-- return.
H.DeliverSlots({}, 0)
selected = A.Wishlist()
assert(selected and selected.name == "First Run Mage"
    and selected.source == "first-run-wishlist",
    "transient empty slots hid the selected first-run wishlist")

-- Existing users may only have the historical numbered association.  During
-- an activeSlot=0 transition, a sole stored link is the unambiguous fallback.
local state = Nexus.Store.State()
state.firstRunWishlist = nil
state.loadoutWishlists = {
    [1] = { slot=7, name="First Run Mage", key=A.WishlistKey(wishlist.echoes) },
}
selected = A.Wishlist()
assert(selected and selected.name == "First Run Mage"
    and selected.source == "first-run-wishlist",
    "sole historical loadout association was not retained at activeSlot=0")

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
