-- brain/startup.lua — Self-Coding AI Brain
-- Standalone AI agent that can write code, learn, and improve itself
-- Also supports discovering and communicating with turtles via rednet
--
-- SAFETY: This file has crash detection at the top (no requires).
-- If a module is broken, it auto-restores from backups on reboot.
-- If this file itself is broken, run "recovery" from the shell.

-- ======================================================
-- CRASH DETECTION & RECOVERY (runs before any requires)
-- This section uses ONLY built-in Lua/CC APIs, no modules.
-- ======================================================

local CRASH_FLAG = "data/.crash_flag"

local function attemptRecovery()
    if not fs.exists("data/backups") then
        print("No backups found.")
        print("Run 'recovery' or re-run the installer.")
        return false
    end
    local backups = fs.list("data/backups")
    if #backups == 0 then
        print("Backup directory is empty.")
        print("Run 'recovery' or re-run the installer.")
        return false
    end
    print("Restoring " .. #backups .. " file(s) from backup...")
    for _, name in ipairs(backups) do
        local backup_path = fs.combine("data/backups", name)
        if not fs.isDir(backup_path) then
            local original = name:gsub("__", "/")
            local dir = fs.getDir(original)
            if dir and dir ~= "" and not fs.exists(dir) then
                fs.makeDir(dir)
            end
            if fs.exists(original) then fs.delete(original) end
            fs.copy(backup_path, original)
            print("  Restored: " .. original)
        end
    end
    return true
end

if fs.exists(CRASH_FLAG) then
    fs.delete(CRASH_FLAG)
    print()
    print("=== CRASH DETECTED ===")
    print("The AI broke something last run.")
    print("Auto-recovering from backups...")
    print()
    if attemptRecovery() then
        print()
        print("Recovery complete! Rebooting in 3s...")
        os.sleep(3)
        os.reboot()
        return
    else
        print()
        print("Auto-recovery failed.")
        print("Type 'recovery' for manual recovery options.")
        return
    end
end

if not fs.exists("data") then fs.makeDir("data") end
local cf = fs.open(CRASH_FLAG, "w")
if cf then cf.write("1") cf.close() end

-- ======================================================
-- MODULE LOADING (wrapped in pcall for safety)
-- ======================================================

local config, mon, world_mod, queue, coder, net

local load_ok, load_err = pcall(function()
    config    = require("shared/config")
    mon       = require("shared/monitor")
    world_mod = require("shared/world")
    queue     = require("shared/queue")
    coder     = require("shared/coder")
    net       = require("shared/net")
end)

if fs.exists(CRASH_FLAG) then fs.delete(CRASH_FLAG) end

if not load_ok then
    print()
    print("=== MODULE LOAD ERROR ===")
    print(tostring(load_err))
    print()
    print("Attempting auto-recovery from backups...")
    if attemptRecovery() then
        print()
        print("Recovery complete! Rebooting in 3s...")
        os.sleep(3)
        os.reboot()
    else
        print()
        print("No backups available.")
        print("Type 'recovery' for manual recovery options.")
    end
    return
end

-- ======================================================
-- TURTLE TRACKING
-- ======================================================

local known_turtles = {}  -- { [id] = { role, fuel, last_seen } }
local modem_open = false

-- Try to open rednet modem
local function openModem()
    local ok = net.open()
    modem_open = ok
    return ok
end

-- Handle incoming turtle messages
local function handleTurtleMessage(sender_id, msg)
    if not msg or not msg.type then return end

    if msg.type == "register" then
        known_turtles[sender_id] = {
            role = msg.role or "unknown",
            fuel = msg.fuel or 0,
            last_seen = os.clock()
        }
        mon.log("Turtle #" .. sender_id .. " connected ("
            .. (msg.role or "unknown") .. ", fuel: "
            .. (msg.fuel or "?") .. ")", "lime")
        -- Save to world
        local w = world_mod.load()
        w.turtle_roles = w.turtle_roles or {}
        w.turtle_roles[tostring(sender_id)] = msg.role
        world_mod.save(w)

    elseif msg.type == "task_complete" then
        mon.log("Turtle #" .. sender_id .. " completed: "
            .. tostring(msg.summary), "lime")
        if known_turtles[sender_id] then
            known_turtles[sender_id].last_seen = os.clock()
        end

    elseif msg.type == "task_failed" then
        mon.log("Turtle #" .. sender_id .. " FAILED: "
            .. tostring(msg.reason), "red")

    elseif msg.type == "report" then
        mon.log("Turtle #" .. sender_id .. ": "
            .. tostring(msg.message), "white")
        if known_turtles[sender_id] then
            known_turtles[sender_id].last_seen = os.clock()
        end

    elseif msg.type == "discovery" then
        if msg.machine then
            world_mod.addMachine(msg.machine.name,
                msg.machine.x, msg.machine.y,
                msg.machine.z, msg.machine.label)
            mon.log("Discovered: " .. msg.machine.name, "lime")
        end
    end
end

-- Scan for turtles by broadcasting a ping
local function scanForTurtles()
    if not modem_open then
        print("No modem found. Attach a wireless modem.")
        mon.log("Scan failed: no modem", "red")
        return
    end
    mon.log("Scanning for turtles...", "yellow")
    print("Broadcasting scan ping...")
    net.broadcast({ type = "ping" })
    -- Listen for responses for 3 seconds
    local found = 0
    local deadline = os.clock() + 3
    while os.clock() < deadline do
        local sender, msg = net.receive(
            deadline - os.clock())
        if sender and msg then
            handleTurtleMessage(sender, msg)
            found = found + 1
        end
    end
    if found == 0 then
        print("No turtles responded.")
        print("Make sure the turtle is running and has")
        print("a wireless modem + the turtle agent code.")
        mon.log("No turtles found", "yellow")
    else
        print("Found " .. found .. " turtle(s).")
    end
end

-- Get turtle status summary for the AI
local function getTurtleStatus()
    local count = 0
    local info = {}
    for id, t in pairs(known_turtles) do
        count = count + 1
        table.insert(info, "#" .. id .. " ("
            .. t.role .. ", fuel:" .. t.fuel .. ")")
    end
    if count == 0 then
        return "No turtles connected"
    end
    return count .. " turtle(s): " .. table.concat(info, ", ")
end

-- ======================================================
-- MAIN APPLICATION
-- ======================================================

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

            elseif input == "scan" then
                scanForTurtles()

            elseif input == "turtles" then
                print(getTurtleStatus())

            elseif input == "knowledge" then
                local w = world_mod.load()
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
                local w = world_mod.load()
                if w.completed_tasks
                    and #w.completed_tasks > 0 then
                    print("=== Completed Tasks ===")
                    for _, t in ipairs(w.completed_tasks) do
                        print("  " .. t.goal .. " ("
                            .. t.steps .. " steps)")
                    end
                else
                    print("No completed tasks yet.")
                end

            elseif input == "recovery" then
                shell.run("recovery")

            elseif input == "help" then
                print("=== Commands ===")
                print("  <any text>  - Give the AI a task")
                print("  scan        - Scan for turtles")
                print("  turtles     - Show connected turtles")
                print("  clear       - Clear the monitor")
                print("  knowledge   - Show what AI has learned")
                print("  history     - Show completed tasks")
                print("  recovery    - Restore from backups")
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

local function brainLoop()
    while true do
        -- Process command queue
        local cmd = queue.pop()
        if cmd then
            mon.setStatus("AI Brain - Working...")
            mon.setTask(cmd)
            mon.log("", "white")
            mon.log("=== New Task: " .. cmd .. " ===", "cyan")

            local run_ok, ok, result = pcall(
                coder.run, cmd, onCoderEvent, 30,
                { turtle_status = getTurtleStatus(),
                  known_turtles = known_turtles })

            if not run_ok then
                mon.log("=== CODER CRASHED: "
                    .. tostring(ok) .. " ===", "red")
                mon.log("The AI may have broken a module."
                    .. " Continuing...", "yellow")
            elseif ok then
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

        -- Listen for turtle messages (non-blocking)
        if modem_open then
            local sender, msg = net.receive(0.5)
            if sender and msg then
                handleTurtleMessage(sender, msg)
            end
        else
            os.sleep(0.5)
        end
    end
end

-- ========== STARTUP ==========

print("=== CC:Tweaked AI Brain ===")
print("Self-Coding AI Agent (with crash recovery)")
print("Computer ID: " .. os.getComputerID())
print()
print("Commands:")
print("  Type anything  - give the AI a task")
print("  scan           - scan for turtles (rednet)")
print("  turtles        - show connected turtles")
print("  clear / knowledge / history / recovery / help")
print()

mon.init()
world_mod.load()
openModem()

mon.clear()
mon.setStatus("AI Brain - Ready")
mon.log("Brain online - ID #" .. os.getComputerID(), "lime")
mon.log("Model: " .. config.model, "white")
mon.log("Safety: syntax check + auto-backup + recovery", "green")
if modem_open then
    mon.log("Modem: open (type 'scan' to find turtles)", "cyan")
else
    mon.log("Modem: not found (attach one to find turtles)", "yellow")
end
mon.log("", "white")
mon.log("Type a task or 'help' to get started.", "cyan")

parallel.waitForAll(readPlayerInput, brainLoop)
