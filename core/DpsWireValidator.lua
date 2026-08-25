-- Nexus: core/DpsWireValidator.lua
-- Pure validation for exact-loadout DPS wire payloads.

Nexus = Nexus or {}
local Validator = {}
Nexus.DpsWireValidator = Validator

local VALID_CLASS = {
    WARRIOR=true,PALADIN=true,HUNTER=true,ROGUE=true,PRIEST=true,
    DEATHKNIGHT=true,SHAMAN=true,MAGE=true,WARLOCK=true,DRUID=true,
}

local function Finite(value)
    value = tonumber(value)
    return value and value == value and value ~= math.huge and value ~= -math.huge
end

local function InRange(value, minimum, maximum)
    value = tonumber(value)
    if not Finite(value) then return false end
    return value >= minimum and value <= maximum
end

local function ValidShape(payload)
    if type(payload) ~= "table" then return false end
    if type(payload.f) ~= "string" then return false end
    if type(payload.e) ~= "table" then return false end
    return payload.h ~= nil
end

local function ValidMetrics(payload)
    if not InRange(payload.d, 0.000001, 500000000) then return false end
    if not InRange(payload.u, 30, math.huge) then return false end
    if not InRange(payload.t, 0.000001, math.huge) then return false end
    if not InRange(payload.l, 1, 80) then return false end
    return tonumber(payload.l) == math.floor(tonumber(payload.l))
end

local function ValidPlayer(payload)
    local player = tostring(payload.p or "")
    if player == "" or #player > 64 then return false end
    if player:find("[%c|]") then return false end
    local class = type(payload.k) == "string" and payload.k:upper() or nil
    return VALID_CLASS[class] == true
end

local function ValidIdentity(payload, dependencies)
    if type(dependencies.samePeer) ~= "function" then return false end
    if type(dependencies.ownerMatches) ~= "function" then return false end
    if not dependencies.samePeer(tostring(payload.p or ""),
        tostring(dependencies.localPlayer or "")) then return false end
    return dependencies.ownerMatches(payload.o, tostring(payload.p or "")) == true
end

local function ValidLoadout(payload, dependencies)
    if type(dependencies.echoKey) ~= "function" then return false end
    local fingerprint = dependencies.echoKey(payload.e)
    if not fingerprint or fingerprint ~= payload.f then return false end
    if type(dependencies.echoHash) ~= "function" then return true end
    local hash = dependencies.echoHash(payload.e)
    return not hash or payload.h == hash
end

function Validator.Validate(payload, dependencies)
    dependencies = dependencies or {}
    if not ValidShape(payload) then return false end
    if payload.c ~= "dummy" and payload.c ~= "lk" then return false end
    if not ValidMetrics(payload) then return false end
    if not ValidPlayer(payload) then return false end
    if not ValidIdentity(payload, dependencies) then return false end
    return ValidLoadout(payload, dependencies)
end

return Validator
