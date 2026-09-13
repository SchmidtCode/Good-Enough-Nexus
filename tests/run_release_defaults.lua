local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")
WishlistRealizerDB = nil
NexusDB = {}
Nexus.Store.Init()
local settings = Nexus.Store.Settings()
assert(settings.autoSave == false, "new installs must opt into server saves")
assert(settings.syncDirectExperimental == false, "whispers must stay opt-in")
assert(settings.autoLockEchoes == false, "locking must stay opt-in")
for _, choice in ipairs({true, false}) do
    NexusDB = {settings={autoSave=choice, syncDirectExperimental=choice,
        autoLockEchoes=choice, futureSetting="preserved"},
        futureData={keep=true}}
    Nexus.Store.Init()
    assert(NexusDB.settings.autoSave == choice)
    assert(NexusDB.settings.syncDirectExperimental == choice)
    assert(NexusDB.settings.autoLockEchoes == choice)
    assert(NexusDB.settings.futureSetting == "preserved" and NexusDB.futureData.keep)
end
print("release defaults are opt-in and preserve existing settings/data: OK")
