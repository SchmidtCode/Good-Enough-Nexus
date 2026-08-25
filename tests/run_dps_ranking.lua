Nexus = {}
dofile("core/DpsRanking.lua")

local R = Nexus.DpsRanking

assert(R.CharacterKey({ownerKey=" Alice @ Ebon Hold "}) == "alice@ebonhold")
assert(R.CharacterKey({player="Alice-Realm",realm="Ebon Hold"}) == "alice@ebonhold")
assert(R.CharacterKey({player="Alice"}) == "alice")
assert(R.CharacterKey({player="Alice",ownerKey="invalid"}) == "alice")

local dummy = {
    {player="Alice",ownerKey="alice@ebonhold",fingerprint="same",buildId="old",dps=100,ts=12},
    {player="Bob",ownerKey="bob@ebonhold",buildId=7,dps=80,ts=14},
}
local lk = {
    {player="Alice",ownerKey="alice@ebonhold",fingerprint="same",buildId="new",dps=200,ts=11},
    {player="Bob",ownerKey="bob@ebonhold",buildId=7,dps=120,ts=13},
    {player="Eve",ownerKey="eve@ebonhold",buildId=7,dps=999,ts=15},
}

local pairs = R.PairCategories(dummy, lk)
assert(#pairs == 2, "canonical pairing crossed character or lost a valid pair")

local combined = R.CombinedRows(dummy, lk)
assert(#combined == 2 and combined[1].player == "Alice" and combined[1].average == 150)
assert(combined[2].player == "Bob" and combined[2].average == 100)

local summary = R.Summary(dummy, lk)
assert(summary.dummy == 100 and summary.lk == 999 and summary.best == 999)
assert(summary.count == 2 and summary.average == 549.5)

assert(R.RecordKey({player="Alice",buildId=7}) == "alice|number:7")
assert(R.RecordKey({player="Alice",buildId="7"}) == "alice|string:7")

print("canonical DPS identity, pairing, and summaries -- OK")
