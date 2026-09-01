Nexus = {}
dofile("core/DpsWireValidator.lua")

local Validator = Nexus.DpsWireValidator
local dependencies = {
    echoKey=function() return "fingerprint" end,
    echoHash=function() return "loadout-hash" end,
    samePeer=function(left, right) return left:lower() == right:lower() end,
    ownerMatches=function(owner, player)
        return owner == player:lower() .. "@ebonhold"
    end,
    localPlayer="Alice",
}
local valid = {
    f="fingerprint",h="loadout-hash",e={{spellId=700001,stacks=1}},
    c="dummy",d=25000000,u=60,t=50000,g=50000,p="Alice",l=80,
    k="MAGE",o="alice@ebonhold",
}

assert(Validator.Validate(valid, dependencies),
    "valid exact-loadout DPS payload was rejected")

local relayDependencies = {}
for key, value in pairs(dependencies) do relayDependencies[key] = value end
relayDependencies.localPlayer = "Relay"
relayDependencies.allowLegacyRelay = true
local relayed = {}
for key, value in pairs(valid) do relayed[key] = value end
relayed.v, relayed.y = 6, 1
assert(Validator.Validate(relayed, relayDependencies),
    "marked response-only legacy relay was rejected")
relayed.u, relayed.t, relayed.g = 0, 0, 0
assert(Validator.Validate(relayed, relayDependencies),
    "metadata-free marked legacy relay was rejected")
relayed.u, relayed.t, relayed.g = valid.u, valid.t, valid.g
relayed.v = 7
assert(not Validator.Validate(relayed, relayDependencies),
    "current protocol record bypassed direct-owner validation")
relayed.v, relayed.y = 6, nil
assert(not Validator.Validate(relayed, relayDependencies),
    "unmarked relay with claimed owner metadata was accepted")

for field, value in pairs({d=-1,u=29,t=0,g=-1,l=81,k="INVALID",p="Alice|spoof",
        c="arena",o="mallory@ebonhold",f="wrong",h="wrong"}) do
    local invalid = {}
    for key, original in pairs(valid) do invalid[key] = original end
    invalid[field] = value
    assert(not Validator.Validate(invalid, dependencies),
        "invalid DPS payload field was accepted: " .. field)
end

print("DPS wire metrics, identity, category, and exact loadout validation -- OK")
