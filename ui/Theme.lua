-- Nexus dark UI theme. Keeps controls native-looking without the bright red
-- UIPanelButton artwork used by the stock 3.3.5 templates.
Nexus = Nexus or {}
Nexus.Theme = Nexus.Theme or {}
local T = Nexus.Theme

local function TextRegion(button)
    if button.GetFontString then return button:GetFontString() end
    return button.text
end

function T.StyleButton(button, compact)
    if not button or button._nexusDarkStyled then return button end
    if not button.GetObjectType or button:GetObjectType() ~= "Button" then return button end
    local text = TextRegion(button)
    if not text then return button end
    button._nexusDarkStyled = true

    pcall(button.SetNormalTexture, button, nil)
    pcall(button.SetPushedTexture, button, nil)
    pcall(button.SetDisabledTexture, button, nil)
    pcall(button.SetHighlightTexture, button, nil)
    pcall(function()
        button:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = compact and 8 or 10,
            insets = { left=2, right=2, top=2, bottom=2 },
        })
        button:SetBackdropColor(0.025, 0.03, 0.04, 0.96)
        button:SetBackdropBorderColor(0.25, 0.29, 0.34, 0.95)
    end)
    pcall(function() text:SetTextColor(0.92, 0.84, 0.62) end)

    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetTexture("Interface\\Buttons\\WHITE8X8")
    hover:SetAllPoints()
    hover:SetVertexColor(0.16, 0.24, 0.29, 0.38)
    button._nexusDarkHover = hover

    button:HookScript("OnMouseDown", function(self)
        pcall(self.SetBackdropColor, self, 0.015, 0.02, 0.025, 1)
    end)
    button:HookScript("OnMouseUp", function(self)
        pcall(self.SetBackdropColor, self, 0.025, 0.03, 0.04, 0.96)
    end)
    button:HookScript("OnEnable", function(self)
        local fs = TextRegion(self)
        if fs then fs:SetTextColor(0.92, 0.84, 0.62) end
        pcall(self.SetBackdropBorderColor, self, 0.25, 0.29, 0.34, 0.95)
    end)
    button:HookScript("OnDisable", function(self)
        local fs = TextRegion(self)
        if fs then fs:SetTextColor(0.48, 0.50, 0.52) end
        pcall(self.SetBackdropBorderColor, self, 0.13, 0.15, 0.18, 0.8)
    end)
    if button.IsEnabled and not button:IsEnabled() then
        text:SetTextColor(0.48, 0.50, 0.52)
    end
    return button
end

function T.StyleWindow(window, alpha)
    if not window or window._nexusWindowStyled then return window end
    window._nexusWindowStyled = true
    pcall(function()
        window:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 32, edgeSize = 12,
            insets = { left=4, right=4, top=4, bottom=4 },
        })
        window:SetBackdropColor(0.16, 0.165, 0.175, alpha or 0.90)
        window:SetBackdropBorderColor(0.20, 0.23, 0.28, 0.95)
    end)
    local shade = window:CreateTexture(nil, "BACKGROUND")
    shade:SetTexture("Interface\\Buttons\\WHITE8X8")
    shade:SetPoint("TOPLEFT", 5, -5)
    shade:SetPoint("BOTTOMRIGHT", -5, 5)
    shade:SetVertexColor(0.10, 0.105, 0.115, 0.05)
    window._nexusWindowShade = shade
    return window
end

function T.StyleTree(root)
    if not root or not root.GetChildren then return end
    local children = { root:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        if child and child.GetObjectType and child:GetObjectType() == "Button" then
            T.StyleButton(child, (child.GetHeight and child:GetHeight() or 24) <= 20)
        end
        T.StyleTree(child)
    end
end
