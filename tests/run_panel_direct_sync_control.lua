local H = dofile("tests/harness.lua")
dofile("ui/Panel.lua")

NexusDB = {settings={syncDirectExperimental=false}}
local enabled = false
local changes = {}
Nexus.Sync = nil
local menuItems
EasyMenu = function(items) menuItems = items end
CloseDropDownMenus = function() end

Nexus.Panel.Init({
    DirectSyncEnabled = function() return enabled end,
    ToggleDirectSync = function()
        enabled = not enabled
        NexusDB.settings.syncDirectExperimental = enabled
        changes[#changes + 1] = enabled
        return enabled
    end,
})
Nexus.Panel.Render({progress={},cards={},recommendation="",auto=false,version="test"})
local menu = assert(NexusPanel and NexusPanel._menuBtn)
local function Find(label)
    menuItems = nil
    menu:GetScript("OnClick")(menu)
    local found
    local count = 0
    for _, item in ipairs(menuItems or {}) do
        if item.text == label then
            found = item
            count = count + 1
        end
    end
    assert(count == 1,
        "expected exactly one '" .. label .. "' menu item, found " .. count)
    return found
end

local off = assert(Find("Direct sync (experimental): OFF"),
    "settings menu did not expose default-off direct sync")
assert(not off.disabled)
off.func()
assert(enabled and NexusDB.settings.syncDirectExperimental == true,
    "menu did not use the controller's persistent direct-sync toggle")

local on = assert(Find("Direct sync (experimental): ON"),
    "settings menu did not refresh direct-sync state")
on.func()
assert(not enabled and NexusDB.settings.syncDirectExperimental == false)
assert(#changes == 2 and changes[1] == true and changes[2] == false,
    "menu did not report both direct-sync setting changes to the controller")

print("panel exposes persistent experimental direct-sync control -- OK")
