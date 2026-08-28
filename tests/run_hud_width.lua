local H = dofile("tests/harness.lua")
local fonts = {}
local realCreateFrame = CreateFrame
function CreateFrame(...)
    local frame = realCreateFrame(...)
    local createFont = frame.CreateFontString
    frame.CreateFontString = function(...)
        local font = createFont(...)
        fonts[#fonts + 1] = font
        return font
    end
    return frame
end
dofile("ui/Panel.lua")
NexusDB = {}
Nexus.Panel.Init({ToggleAuto=function() return false end})
local menu
EasyMenu = function(items) menu = items end
CloseDropDownMenus = function() end
Nexus.Panel.Render({progress={wishlistName="Wrand Fury Proc 85",owned=29,total=78,
    missing={"Arcane Cadence", "Archmage's Mark"},
    shed={"Agility Boost (Common) x2", "Armor Penetration"},
    unknownTomes={"Tome of Arcane Cadence"}}, cards={}, auto=false,level=80})
NexusPanel._menuBtn:GetScript("OnClick")(NexusPanel._menuBtn)
menu[3].func()
local width = NexusPanel:GetWidth()
for _, font in ipairs(fonts) do
    local point, parent, relative, x = font:GetPoint()
    if font:IsShown() and parent == NexusPanel and point == "TOPLEFT"
        and relative == "TOPLEFT" and x and font:GetText() ~= "" then
        assert(x + font:GetWidth() <= width - 8,
            "visible text extends past the HUD: " .. font:GetText())
    end
end
assert(width == 340, "HUD must use the requested 340-pixel width")
assert(NexusPanel:GetHeight() == 308, "active performance HUD must be 20 pixels taller")
print("wider HUD keeps visible columns inside the frame -- OK")
