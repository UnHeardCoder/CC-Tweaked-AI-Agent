-- brain/startup.lua — Self-Coding AI Brain
-- Standalone AI agent that can write code, learn, and improve itself
-- Works without any turtles — just this computer + monitor

local config = require("shared/config")
local mon    = require("shared/monitor")
local world  = require("shared/world")
local queue  = require("shared/queue")
local coder  = require("shared/coder")

-- Display callback: routes coder events to monitor
local function onCoderEvent(dtype, text, color)
    if dtype == "task" then
        mon.setTask(text)
    elseif dtype == "think" then
        mon.log("[THINK] " .. text, "yellow")
    elseif dtype == "action" then
        mon.log("[ACT] " .. text, "lime")
    elseif dtype == "code" then
        mon.log("[CODE] " .. text, "cyan")
    elseif dtype == "result" then
        mon.log("[OUT] " .. text, "white")
    elseif dtype == "error" then
        mon.log("[ERR] " .. text, "red")
    elseif dtype == "complete" then
        mon.log("[DONE] " .. text, "lime")
    elseif dtype == "failed" then
        mon.log("[FAIL] " .. text, "red")
    elseif dtype == "step" then
        mon.setStatus("AI Brain - " .. text)
    else
        mon.log(text, color or "white")
    end
end

-- Read player input from the terminal
local function readPlayerInput()
    while true do
        term.setCursorPos(1, 1)
        term.clearLine()
        write("> ")
        local input = read()
        if input and #input > 0 then
            if input == "clear" then
                mon.clear()
                mon.setStatus("AI Brain - Ready")
                print("Monitor cleared.")

            elseif input == "knowledge" then
                local w = world.load()
                if w.knowledge and next(w.knowledge) then
                    print("=== Stored Knowledge ===")
                    for topic, info in pairs(w.knowledge) do
                        print("  " .. topic .. ": "
                            .. tostring(info):sub(1, 60))
                    end
                else
                    print("No knowledge stored yet.")
                end

            elseif input == "history" then
                local w = world.load()
                if w.completed_tasks and #w.completed_tasks > 0 then
                    print("=== Completed Tasks ===")
                    for _, t in ipairs(w.completed_tasks) do
                        print("  " .. t.goal .. " ("
                            .. t.steps .. " steps)")
                    end
                else
                    print("No completed tasks yet.")
                end

            elseif input == "help" then
                print("=== Commands ===")
                print("  <any text>  - Give the AI a task")
                print("  clear       - Clear the monitor")
                print("  knowledge   - Show what AI has learned")
                print("  history     - Show completed tasks")
                print("  help        - Show this help")

            else
                queue.push(input)
                mon.log("Queued: " .. input, "cyan")
                print("Task queued. ("
                    .. queue.size() .. " in queue)")
            end
        end
    end
end

-- Main brain loop: pull tasks from queue and run the coder
local function brainLoop()
    while true do
        local cmd = queue.pop()
        if cmd then
            mon.setStatus("AI Brain - Working...")
            mon.setTask(cmd)
            mon.log("", "white")
            mon.log("=== New Task: " .. cmd .. " ===", "cyan")

            local ok, result = coder.run(cmd, onCoderEvent, 30)

            if ok then
                mon.log("=== Completed: "
                    .. tostring(result) .. " ===", "lime")
            else
                mon.log("=== Failed: "
                    .. tostring(result) .. " ===", "red")
            end

            mon.setTask("")

            if queue.size() > 0 then
                mon.setStatus("AI Brain - "
                    .. queue.size() .. " tasks remaining")
            else
                mon.setStatus("AI Brain - Ready")
            end
        end

        os.sleep(0.5)
    end
end

-- ========== STARTUP ==========

print("=== CC:Tweaked AI Brain ===")
print("Self-Coding AI Agent")
print("Computer ID: " .. os.getComputerID())
print()
print("Commands:")
print("  Type anything  - give the AI a task")
print("  clear          - clear the monitor")
print("  knowledge      - show what AI has learned")
print("  history        - show completed tasks")
print("  help           - show all commands")
print()

-- Initialize systems
mon.init()
world.load()

mon.clear()
mon.setStatus("AI Brain - Ready")
mon.log("Brain online - ID #" .. os.getComputerID(), "lime")
mon.log("Model: " .. config.model, "white")
mon.log("", "white")
mon.log("This AI can write code, learn, and improve itself.", "yellow")
mon.log("Type a task in the terminal to get started.", "cyan")
mon.log("Examples:", "white")
mon.log("  write a program that displays the time", "white")
mon.log("  create a file manager program", "white")
mon.log("  improve yourself to handle errors better", "white")
mon.log("  search the web for CC:Tweaked monitor API", "white")

-- Run input reader and brain loop in parallel
parallel.waitForAll(readPlayerInput, brainLoop)
