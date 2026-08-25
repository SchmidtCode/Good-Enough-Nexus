local H = dofile("tests/harness.lua")
local Engine = Nexus.SyncResponder.New({bucketCount=2, pendingTtl=5, pendingMaxAge=20})

local first = {createdAt=H.now,lastActiveAt=H.now,prepared=false,remaining=0}
local second = {createdAt=H.now,lastActiveAt=H.now,prepared=false,remaining=0}
assert(Engine.AdmitPending("response", "b", second, 2))
assert(Engine.AdmitPending("response", "a", first, 2))
assert(not Engine.AdmitPending("response", "c", {}, 2), "pending cap was not enforced")

local one = Engine.NextUnit()
local two = Engine.NextUnit()
assert(one.entryKey == "a" and two.entryKey == "b",
    "fair selection did not advance through sorted work")

first.prepared = true
first.buckets = { B2={remaining=0} }
first.bucketCursor = 0
Engine.DropPending("response", "b")
local bucket = Engine.NextUnit()
assert(bucket.type == "bucket" and bucket.id == "B2" and bucket.ordinal == 2,
    "ready bucket selection was not preserved")

Engine.AdvancePending(6, H.now + 6)
assert(Engine.PendingCount("response") == 0, "inactive work did not expire")

Engine.AdmitPending("loadout", "x", {
    createdAt=H.now,lastActiveAt=H.now,remaining=10,
}, 2)
Engine.AdvancePending(4, H.now + 4)
assert(Engine.loadouts.x.remaining == 6, "loadout delay was not advanced")
Engine.ClearPending()
assert(Engine.PendingCount("loadout") == 0, "pending state did not clear")

print("sync responder admission, expiry, bucket selection, and fairness -- OK")
