-- shared/monitor.lua — Monitor display with color and scrolling log
-- Drives an attached advanced monitor for brain status display
-- Shows AI thinking, code output, and learning progress

local mon = {}

local monitor = nil   -- peripheral handle
local lines = {}      -- scrolling log buffer
local maxLines = 1    -- calculated from monitor height
local statusText = "" -- persistent top line
local taskText = ""   -- persistent second line
local monWidth = 40   -- monitor width in characters

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
        print("[monitor] No monitor found - output to terminal only")
        return false
    end
    monitor.setTextScale(0.5)
    monitor.clear()
    monWidth = monitor.getSize()
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

-- Word-wrap long text into multiple lines for the monitor
local function wrapText(text, width)
    if #text <= width then return { text } end
    local wrapped = {}
    local remaining = text
    while #remaining > 0 do
        if #remaining <= width then
            table.insert(wrapped, remaining)
            break
        end
        -- Find a good break point
        local cut = width
        local space = remaining:sub(1, width):find("%s[^%s]*$")
        if space and space > width * 0.4 then
            cut = space
        end
        table.insert(wrapped, remaining:sub(1, cut))
        remaining = remaining:sub(cut + 1)
    end
    return wrapped
end

-- Append a line to the scrolling log; scroll if full
-- Long lines are word-wrapped to fit the monitor
function mon.log(text, color)
    local c = colorMap[color] or colors.white
    -- Also print to terminal for debugging
    print(text)

    if not monitor then return end

    -- Word-wrap long lines
    local wrapped = wrapText(text, monWidth)
    for _, line in ipairs(wrapped) do
        table.insert(lines, { text = line, color = c })
    end
    -- Trim to max visible lines
    while #lines > maxLines do
        table.remove(lines, 1)
    end
    redraw()
end

-- Set the persistent status line (top line, always visible)
function mon.setStatus(text)
    statusText = "[STATUS] " .. (text or "")
    redraw()
end

-- Set the persistent task line (second line)
function mon.setTask(text)
    taskText = "[TASK] " .. (text or "")
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
