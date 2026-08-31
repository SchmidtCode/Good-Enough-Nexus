local H = dofile("tests/harness.lua")

local journal = CreateFrame("Frame", "ProjectEbonholdEchoJournal", UIParent)
journal:SetSize(800, 600)
journal:Show()
CreateFrame("ScrollFrame", "ProjectEbonholdEchoJournalScroll", journal)
local tab = CreateFrame("Button", "ProjectEbonholdEchoJournalTab1", journal)
tab:SetFrameLevel(2)

Nexus.GameAdapter = {
    Slots = function()
        return {
            activeSlot = 1,
            maxSlots = 5,
            bySlot = {
                [1] = { name = "Orb build", echoes = { { spellId = 200100 } } },
            },
        }
    end,
    GetWishlistCandidates = function()
        return {
            { slot = 101, key = "wish", name = "Orb target",
              echoes = { { spellId = 200100 } } },
        }
    end,
    GetLoadoutWishlist = function()
        return { slot = 101, key = "wish", name = "Orb target",
            echoes = { { spellId = 200100 } } }
    end,
}

dofile("ui/JournalTab.lua")
assert(Nexus.JournalTab.TryInstall(function() return { sections = {} } end),
    "journal guidance fixture did not install")
Nexus.JournalTab.RefreshAssociations()

local panel = assert(_G.NexusLoadoutAssociationPanel,
    "Nexus HUD target control was not created")
assert(panel.label:GetText() == "Nexus HUD target",
    "journal control is not visibly identified as Nexus-owned")
assert(panel.help:GetText():find("Progress", 1, true)
    and panel.help:GetText():find("To Shed", 1, true),
    "journal control does not explain which HUD values it drives")
assert(panel.selector.loadoutName == "Orb build",
    "HUD target control lost the active Ebonhold loadout context")

print("Echo Journal identifies the Nexus HUD target and its calculations -- OK")
