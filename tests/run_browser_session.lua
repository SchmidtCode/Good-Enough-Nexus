local H = dofile("tests/harness.lua")
local source = {
    {id="a",value=1}, {id="b",value=2}, {id="c",value=3}, {id="d",value=4},
}
local reads = 0
local session = Nexus.BrowserSession.New({
    rowHeight=10, overscan=1,
    project=function(query)
        reads = reads + 1
        local rows = {}
        for _, row in ipairs(source) do
            if not query or row.value >= query.minimum then rows[#rows + 1] = row end
        end
        return rows, {matched=#rows}
    end,
})

assert(session.Refresh({minimum=1}) and reads == 1)
session.Select("c")
local window = session.SetViewport(20, 10)
assert(window.first == 1 and window.last == 4 and session.SelectedRow().id == "c",
    "projection, selection, and virtual window were not joined")

source = {{id="a",value=1}}
assert(session.Refresh({minimum=1}) and session.SelectedKey() == nil,
    "stale selection survived a projection change")
assert(session.Stats().selectionRepairs == 1 and session.Summary().matched == 1,
    "browser session diagnostics were not updated")

print("browser projection, selection repair, and virtual window state -- OK")
