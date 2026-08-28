-- Nexus: ui/Changelog.lua
-- One-time, dismissible release note for meaningful user-facing changes.
Nexus = Nexus or {}
local M = {}
Nexus.Changelog = M

local VERSION = "1.96.2"
local RELEASE_KEY = "1.96.2"
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
    frame:SetSize(520, 360)
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
    title:SetText("Nexus 1.96.2 Community Update")

    local body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", 28, -52)
    body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 52)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetText([[|cffffd200Core HUD fixes|r

- Fixes the compact HUD opening blank at level 80 with no active Echo board.
- Refreshes Still Needed and Missing Tomes after Echo or tome learning changes.

|cffffd200HUD layout|r

- Uses a 340-pixel-wide HUD with more vertical room and readable columns.
- Keeps unchanged learning checks from rebuilding or repainting the HUD.

|cffffd200Official handoff|r

- Ignores interim 1.96.x peer versions in the official update notice.
- Still points users to Visceral's official Better-Nexus 1.20 release when seen.

|cffffd200Support scope|r

- This unofficial package has no routine hotpatch schedule.
- Maintenance is limited to problems that block core addon functionality.]])

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
local armed = false
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function()
    armed = true
    local scheduler = assert(Nexus.Scheduler, "Scheduler required")
    scheduler.Init()
    scheduler.After("ui.changelog.show", 2, function()
        if not armed then return end
        armed = false
        pcall(M.ShowIfNeeded)
    end)
end)
