-- shared/queue.lua — File-backed FIFO command queue
-- Stores pending commands at data/queue.json

local queue = {}

local QUEUE_PATH = "data/queue.json"

-- Ensure data directory exists
local function ensureDir()
    if not fs.exists("data") then
        fs.makeDir("data")
    end
end

-- Load queue from disk
local function loadQueue()
    ensureDir()
    if not fs.exists(QUEUE_PATH) then
        return {}
    end
    local f = fs.open(QUEUE_PATH, "r")
    if not f then
        return {}
    end
    local raw = f.readAll()
    f.close()
    local data = textutils.unserializeJSON(raw)
    return data or {}
end

-- Save queue to disk
local function saveQueue(data)
    ensureDir()
    local json = textutils.serializeJSON(data)
    local f = fs.open(QUEUE_PATH, "w")
    if f then
        f.write(json)
        f.close()
    end
end

-- Push a command string to the back of the queue
function queue.push(command_string)
    local data = loadQueue()
    table.insert(data, command_string)
    saveQueue(data)
end

-- Pop and return the front item from the queue
function queue.pop()
    local data = loadQueue()
    if #data == 0 then
        return nil
    end
    local item = table.remove(data, 1)
    saveQueue(data)
    return item
end

-- Peek at the front item without removing it
function queue.peek()
    local data = loadQueue()
    return data[1]
end

-- Return the number of items in the queue
function queue.size()
    local data = loadQueue()
    return #data
end

-- Return the full queue as a table
function queue.list()
    return loadQueue()
end

-- Clear all items from the queue
function queue.clear()
    saveQueue({})
end

return queue
