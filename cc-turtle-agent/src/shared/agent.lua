-- shared/agent.lua — ReAct loop (Observe -> Reason -> Act -> Report)
-- Core agent logic used by both brain and turtles

local ai = require("shared/ai")
local search = require("shared/search")
local world = require("shared/world")
local net = require("shared/net")

local agent = {}

-- Gather current observations from the turtle API
local function observe(turtle_api)
    local obs = {}

    -- Fuel level
    obs.fuel = turtle_api.getFuelLevel()

    -- Inventory summary: list non-empty slots
    local inv = {}
    for slot = 1, 16 do
        local detail = turtle_api.getItemDetail(slot)
        if detail then
            table.insert(inv, "slot" .. slot .. ": " .. detail.name
                .. " x" .. detail.count)
        end
    end
    obs.inventory = #inv > 0 and table.concat(inv, ", ") or "empty"

    -- Block inspection
    local ok, front = turtle_api.inspect()
    obs.front_block = ok and front.name or "air"

    local ok2, above = turtle_api.inspectUp()
    obs.above_block = ok2 and above.name or "air"

    local ok3, below = turtle_api.inspectDown()
    obs.below_block = ok3 and below.name or "air"

    -- Selected slot
    obs.selected_slot = turtle_api.getSelectedSlot()

    return obs
end

-- Execute a single action returned by the AI
-- Returns success boolean and result description string
local function executeAction(action, params, turtle_api)
    params = params or {}

    -- Movement actions
    if action == "forward" then
        local ok, err = turtle_api.forward()
        return ok, ok and "moved forward" or ("forward failed: " .. tostring(err))

    elseif action == "back" then
        local ok, err = turtle_api.back()
        return ok, ok and "moved back" or ("back failed: " .. tostring(err))

    elseif action == "up" then
        local ok, err = turtle_api.up()
        return ok, ok and "moved up" or ("up failed: " .. tostring(err))

    elseif action == "down" then
        local ok, err = turtle_api.down()
        return ok, ok and "moved down" or ("down failed: " .. tostring(err))

    elseif action == "turnLeft" then
        turtle_api.turnLeft()
        return true, "turned left"

    elseif action == "turnRight" then
        turtle_api.turnRight()
        return true, "turned right"

    -- Digging actions
    elseif action == "dig" then
        local ok, err = turtle_api.dig()
        return ok, ok and "dug forward" or ("dig failed: " .. tostring(err))

    elseif action == "digUp" then
        local ok, err = turtle_api.digUp()
        return ok, ok and "dug up" or ("digUp failed: " .. tostring(err))

    elseif action == "digDown" then
        local ok, err = turtle_api.digDown()
        return ok, ok and "dug down" or ("digDown failed: " .. tostring(err))

    -- Placing actions
    elseif action == "place" then
        if params.slot then turtle_api.select(params.slot) end
        local ok, err = turtle_api.place()
        return ok, ok and "placed block" or ("place failed: " .. tostring(err))

    elseif action == "placeUp" then
        if params.slot then turtle_api.select(params.slot) end
        local ok, err = turtle_api.placeUp()
        return ok, ok and "placed up" or ("placeUp failed: " .. tostring(err))

    elseif action == "placeDown" then
        if params.slot then turtle_api.select(params.slot) end
        local ok, err = turtle_api.placeDown()
        return ok, ok and "placed down" or ("placeDown failed: " .. tostring(err))

    -- Inspection actions
    elseif action == "inspect" then
        local ok, data = turtle_api.inspect()
        if ok then
            return true, "inspected: " .. tostring(data.name)
        end
        return false, "nothing to inspect"

    elseif action == "inspectUp" then
        local ok, data = turtle_api.inspectUp()
        if ok then
            return true, "inspected up: " .. tostring(data.name)
        end
        return false, "nothing above"

    elseif action == "inspectDown" then
        local ok, data = turtle_api.inspectDown()
        if ok then
            return true, "inspected down: " .. tostring(data.name)
        end
        return false, "nothing below"

    -- Item actions
    elseif action == "suck" then
        local count = params.count or 64
        local ok, err = turtle_api.suck(count)
        return ok, ok and "picked up items" or ("suck failed: " .. tostring(err))

    elseif action == "suckUp" then
        local ok, err = turtle_api.suckUp(params.count or 64)
        return ok, ok and "picked up from above" or ("suckUp failed: " .. tostring(err))

    elseif action == "suckDown" then
        local ok, err = turtle_api.suckDown(params.count or 64)
        return ok, ok and "picked up from below" or ("suckDown failed: " .. tostring(err))

    elseif action == "drop" then
        if params.slot then turtle_api.select(params.slot) end
        local ok, err = turtle_api.drop()
        return ok, ok and "dropped items" or ("drop failed: " .. tostring(err))

    elseif action == "dropUp" then
        if params.slot then turtle_api.select(params.slot) end
        local ok, err = turtle_api.dropUp()
        return ok, ok and "dropped up" or ("dropUp failed: " .. tostring(err))

    elseif action == "dropDown" then
        if params.slot then turtle_api.select(params.slot) end
        local ok, err = turtle_api.dropDown()
        return ok, ok and "dropped down" or ("dropDown failed: " .. tostring(err))

    -- Crafting
    elseif action == "craft" then
        local ok, err = turtle_api.craft()
        return ok, ok and "crafted successfully" or ("craft failed: " .. tostring(err))

    -- Slot selection
    elseif action == "select" then
        local slot = params.slot or 1
        turtle_api.select(slot)
        return true, "selected slot " .. slot

    -- Refueling
    elseif action == "refuel" then
        local ok, err = turtle_api.refuel()
        return ok, ok and "refueled" or ("refuel failed: " .. tostring(err))

    -- Web search
    elseif action == "search_web" then
        local query = params.query or "minecraft help"
        local answer, snippets, err = search.query(query)
        if answer then
            return true, "search result: " .. answer:sub(1, 200)
        end
        return false, "search failed: " .. tostring(err)

    -- Communication with brain
    elseif action == "report_to_brain" then
        local message = params.message or "status update"
        net.sendToBrain({
            type = "report",
            turtle_id = os.getComputerID(),
            message = message
        })
        return true, "reported to brain: " .. message

    elseif action == "request_fuel" then
        net.sendToBrain({
            type = "fuel_request",
            turtle_id = os.getComputerID(),
            fuel_level = turtle_api.getFuelLevel()
        })
        return true, "requested fuel from brain"

    -- Terminal actions
    elseif action == "task_complete" then
        return true, "TASK_COMPLETE: " .. tostring(params.summary or "done")

    elseif action == "task_failed" then
        return false, "TASK_FAILED: " .. tostring(params.reason or "unknown")

    else
        return false, "unknown action: " .. tostring(action)
    end
end

-- Write a step log entry to data/logs/
local function logStep(goal, step, data)
    if not fs.exists("data/logs") then
        fs.makeDir("data/logs")
    end
    -- Simple hash of goal for filename
    local hash = 0
    for i = 1, #goal do
        hash = (hash * 31 + string.byte(goal, i)) % 100000
    end
    local path = "data/logs/goal_" .. hash .. ".log"
    local f = fs.open(path, "a")
    if f then
        f.writeLine("Step " .. step .. ": " .. textutils.serializeJSON(data))
        f.close()
    end
end

-- Run the full ReAct agent loop
-- goal: string describing what to accomplish
-- turtle_api: the turtle API table (real turtle or mock)
-- max_steps: maximum iterations before stopping
function agent.run(goal, turtle_api, max_steps)
    max_steps = max_steps or 50
    local history = {}
    local world_data = world.load()

    print("[agent] Starting goal: " .. goal)

    for step = 1, max_steps do
        print("[agent] Step " .. step .. "/" .. max_steps)

        -- 1. Observe
        local observations = observe(turtle_api)

        -- 2. Reason
        local decision, err = ai.reason(goal, observations, world_data, history)
        if not decision then
            print("[agent] Reasoning failed: " .. tostring(err))
            table.insert(history, {
                action = "reason_failed", result = tostring(err)
            })
            os.sleep(2)
            goto continue
        end

        print("[agent] Thought: " .. tostring(decision.thought))
        print("[agent] Action: " .. tostring(decision.action))

        -- 3. Act
        local ok, result = pcall(executeAction, decision.action,
            decision.params, turtle_api)
        if not ok then
            result = "pcall error: " .. tostring(result)
            ok = false
        end

        print("[agent] Result: " .. tostring(result))

        -- Record in history
        table.insert(history, {
            action = decision.action,
            params = decision.params,
            thought = decision.thought,
            result = tostring(result),
            success = ok
        })

        -- Log to file
        logStep(goal, step, history[#history])

        -- 4. Check for terminal actions
        if decision.action == "task_complete" then
            print("[agent] Task completed: " .. tostring(decision.params
                and decision.params.summary or ""))
            return true, decision.params and decision.params.summary or "done"
        end

        if decision.action == "task_failed" then
            print("[agent] Task failed: " .. tostring(decision.params
                and decision.params.reason or ""))
            return false, decision.params and decision.params.reason or "failed"
        end

        -- Yield to prevent "too long without yielding" errors
        os.sleep(0.1)

        ::continue::
    end

    print("[agent] Reached max steps (" .. max_steps .. ")")
    return false, "max steps reached"
end

return agent
