-- shared/world.lua — world.json read/write helpers
-- Manages the persistent world knowledge base at data/world.json

local world = {}

local DATA_PATH = "data/world.json"

-- Default empty world structure
local function defaultWorld()
    return {
        machines = {},
        items = {},
        known_ores = {},
        known_paths = {},
        failed_attempts = {},
        turtle_roles = {}
    }
end

-- Ensure data directory exists
local function ensureDir()
    if not fs.exists("data") then
        fs.makeDir("data")
    end
end

-- Load world.json from disk; returns table
function world.load()
    ensureDir()
    if not fs.exists(DATA_PATH) then
        local default = defaultWorld()
        world.save(default)
        return default
    end
    local f = fs.open(DATA_PATH, "r")
    if not f then
        return defaultWorld()
    end
    local raw = f.readAll()
    f.close()
    local data = textutils.unserializeJSON(raw)
    if not data then
        return defaultWorld()
    end
    return data
end

-- Save a table to world.json
function world.save(data)
    ensureDir()
    local json = textutils.serializeJSON(data)
    local f = fs.open(DATA_PATH, "w")
    if f then
        f.write(json)
        f.close()
    end
end

-- Get a top-level key from world data
function world.get(key)
    local data = world.load()
    return data[key]
end

-- Set a top-level key and auto-save
function world.set(key, value)
    local data = world.load()
    data[key] = value
    world.save(data)
end

-- Register a machine with coordinates and label
function world.addMachine(name, x, y, z, label)
    local data = world.load()
    data.machines = data.machines or {}
    data.machines[name] = {
        x = x, y = y, z = z,
        label = label or name
    }
    world.save(data)
end

-- Register an item at a location with quantity
function world.addItem(name, location, qty)
    local data = world.load()
    data.items = data.items or {}
    data.items[name] = {
        location = location,
        qty = qty or 0
    }
    world.save(data)
end

-- Update an item quantity by a delta (positive or negative)
function world.updateItem(name, qty_delta)
    local data = world.load()
    data.items = data.items or {}
    if data.items[name] then
        data.items[name].qty = (data.items[name].qty or 0) + qty_delta
        if data.items[name].qty < 0 then
            data.items[name].qty = 0
        end
    end
    world.save(data)
end

-- Record a discovered ore at coordinates
function world.recordOre(name, x, y, z)
    local data = world.load()
    data.known_ores = data.known_ores or {}
    data.known_ores[name] = data.known_ores[name] or {}
    table.insert(data.known_ores[name], { x = x, y = y, z = z })
    world.save(data)
end

-- Record a named path as a sequence of movement steps
function world.recordPath(name, steps_table)
    local data = world.load()
    data.known_paths = data.known_paths or {}
    data.known_paths[name] = steps_table
    world.save(data)
end

return world
