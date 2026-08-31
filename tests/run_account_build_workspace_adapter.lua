local H = dofile("tests/harness.lua")
local Workspace = Nexus.AccountBuildWorkspace
local stored = {}
for _, method in ipairs({"EnsureDpsBuildForEchoes", "PostCurrentWishlist",
    "PublishImportedBuild", "EditBuild", "UpdateFromWishlist", "DeleteBuild"}) do
    assert(type(Workspace[method]) == "function",
        "workspace named operation missing: " .. method)
end

dofile("core/GameAdapter.lua")
local runtimeIdentity = Nexus.GameAdapter.PlayerIdentity()
assert(runtimeIdentity.name == "Boganic" and runtimeIdentity.class == "MAGE"
    and runtimeIdentity.ownerKey == "boganic@ebonhold",
    "GameAdapter did not materialize the player identity")

Nexus.BuildCatalog = {
    Get=function(id) return stored[id] end,
    All=function() return stored end,
    Summaries=function() return stored end,
    Put=function(build) stored[build.id] = build; return true end,
    RemoveOverlay=function(id) stored[id] = nil; return true end,
    SetTombstone=function() return true end,
}

local identityReads, nowReads, timestampReads = 0, 0, 0
Workspace.Init({
    Catalog=function()
        return {rows={[700001]={classMask=128,quality=4}}}
    end,
    Slots=function()
        return {activeSlot=1,bySlot={
            [1]={slot=1,name="Adapter build",echoes={{spellId=700001,stacks=1}}},
        }}
    end,
    GetLoadoutWishlist=function() return nil end,
    PlayerIdentity=function()
        identityReads = identityReads + 1
        return {name="AdapterAlice",class="MAGE",realm="Ebonhold",
            ownerKey="adapteralice@ebonhold"}
    end,
    Now=function() nowReads = nowReads + 1; return 100 end,
    Timestamp=function() timestampReads = timestampReads + 1; return 50000 end,
})

UnitName = function() error("workspace touched UnitName") end
UnitClass = function() error("workspace touched UnitClass") end
GetNormalizedRealmName = function() error("workspace touched realm global") end
GetRealmName = function() error("workspace touched realm global") end
GetTime = function() error("workspace touched GetTime") end
time = function() error("workspace touched time") end

assert(Workspace.Import(true) == 1,
    "workspace did not import a Saved Build through its adapter")
local build = stored["saved-adapteralice_ebonhold-1"]
assert(build and build.author == "AdapterAlice" and build.class == "MAGE"
    and build.ownerKey == "adapteralice@ebonhold"
    and build.lastModified == 50000,
    "workspace did not use the injected identity and timestamp")
assert(Workspace.Owns(build),
    "workspace ownership did not use the injected identity")
assert(identityReads > 0 and nowReads > 0 and timestampReads > 0,
    "workspace did not read every required adapter value")

local function RelatedSelection(firstId, secondId)
    stored = {}
    for _, id in ipairs({firstId, secondId}) do
        stored[id] = {
            id=id,title="Adapter build",author="AdapterAlice",
            ownerKey="adapteralice@ebonhold",class="MAGE",
            echoes={{spellId=700001,stacks=1}},
        }
    end
    assert(Workspace.Import(true) == 1)
    return stored["saved-adapteralice_ebonhold-1"].recordBuildId
end

assert(RelatedSelection("z-related", "a-related") == "a-related"
    and RelatedSelection("a-related", "z-related") == "a-related",
    "equal related-build scores did not use the stable build ID tie-break")

Nexus.DpsCapture = {
    GetEchoKey=function(echoes)
        return tostring(echoes and echoes[1] and echoes[1].spellId or "")
    end,
}
local function DpsSelection(firstId, secondId)
    stored = {}
    for _, id in ipairs({firstId, secondId}) do
        stored[id] = {
            id=id,title=id,author="Remote",ownerKey="remote@ebonhold",
            class="MAGE",echoes={{spellId=700001,stacks=1}},
        }
    end
    local id = Workspace.EnsureDpsBuildForEchoes({{spellId=700001,stacks=1}},
        "dummy", {player="Remote",ownerKey="remote@ebonhold",class="MAGE"})
    return id
end

assert(DpsSelection("id-003", "id-002") == "id-002"
    and DpsSelection("id-002", "id-003") == "id-002",
    "equal DPS build matches did not use the stable build ID tie-break")

print("account build workspace uses only injected player IO -- OK")
