local H = dofile("tests/harness.lua")
dofile("ui/Panel.lua")

NexusDB = {}
local autoSave = true
local menuItems
EasyMenu = function(items) menuItems = items end
CloseDropDownMenus = function() end

Nexus.Panel.Init({
    AutoSaveEnabled = function() return autoSave end,
    ToggleAutoSave = function()
        autoSave = not autoSave
        return autoSave
    end,
})
Nexus.Panel.Render({ progress = {}, cards = {}, recommendation = "",
    auto = false, version = "test" })

local menu = assert(NexusPanel and NexusPanel._menuBtn,
    "Nexus settings menu was not created")
local function OpenAndFind(expected)
    menuItems = nil
    menu:GetScript("OnClick")(menu)
    assert(type(menuItems) == "table", "settings menu did not open")
    for _, item in ipairs(menuItems) do
        if item.text == expected then return item end
    end
    error("missing settings action: " .. expected)
end

local enabled = OpenAndFind("Automatic Saved Build updates: ON")
enabled.func()
assert(autoSave == false, "visible auto-save control did not disable saving")

local disabled = OpenAndFind("Automatic Saved Build updates: OFF")
disabled.func()
assert(autoSave == true, "visible auto-save control did not re-enable saving")

print("panel exposes a visible persistent auto-save control -- OK")
