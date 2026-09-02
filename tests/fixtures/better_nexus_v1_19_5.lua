-- Frozen compatibility facts from Better Nexus tag v1.19.5, commit
-- d36a09f06be198dfb76cd1cc82bf437444f60cb2.
--
-- The packet rules came from core/Sync.lua and the digest rules came from
-- core/DpsCapture.lua. Keep this fixture offline and small. It is a contract,
-- not a vendored copy of the old addon.

local Fixture = {
    source = {
        tag = "v1.19.5",
        commit = "d36a09f06be198dfb76cd1cc82bf437444f60cb2",
    },
    packets = {
        unknown = {
            wire = "ZZV195|FuturePeer|payload",
            ignored = true,
        },
        WLRQ = {
            minimumFields = 2,
            maximumFields = 6,
            minimum = "WLRQ|LegacyBare",
            representative = "WLRQ|LegacyPeer|0|0|legacy-fixture|1.19.5",
            tooMany = "WLRQ|LegacyPeer|0|0|legacy-fixture-2|1.19.5|extra",
        },
        WLNP = {
            fields = 3,
            representative = "WLNP|PresencePeer|1.19.5",
        },
        WLBC = {
            fields = 7,
            representative = "WLBC|ClaimPeer|LegacyPeer|legacy-fixture|D|1|0",
        },
        WLRB = {
            fields = 6,
            representative = "WLRB|BuildPeer|fixture-build|1|1/2|AAAA",
            tooFew = "WLRB|BuildPeer|fixture-build|1|1/2",
            tooMany = "WLRB|BuildPeer|fixture-build|1|1/2|AAAA|extra",
        },
        WLD2 = {
            fields = 5,
            representative = "WLD2|DpsPeer|fixture-dps|1/2|AAAA",
            tooFew = "WLD2|DpsPeer|fixture-dps|1/2",
            tooMany = "WLD2|DpsPeer|fixture-dps|1/2|AAAA|extra",
        },
    },
    dps = {
        -- v1.19.5 hashes category, lowercase player key, floored DPS, and
        -- loadout hash. It sorts entries inside eight DJB2-selected buckets.
        -- Generation and evidence fields below must not affect this digest.
        expectedDigest = "0,76968a00,0,0,0,0,0,49951ce1",
        savedVariables = {
            characterBest = {
                dummy = {
                    alpha = {
                        player = "Alpha",
                        ownerKey = "alpha@ebonhold",
                        realm = "ebonhold",
                        dps = 12345.9,
                        loadoutHash = "abcd",
                        generationAt = 101,
                        evidence = "owner",
                        legacy = false,
                    },
                    foxtrot = {
                        player = "Foxtrot",
                        dps = 54321.8,
                        loadoutHash = "f00d",
                        generationAt = 909,
                        evidence = "relay",
                        legacy = true,
                    },
                    ignored = {
                        player = "Ignored",
                        dps = 0,
                        loadoutHash = "dead",
                    },
                },
                lk = {
                    bob = {
                        player = "Bob",
                        ownerKey = "bob@ebonhold",
                        realm = "ebonhold",
                        dps = 99999.99,
                        loadoutHash = "beef",
                        generationAt = 202,
                        evidence = "owner",
                        legacy = false,
                    },
                    carol = {
                        player = "Carol",
                        dps = 45678.1,
                        fingerprint = "200104x3",
                        generationAt = 303,
                        evidence = "relay",
                        legacy = true,
                    },
                },
            },
            personalBest = {},
            buildBest = {},
        },
    },
}

local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, child in pairs(value) do
        out[Copy(key)] = Copy(child)
    end
    return out
end

function Fixture.NewDpsCapture()
    return Copy(Fixture.dps.savedVariables)
end

return Fixture
