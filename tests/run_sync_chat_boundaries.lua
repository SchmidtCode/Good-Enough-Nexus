local H = dofile('tests/harness.lua')
dofile('core/Codec.lua')
dofile('core/Sync.lua')
local S = Nexus.Sync

-- Reproduces the native trigger at the old fixed-size boundary, including
-- repeated n bytes. Reassembly must retain every byte, not replace/remove n.
local data = string.rep('A', 24) .. 'nnn' .. string.rep('B', 70)
assert(data:sub(25,25) == 'n', 'fixture must fail old fixed-size chunking')
local chunks = assert(S._SplitChatData(data, 24, 999))
assert(table.concat(chunks) == data)
for _, body in ipairs(chunks) do
    assert(#body > 0 and #body <= 24)
    assert(body:sub(1,1) ~= 'n', 'native invalid-escape trigger remains')
end
for budget=24,60 do
    for offset=1,120 do
        local input = string.rep('A',offset) .. 'nnnn' .. string.rep('Z',140)
        local parts = assert(S._SplitChatData(input,budget,999))
        assert(table.concat(parts) == input)
        for _, part in ipairs(parts) do
            assert(#part <= budget and part:sub(1,1) ~= 'n')
        end
    end
end
assert(not S._SplitChatData('nAAA',24,999), 'unsafe initial byte silently altered')
assert(not S._SplitChatData('A'..string.rep('n',50),24,999))
assert(not S._SplitChatData(string.rep('A',100),24,2), 'chunk cap exceeded')
assert(table.concat(assert(S._SplitChatData('e30=',24,999))) == 'e30=')
print('chat chunk boundaries: native n trigger, exact bytes, runs, limits: OK')
