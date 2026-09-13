-- Full integration: posting a build through the real CommunityBuilds UI
-- actually broadcasts via Sync, and CHAT_MSG_CHANNEL events get routed
-- to Sync.HandleIncoming only when they're really our sync channel (not
-- some unrelated channel a player happens to be in).
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")
dofile("core/Sync.lua")
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
Nexus.LogViewer = { Init = function() end }
dofile("ui/CommunityBuilds.lua")
local chatFilters = {}
ChatFrame_AddMessageEventFilter = function(event, callback)
    chatFilters[event] = chatFilters[event] or {}
    chatFilters[event][#chatFilters[event] + 1] = callback
end
dofile("core/Main.lua")

NexusDB = {}
H.wishlist = { name = "MyBuild", class = "MAGE", echoes = {
    { spellId = 200100, quality = 3, stacks = 1 },
} }
H.playerLevel = 5
UnitName = function() return "Alice" end

H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("SPELLS_CHANGED")
H.FireEvent("PLAYER_ENTERING_WORLD")
H.Advance(2)

assert(Nexus.Sync.IsConnected(), "sync channel should be connected after PLAYER_ENTERING_WORLD")
print("sync channel connects automatically on login -- OK")

local directWire = "WLD2|Alice|direct-filter|1/1|QQ=="
local escapedDirectWire = directWire:gsub("|", "||")
local incomingFilter = chatFilters.CHAT_MSG_WHISPER
    and chatFilters.CHAT_MSG_WHISPER[1]
local outgoingFilter = chatFilters.CHAT_MSG_WHISPER_INFORM
    and chatFilters.CHAT_MSG_WHISPER_INFORM[1]
assert(incomingFilter and outgoingFilter,
    "direct bulk filters were not installed for both whisper directions")
assert(incomingFilter(nil, "CHAT_MSG_WHISPER", escapedDirectWire, "Alice"),
    "incoming escaped Nexus bulk whisper remained visible")
assert(outgoingFilter(nil, "CHAT_MSG_WHISPER_INFORM",
    escapedDirectWire, "Testreceiver"),
    "outgoing Nexus bulk whisper remained visible")
assert(not incomingFilter(nil, "CHAT_MSG_WHISPER", "hello", "Alice"),
    "ordinary incoming whisper was hidden")
assert(not outgoingFilter(nil, "CHAT_MSG_WHISPER_INFORM", "hello", "Testreceiver"),
    "ordinary outgoing whisper was hidden")
print("direct bulk whispers are hidden without filtering ordinary chat -- OK")

Nexus.Sync._diagnostic={peer="Testreceiver",id="lab-1-1",pipeFree=true}
local labWire=Nexus.Sync._EncodeLabBulk(directWire)
assert(outgoingFilter(nil,"CHAT_MSG_WHISPER_INFORM",labWire,"Testreceiver"),
    "outgoing CW2 lab envelope remained visible")
local peerWire=Nexus.Sync._EncodeLabBulk("WLD2|Testreceiver|record|1/1|QQ==")
assert(incomingFilter(nil,"CHAT_MSG_WHISPER",peerWire,"Testreceiver"))
assert(not outgoingFilter(nil,"CHAT_MSG_WHISPER_INFORM",peerWire,"Testreceiver"),
    "outgoing filter accepted another claimed sender")
assert(not outgoingFilter(nil,"CHAT_MSG_WHISPER_INFORM","WLTB:hello","Testreceiver"))
Nexus.Sync._diagnostic=nil
assert(not outgoingFilter(nil,"CHAT_MSG_WHISPER_INFORM",labWire,"Testreceiver"),
    "unarmed lab-like chat was hidden")

-- Post through the real UI-facing function
local CB = Nexus.CommunityBuilds
local ok, id = CB.PostCurrentWishlist("My Shared Build", "Check this out", H.wishlist)
assert(ok, "posting should succeed")
H.Advance(3)  -- let the send queue pump
assert(#H.sentChatMessages >= 1, "posting did not actually broadcast anything")
print("posting a wishlist through the real UI genuinely broadcasts it -- OK")

-- Simulate CHAT_MSG_CHANNEL from an UNRELATED channel -- must be ignored
local before = Nexus.Sync.Stats().received
local sentMsg = H.sentChatMessages[1].text
H.FireEvent("CHAT_MSG_CHANNEL", sentMsg, "Alice", "Common", "general")
assert(Nexus.Sync.Stats().received == before,
    "a message from an unrelated channel must NOT be processed as sync data")
print("messages from unrelated channels are correctly ignored -- OK")

-- Now simulate it arriving on the REAL sync channel (as another client
-- receiving Alice's broadcast) -- must be processed
NexusDB.communityBuilds = nil  -- pretend this is Bob's fresh client
-- Receiving is opt-in: Bob must request a sync first.
Nexus.Sync.RequestSync()
for _, msg in ipairs(H.sentChatMessages) do
    H.FireEvent("CHAT_MSG_CHANNEL", msg.text, "Alice", "Common", Nexus.Sync.ChannelName())
end
assert(NexusDB.communityBuilds and NexusDB.communityBuilds[id],
    "a message on the real sync channel should have been processed and stored")
assert(NexusDB.communityBuilds[id].title == "My Shared Build")
print("messages on the real sync channel are correctly processed end-to-end -- OK")
