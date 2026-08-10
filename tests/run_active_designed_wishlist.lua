-- An active designed wishlist is an exact server target even when multiple
-- designed candidates exist and no numbered Saved Build association exists.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")

NexusDB = {}
Nexus.Store.Init()
local A = Nexus.GameAdapter
A.Init({}, Nexus.Store)

H.DeliverSlots({
    [1] = { slot=1, name="Run 1", verified=true,
        echoes={{spellId=200100,quality=3,stacks=1}} },
    [101] = { slot=101, name="Other Wishlist", verified=false,
        echoes={{spellId=200102,quality=2,stacks=1}} },
    [102] = { slot=102, name="FUCK DUMMY", verified=false,
        echoes={{spellId=200104,quality=2,stacks=3}} },
}, 102)

local selected = A.Wishlist()
assert(selected and selected.name == "FUCK DUMMY"
    and selected.slot == 102 and selected.source == "designed",
    "active designed slot was not selected exactly")
assert(selected.byFamily.s200104
    and selected.byFamily.s200104.targetStacks == 3,
    "active designed wishlist lost its Echo stack target")
assert(A.WishlistNote() == "Active designed wishlist target",
    "active designed wishlist reported the first-run fallback note")

-- activeSlot=0 remains ambiguous and must not guess between the same rows.
H.DeliverSlots({
    [101] = { slot=101, name="Other Wishlist", verified=false,
        echoes={{spellId=200102,quality=2,stacks=1}} },
    [102] = { slot=102, name="FUCK DUMMY", verified=false,
        echoes={{spellId=200104,quality=2,stacks=3}} },
}, 0)
assert(A.Wishlist() == nil,
    "inactive multiple designed wishlists were guessed ambiguously")

print("active designed wishlist exact selection -- OK")
