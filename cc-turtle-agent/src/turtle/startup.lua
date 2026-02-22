-- turtle/startup.lua — Turtle agent main loop
-- Each turtle runs this: registers with brain, receives tasks, runs agent loop

local config = require("shared/config")
local agent  = require("shared/agent")
local net    = require("shared/net")
local world  = require("shared/world")

-- Get or set this turtle's role
local function getRole()
    local role = settings.get("agent.role_name")
    if not role then
        role = "general"
        settings.set("agent.role_name", role)
        settings.save()
    end
    return role
end

-- Register this turtle with the brain
local function registerWithBrain()
    local role = getRole()
    net.sendToBrain({
        type = "register",
        turtle_id = os.getComputerID(),
        role = role,
        fuel = turtle.getFuelLevel()
    })
    print("[turtle] Registered with brain as '" .. role .. "'")
end

-- Auto-refuel from inventory if fuel is low
local function autoRefuel(threshold)
    threshold = threshold or 100
    if turtle.getFuelLevel() == "unlimited" then return end
    if turtle.getFuelLevel() >= threshold then return end

    print("[turtle] Low fuel (" .. turtle.getFuelLevel() .. "), attempting refuel...")
    for slot = 1, 16 do
        turtle.select(slot)
        local ok = turtle.refuel(1)
        if ok then
            print("[turtle] Refueled from slot " .. slot
                .. ", now at " .. turtle.getFuelLevel())
            if turtle.getFuelLevel() >= threshold then
                turtle.select(1)
                return true
            end
        end
    end
    turtle.select(1)

    -- Still low? Request fuel from brain
    if turtle.getFuelLevel() < threshold then
        net.sendToBrain({
            type = "fuel_request",
            turtle_id = os.getComputerID(),
            fuel_level = turtle.getFuelLevel()
        })
        print("[turtle] Requested fuel from brain")
    end
    return false
end

-- Inspect surroundings and report discoveries to brain
local function scanSurroundings()
    local discoveries = {}

    local dirs = {
        { fn = turtle.inspect,     label = "front" },
        { fn = turtle.inspectUp,   label = "up" },
        { fn = turtle.inspectDown, label = "down" },
    }

    for _, dir in ipairs(dirs) do
        local ok, data = dir.fn()
        if ok and data and data.name then
            local name = data.name
            -- Check if it looks like an ore
            if name:find("ore") then
                table.insert(discoveries, {
                    type = "ore",
                    name = name,
                    direction = dir.label
                })
            end
            -- Check if it looks like a machine/container
            if name:find("chest") or name:find("furnace")
                or name:find("hopper") or name:find("barrel")
                or name:find("crate") or name:find("drawer") then
                table.insert(discoveries, {
                    type = "machine",
                    name = name,
                    direction = dir.label
                })
            end
        end
    end

    -- Report any discoveries to brain
    for _, disc in ipairs(discoveries) do
        net.sendToBrain({
            type = "discovery",
            turtle_id = os.getComputerID(),
            [disc.type] = {
                name = disc.name,
                label = disc.name,
                x = 0, y = 0, z = 0  -- GPS would fill these in
            }
        })
    end

    return discoveries
end

-- Handle a task assignment from the brain
local function handleTask(msg)
    local goal = msg.goal or "unknown task"
    local max_steps = msg.max_steps or 50

    print("[turtle] === NEW TASK ===")
    print("[turtle] Goal: " .. goal)
    print("[turtle] Max steps: " .. max_steps)

    -- Run the agent ReAct loop
    local success, summary = agent.run(goal, turtle, max_steps)

    -- Report result back to brain
    if success then
        net.sendToBrain({
            type = "task_complete",
            turtle_id = os.getComputerID(),
            goal = goal,
            summary = summary
        })
        print("[turtle] Task completed: " .. tostring(summary))
    else
        net.sendToBrain({
            type = "task_failed",
            turtle_id = os.getComputerID(),
            goal = goal,
            reason = summary
        })
        print("[turtle] Task failed: " .. tostring(summary))
    end
end

-- ========== STARTUP ==========

local role = getRole()
print("=== CC:Tweaked AI Turtle ===")
print("Computer ID: " .. os.getComputerID())
print("Role: " .. role)

-- Initialize
net.open()

-- Register with brain
registerWithBrain()

-- Main loop
print("[turtle] Listening for tasks...")
while true do
    -- Try to receive a task from the brain
    local sender, msg = net.receive(5)

    if msg and msg.type == "task_assign" then
        -- Got a task — execute it
        handleTask(msg)
        -- Re-register as available after completing
        registerWithBrain()

    else
        -- No task received — idle behavior
        autoRefuel(200)

        -- Occasionally scan surroundings for discoveries
        if math.random(1, 3) == 1 then
            local found = scanSurroundings()
            if #found > 0 then
                print("[turtle] Reported " .. #found .. " discoveries")
            end
        end
    end

    os.sleep(0.5)
end
