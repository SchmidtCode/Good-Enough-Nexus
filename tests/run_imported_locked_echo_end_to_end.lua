-- A locked Echo imported from a build must survive the editor's real Save
-- flow and reach the real LockPerk adapter path when automation is enabled.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Relay.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("ui/Readout.lua")
dofile("ui/Panel.lua")
dofile("ui/JournalTab.lua")
dofile("ui/WishlistEditor.lua")
dofile("core/Main.lua")

NexusDB = {}
Nexus.Store.Init()
H.playerLevel = 80
H.DeliverSlots({}, 0)
H.granted = {
    ["Double Strike"] = {
        { spellId = 200104, stack = 1, maxStack = 5, quality = 2 },
    },
}
H.locked = {}

local uploaded
ProjectEbonhold.PerkService.UploadServerBuildSlot = function(slot, name, echoes)
    uploaded = { slot = slot, name = name, echoes = echoes }
    return true
end

local lockCalls = {}
ProjectEbonhold.PerkService.LockPerk = function(spellId)
    lockCalls[#lockCalls + 1] = spellId
    H.locked[#H.locked + 1] = {
        spellId = spellId, stack = 1, maxStack = 1, quality = 3,
    }
    return true
end
ProjectEbonhold.PerkService.UnlockPerk = function() return true end

local editor = Nexus.WishlistEditor
editor.Init(Nexus.GameAdapter, Nexus.Model)
editor.OpenForCandidate({
    title = "Imported locked build",
    echoes = {
        { spellId = 200100, quality = 3, stacks = 1, locked = true },
        { spellId = 200104, quality = 2, stacks = 1 },
    },
})

local draft = editor.DebugDraftState()
assert(draft.pending == 2 and draft.pendingLock == 0,
    "import did not retain the normal and actively pursued locked Echoes")

local editorFrame = _G.NexusEditorFrame
assert(editorFrame and editorFrame._applyBtn,
    "editor Save control is unavailable to the end-to-end test")
editorFrame._applyBtn:GetScript("OnClick")(editorFrame._applyBtn)
assert(H.lastStaticPopup
    and H.lastStaticPopup.which == "WISHLISTREALIZER_CREATE_WISHLIST",
    "imported build Save did not ask for confirmation")
H.AcceptLastStaticPopup()

assert(uploaded and #uploaded.echoes == 1
    and uploaded.echoes[1].spellId == 200104,
    "Save did not upload the normal wishlist independently of locked slots")
local wishlistKey = Nexus.GameAdapter.WishlistKey(uploaded.echoes)
local committed = Nexus.Store.State().lockDesignTargetsBySlot[wishlistKey]
assert(committed and committed[200100] ~= nil,
    "Save discarded the imported locked Echo design")

-- Model the server's readback of the newly created designed wishlist.
H.DeliverSlots({
    [6] = { slot = 6, name = uploaded.name, verified = false,
        echoes = uploaded.echoes },
}, 6)

-- The player obtains the designed Echo after importing the build.
H.granted["Alpha Strike"] = {
    { spellId = 200100, stack = 1, maxStack = 1, quality = 3 },
}

H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("PLAYER_ENTERING_WORLD")
NexusDB.settings.autoLockEchoes = true
SlashCmdList.NEXUS("auto")
assert(Nexus.RefreshPanel(), "main automation step did not run")
assert(#lockCalls == 1 and lockCalls[1] == 200100,
    "saved imported lock design did not call LockPerk for its owned Echo\n"
        .. tostring(Nexus.GetDiagnosticPageText("autolock")))

print("imported locked Echo survives Save and reaches LockPerk -- OK")
