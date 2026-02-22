-- brain/startup.lua — Brain main loop
-- Orchestrates the turtle agent network from an advanced computer

local config  = require("shared/config")
local mon     = require("shared/monitor")
local net     = require("shared/net")
local world   = require("shared/world")
local queue   = require("shared/queue")
local ai      = require("shared/ai")

-- Track which turtles are busy with which tasks
local turtle_tasks = {}  -- { [turtle_id] = { goal = "...", status = "active" } }
local available_turtles = {}  -- list of turtle IDs that are idle

-- Register a turtle as available for work
local function registerTurtle(id)
    for _, tid in ipairs(available_turtles) do
        if tid == id then return end
    end
    table.insert(available_turtles, id)
end

-- Get an available turtle and remove it from the idle pool
local function claimTurtle()
    if #available_turtles == 0 then return nil end
    return table.remove(available_turtles, 1)
end

-- Release a turtle back to the available pool
local function releaseTurtle(id)
    turtle_tasks[id] = nil
    registerTurtle(id)
end

-- Ask AI to decompose a command into sub-tasks for turtles
local function decomposeTask(command)
    local world_data = world.load()
    local system = "You are the brain of a CC:Tweaked turtle network in FTB StoneBlock 4. "
        .. "Break the player command into 1-3 concrete sub-tasks for turtles. "
        .. "Each sub-task should be a clear, single goal a turtle can execute. "
        .. "Respond with ONLY a JSON array of strings, e.g. "
        .. '[\"mine 10 blocks forward\", \"return to chest and deposit items\"]'

    local context = "Command: " .. command .. "\n"
    if world_data.machines then
        local names = {}
        for name, _ in pairs(world_data.machines) do
            table.insert(names, name)
        end
        if #names > 0 then
            context = context .. "Known machines: " .. table.concat(names, ", ") .. "\n"
        end
    end
    context = context .. "Available turtles: " .. #available_turtles

    local response, err = ai.ask(system, context)
    if not response then
        return { command }  -- Fallback: treat entire command as one task
    end

    local tasks = textutils.unserializeJSON(response)
    if not tasks or type(tasks) ~= "table" then
        return { command }
    end
    return tasks
end

-- Assign a task to a turtle via rednet
local function assignTask(turtle_id, goal, max_steps)
    max_steps = max_steps or 50
    turtle_tasks[turtle_id] = { goal = goal, status = "active" }
    rednet.send(turtle_id, textutils.serializeJSON({
        type = "task_assign",
        goal = goal,
        max_steps = max_steps
    }), "turtle_agent")
    mon.log("Assigned to turtle #" .. turtle_id .. ": " .. goal, "lime")
end

-- Handle an incoming message from a turtle
local function handleTurtleMessage(sender_id, msg)
    if msg.type == "register" then
        registerTurtle(sender_id)
        mon.log("Turtle #" .. sender_id .. " registered", "cyan")
        local w = world.load()
        w.turtle_roles = w.turtle_roles or {}
        if msg.role then
            w.turtle_roles[tostring(sender_id)] = msg.role
        end
        world.save(w)

    elseif msg.type == "task_complete" then
        mon.log("Turtle #" .. sender_id .. " completed: "
            .. tostring(msg.summary), "lime")
        releaseTurtle(sender_id)

    elseif msg.type == "task_failed" then
        mon.log("Turtle #" .. sender_id .. " FAILED: "
            .. tostring(msg.reason), "red")
        -- Record the failure
        local w = world.load()
        w.failed_attempts = w.failed_attempts or {}
        table.insert(w.failed_attempts, {
            turtle = sender_id,
            task = turtle_tasks[sender_id] and turtle_tasks[sender_id].goal,
            reason = msg.reason
        })
        world.save(w)
        releaseTurtle(sender_id)

    elseif msg.type == "report" then
        mon.log("Turtle #" .. sender_id .. ": " .. tostring(msg.message), "white")

    elseif msg.type == "fuel_request" then
        mon.log("Turtle #" .. sender_id .. " needs fuel (level: "
            .. tostring(msg.fuel_level) .. ")", "yellow")

    elseif msg.type == "discovery" then
        -- Turtle found something new — update world
        if msg.machine then
            world.addMachine(msg.machine.name, msg.machine.x,
                msg.machine.y, msg.machine.z, msg.machine.label)
            mon.log("Discovered machine: " .. msg.machine.name, "lime")
        end
        if msg.ore then
            world.recordOre(msg.ore.name, msg.ore.x, msg.ore.y, msg.ore.z)
            mon.log("Discovered ore: " .. msg.ore.name, "lime")
        end
    end
end

-- Read player input from the terminal (non-blocking via parallel)
local function readPlayerInput()
    while true do
        term.setCursorPos(1, 1)
        term.clearLine()
        write("> ")
        local input = read()
        if input and #input > 0 then
            queue.push(input)
            mon.log("Queued: " .. input, "cyan")
            print("Command queued. (" .. queue.size() .. " in queue)")
        end
    end
end

-- Main brain processing loop
local function brainLoop()
    while true do
        -- Check for queued commands
        local cmd = queue.pop()
        if cmd then
            mon.setTask("Processing: " .. cmd)
            mon.log("Processing command: " .. cmd, "yellow")

            -- Use AI to decompose into sub-tasks
            local sub_tasks = decomposeTask(cmd)
            mon.log("Decomposed into " .. #sub_tasks .. " sub-tasks", "yellow")

            -- Assign each sub-task to an available turtle
            for _, task in ipairs(sub_tasks) do
                local tid = claimTurtle()
                if tid then
                    assignTask(tid, task)
                else
                    -- No turtle available: re-queue the task
                    queue.push(task)
                    mon.log("No turtle available, re-queued: " .. task, "orange")
                end
            end
        end

        -- Listen for turtle messages
        local sender, msg = net.receive(1)
        if sender and msg then
            handleTurtleMessage(sender, msg)
        end

        -- Update status line
        local active_count = 0
        for _ in pairs(turtle_tasks) do active_count = active_count + 1 end
        mon.setStatus("Turtles: " .. #available_turtles .. " idle, "
            .. active_count .. " active | Queue: " .. queue.size())

        os.sleep(0.5)
    end
end

-- ========== STARTUP ==========

print("=== CC:Tweaked AI Brain ===")
print("Computer ID: " .. os.getComputerID())

-- Initialize systems
mon.init()
net.open()
world.load()  -- Ensure data/world.json exists

mon.clear()
mon.setStatus("Brain starting up...")
mon.log("Brain online — ID #" .. os.getComputerID(), "lime")
mon.log("Model: " .. config.model, "white")
mon.log("Waiting for turtles to register...", "yellow")
mon.log("Type commands below to queue tasks.", "cyan")

-- Run input reader and brain loop in parallel
parallel.waitForAll(readPlayerInput, brainLoop)
