-- Nexus: ui/Changelog.lua
-- One-time, dismissible release note for meaningful user-facing changes.
Nexus = Nexus or {}
local M = {}
Nexus.Changelog = M

local VERSION = "1.19.5"
local RELEASE_KEY = "1.19.5"
local frame
local shownThisSession = false

local function HasSeenRelease()
    if type(NexusDB) ~= "table" then return false end
    if NexusDB.lastChangelogSeen == RELEASE_KEY or NexusDB.lastChangelogSeen == VERSION then return true end
    if type(NexusDB.settings) == "table" and (NexusDB.settings.lastChangelogSeen == RELEASE_KEY or NexusDB.settings.lastChangelogSeen == VERSION) then return true end
    return false
end

local function MarkReleaseSeen()
    NexusDB = NexusDB or {}
    NexusDB.lastChangelogSeen = RELEASE_KEY
    NexusDB.settings = NexusDB.settings or {}
    NexusDB.settings.lastChangelogSeen = RELEASE_KEY
end

local function Create()
    if frame then return frame end
    frame = CreateFrame("Frame", "NexusChangelogPopup", UIParent)
    frame:SetSize(520, 330)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 90)
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -20)
    title:SetText("Nexus 1.19.5")

    local body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", 28, -52)
    body:SetPoint("RIGHT", -28, 0)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetText([[|cffffd200Wishlist editor|r

- Wishlist now opens reliably for active Saved Builds that do not yet have an associated wishlist.
- The Create New Wishlist editor starts clean and automatically targets the active Saved Build.

|cffffd200Sync reliability|r

- Community builds, loadouts, deletions, and DPS records now survive full queues, reconnects, and delayed retries without losing pending work.
- Stricter ownership and packet validation reject malformed or spoofed sync traffic.]])

    local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    close:SetSize(92, 24)
    close:SetPoint("BOTTOM", 0, 14)
    close:SetText("Got it")
    close:SetScript("OnClick", function()
        MarkReleaseSeen()
        frame:Hide()
    end)
    frame:Hide()
    return frame
end

function M.ShowIfNeeded()
    NexusDB = NexusDB or {}
    if not NexusDB.hasSeenQuickStart then
        MarkReleaseSeen()
        return
    end
    if shownThisSession or HasSeenRelease() then return end
    -- Mark it seen when displayed, not only when the button is clicked. This
    -- prevents reloads, disconnects, or another popup covering it from causing
    -- the same release note to appear on every login.
    shownThisSession = true
    MarkReleaseSeen()
    local popup = Create()
    if Nexus.Panel and Nexus.Panel.AttachMenuFrame then Nexus.Panel.AttachMenuFrame(popup) end
    if Nexus.Theme and Nexus.Theme.StyleWindow then Nexus.Theme.StyleWindow(popup, 0.96) end
    if Nexus.Panel and Nexus.Panel.CloseOtherWindows then Nexus.Panel.CloseOtherWindows("NexusChangelogPopup") end
    popup:Show()
end

local ev = CreateFrame("Frame")
local elapsed, armed = 0, false
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function() armed = true; elapsed = 0 end)
ev:SetScript("OnUpdate", function(_, dt)
    if not armed then return end
    elapsed = elapsed + (tonumber(dt) or 0)
    if elapsed >= 2 then
        armed = false
        pcall(M.ShowIfNeeded)
    end
end)
