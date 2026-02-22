-- shared/monitor.lua — Monitor display with color and scrolling log
-- Drives an attached advanced monitor for brain status display

local mon = {}

local monitor = nil   -- peripheral handle
local lines = {}      -- scrolling log buffer
local maxLines = 1    -- calculated from monitor height
local statusText = "" -- persistent top line
local taskText = ""   -- persistent second line

-- Color map for convenience
local colorMap = {
    red    = colors.red,
    yellow = colors.yellow,
    lime   = colors.lime,
    orange = colors.orange,
    cyan   = colors.cyan,
    white  = colors.white,
    green  = colors.green,
}

-- Find and initialize the monitor peripheral; set text scale 0.5
function mon.init()
    monitor = peripheral.find("monitor")
    if not monitor then
        print("[monitor] No monitor found — output to terminal only")
        return false
    end
    monitor.setTextScale(0.5)
    monitor.clear()
    local _, h = monitor.getSize()
    -- Reserve 2 lines for status + task, rest for scrolling log
    maxLines = h - 2
    if maxLines < 1 then maxLines = 1 end
    lines = {}
    return true
end

-- Redraw the entire monitor from buffer
local function redraw()
    if not monitor then return end
    monitor.clear()

    -- Line 1: status
    monitor.setCursorPos(1, 1)
    monitor.setTextColor(colors.cyan)
    monitor.write(statusText)

    -- Line 2: current task
    monitor.setCursorPos(1, 2)
    monitor.setTextColor(colors.orange)
    monitor.write(taskText)

    -- Lines 3+: scrolling log
    for i, entry in ipairs(lines) do
        monitor.setCursorPos(1, i + 2)
        monitor.setTextColor(entry.color or colors.white)
        monitor.write(entry.text or "")
    end
end

-- Append a line to the scrolling log; scroll if full
function mon.log(text, color)
    local c = colorMap[color] or colors.white
    -- Also print to terminal for debugging
    print(text)

    if not monitor then return end

    table.insert(lines, { text = text, color = c })
    -- Trim to max visible lines
    while #lines > maxLines do
        table.remove(lines, 1)
    end
    redraw()
end

-- Set the persistent status line (top line, always visible)
function mon.setStatus(text)
    statusText = "[STATUS] " .. (text or "")
    print(statusText)
    redraw()
end

-- Set the persistent task line (second line)
function mon.setTask(text)
    taskText = "[TASK] " .. (text or "")
    print(taskText)
    redraw()
end

-- Clear the monitor and all buffers
function mon.clear()
    lines = {}
    statusText = ""
    taskText = ""
    if monitor then
        monitor.clear()
    end
end

return mon
