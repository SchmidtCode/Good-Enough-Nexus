-- Nexus: ui/BrowserSession.lua
-- Projection, selection, and fixed-height viewport state shared by data browsers.

Nexus = Nexus or {}
local BrowserSession = {}
Nexus.BrowserSession = BrowserSession

function BrowserSession.New(options)
    options = options or {}
    assert(type(options.project) == "function", "browser projection required")
    local keyOf = type(options.keyOf) == "function" and options.keyOf
        or function(row) return row and row.id end
    local session = {
        rows={}, summary=nil, selectedKey=nil, query=nil,
        rowHeight=tonumber(options.rowHeight) or 1,
        overscan=tonumber(options.overscan) or 0,
        viewportHeight=1, offset=0,
        stats={refreshes=0,failures=0,windows=0,selectionRepairs=0},
    }

    local function FindSelected()
        if session.selectedKey == nil then return nil end
        for _, row in ipairs(session.rows) do
            if keyOf(row) == session.selectedKey then return row end
        end
    end

    function session.Refresh(query)
        local ok, rows, summary, err = pcall(options.project, query)
        session.stats.refreshes = session.stats.refreshes + 1
        if not ok or type(rows) ~= "table" then
            session.stats.failures = session.stats.failures + 1
            return false, tostring(ok and err or rows or "browser projection failed")
        end
        session.query, session.rows, session.summary = query, rows, summary
        if session.selectedKey ~= nil and not FindSelected() then
            session.selectedKey = nil
            session.stats.selectionRepairs = session.stats.selectionRepairs + 1
        end
        return true, rows, summary
    end

    function session.Rows()
        return session.rows
    end

    function session.Summary()
        return session.summary
    end

    function session.Select(rowOrKey)
        session.selectedKey = type(rowOrKey) == "table" and keyOf(rowOrKey)
            or rowOrKey
        return FindSelected()
    end

    function session.SelectedKey()
        return session.selectedKey
    end

    function session.SelectedRow()
        return FindSelected()
    end

    function session.SetViewport(viewportHeight, offset, rowHeight, overscan)
        session.viewportHeight = tonumber(viewportHeight) or session.viewportHeight
        session.offset = tonumber(offset) or session.offset
        session.rowHeight = tonumber(rowHeight) or session.rowHeight
        session.overscan = tonumber(overscan) or session.overscan
        return session.Window()
    end

    function session.Window()
        local virtual = assert(Nexus.VirtualList, "VirtualList required").Window(
            #session.rows, session.rowHeight, session.viewportHeight,
            session.offset, session.overscan)
        session.offset = virtual.offset
        session.stats.windows = session.stats.windows + 1
        return virtual
    end

    function session.VisibleRows()
        local window, rows = session.Window(), {}
        for index = window.first, window.last do
            rows[#rows + 1] = {index=index, row=session.rows[index]}
        end
        return rows, window
    end

    function session.Stats()
        local out = {}
        for key, value in pairs(session.stats) do out[key] = value end
        out.results, out.selectedKey = #session.rows, session.selectedKey
        return out
    end

    return session
end
