-- Build-detail Echo icons must identify themselves on hover. Covers both the
-- locked baseline row and the complete loadout grid through the visible UI.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")

local tooltip = { lines = {}, links = {} }
function tooltip:SetOwner(owner, anchor)
    self.owner, self.anchor = owner, anchor
end
function tooltip:SetHyperlink(link)
    self.links[#self.links + 1] = link
end
function tooltip:AddLine(text)
    self.lines[#self.lines + 1] = text
end
function tooltip:Show() self.shown = true end
function tooltip:Hide() self.shown = false end
GameTooltip = tooltip

dofile("ui/CommunityBuilds.lua")

NexusDB = {}
UnitName = function() return "Boganic" end
H.wishlist = { name = "Preview Tooltips", class = "MAGE", echoes = {
    { spellId = 200100, quality = 3, stacks = 1, locked = true },
    { spellId = 200104, quality = 2, stacks = 3 },
} }

local CB = Nexus.CommunityBuilds
CB.Init(Nexus.GameAdapter, Nexus.Model)
local ok, id = CB.PostCurrentWishlist(
    "Preview Tooltips", "Tooltip coverage", H.wishlist)
assert(ok and id, "failed to create preview build")
-- Community posting intentionally treats an active wishlist as unlocked.
-- Mark the stored preview as a saved-build-style locked loadout.
NexusDB.communityBuilds[id].echoes[1].locked = true

CB.Show()
CB.Select(id)

local browser = _G.NexusCommunityBuildsFrame
local detail = browser and browser._detailPanel
assert(detail, "selected build did not expose its visible detail panel")
assert(detail.lockedIconHits and detail.lockedIconHits[1]
    and detail.lockedIconHits[1]:IsShown(),
    "locked Echo preview has no visible hover target")
assert(detail.echoIconHits and detail.echoIconHits[2]
    and detail.echoIconHits[2]:IsShown(),
    "normal Echo preview has no visible hover target")

detail.lockedIconHits[1]:GetScript("OnEnter")(detail.lockedIconHits[1])
assert(tooltip.links[#tooltip.links] == "spell:200100",
    "locked Echo hover did not open its spell tooltip")

detail.echoIconHits[2]:GetScript("OnEnter")(detail.echoIconHits[2])
assert(tooltip.links[#tooltip.links] == "spell:200104",
    "normal Echo hover did not open its spell tooltip")

local context = table.concat(tooltip.lines, "\n")
assert(context:find("Rare", 1, true) and context:find("3 stacks", 1, true),
    "normal Echo tooltip did not include quality and stack context")

print("build preview locked and normal Echo tooltips -- OK")
