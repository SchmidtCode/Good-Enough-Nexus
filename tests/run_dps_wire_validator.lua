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
    c="dummy",d=25000000,u=60,t=50000,p="Alice",l=80,
    k="MAGE",o="alice@ebonhold",
}

assert(Validator.Validate(valid, dependencies),
    "valid exact-loadout DPS payload was rejected")

for field, value in pairs({d=-1,u=29,t=0,l=81,k="INVALID",p="Alice|spoof",
        c="arena",o="mallory@ebonhold",f="wrong",h="wrong"}) do
    local invalid = {}
    for key, original in pairs(valid) do invalid[key] = original end
    invalid[field] = value
    assert(not Validator.Validate(invalid, dependencies),
        "invalid DPS payload field was accepted: " .. field)
end

print("DPS wire metrics, identity, category, and exact loadout validation -- OK")
