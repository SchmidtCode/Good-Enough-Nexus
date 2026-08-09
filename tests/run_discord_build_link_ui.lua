local f = assert(io.open("ui/CommunityBuilds.lua", "r"))
local s = f:read("*a"); f:close()
assert(s:find('DISCORD BUILD LINK', 1, true), 'Discord field label missing')
assert(s:find('linkSaveBtn', 1, true), 'owner link-save button missing')
assert(s:find('M.EditBuild%(%s*selectedId, build.title, build.description, link%)'),
    'link not saved atomically through EditBuild')
assert(s:find('link:match("^https://discord%.com/channels/(%d+)/(%d+)/(%d+)/?$")', 1, true) and s:find('link:match("^https://discord%.com/channels/(%d+)/(%d+)/?$")', 1, true), 'Discord channel-link validator missing')
assert(s:find('https://discord.com/channels/%s/%s', 1, true), 'Discord channel-link normalization missing')
print('discord build link UI tests passed')
