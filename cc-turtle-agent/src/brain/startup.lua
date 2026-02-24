-- brain/startup.lua — Self-Coding AI Brain
-- Standalone AI agent that can write code, learn, and improve itself
-- Works without any turtles — just this computer + monitor
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
            -- Backup names use __ as path separator
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

-- If last boot crashed during module loading, recover
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

-- Set crash flag BEFORE loading modules
-- (cleared after successful load)
if not fs.exists("data") then fs.makeDir("data") end
local cf = fs.open(CRASH_FLAG, "w")
if cf then cf.write("1") cf.close() end

-- ======================================================
-- MODULE LOADING (wrapped in pcall for safety)
-- ======================================================

local config, mon, world_mod, queue, coder

local load_ok, load_err = pcall(function()
    config = require("shared/config")
    mon    = require("shared/monitor")
    world_mod = require("shared/world")
    queue  = require("shared/queue")
    coder  = require("shared/coder")
end)

-- Clear crash flag — modules loaded successfully
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
-- MAIN APPLICATION (modules are loaded and working)
-- ======================================================

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

-- Main brain loop: pull tasks from queue and run the coder
local function brainLoop()
    while true do
        local cmd = queue.pop()
        if cmd then
            mon.setStatus("AI Brain - Working...")
            mon.setTask(cmd)
            mon.log("", "white")
            mon.log("=== New Task: " .. cmd .. " ===", "cyan")

            -- Wrap coder.run in pcall so a runtime crash
            -- doesn't kill the whole brain
            local run_ok, ok, result = pcall(
                coder.run, cmd, onCoderEvent, 30)

            if not run_ok then
                -- coder.run itself crashed
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

        os.sleep(0.5)
    end
end

-- ========== STARTUP ==========

print("=== CC:Tweaked AI Brain ===")
print("Self-Coding AI Agent (with crash recovery)")
print("Computer ID: " .. os.getComputerID())
print()
print("Commands:")
print("  Type anything  - give the AI a task")
print("  clear          - clear the monitor")
print("  knowledge      - show what AI has learned")
print("  history        - show completed tasks")
print("  recovery       - restore from backups")
print("  help           - show all commands")
print()

-- Initialize systems
mon.init()
world_mod.load()

mon.clear()
mon.setStatus("AI Brain - Ready")
mon.log("Brain online - ID #" .. os.getComputerID(), "lime")
mon.log("Model: " .. config.model, "white")
mon.log("Safety: syntax check + auto-backup + recovery", "green")
mon.log("", "white")
mon.log("This AI can write code, learn, and improve itself.", "yellow")
mon.log("Type a task in the terminal to get started.", "cyan")
mon.log("Examples:", "white")
mon.log("  write a program that displays the time", "white")
mon.log("  create a file manager program", "white")
mon.log("  improve yourself to handle errors better", "white")

-- Run input reader and brain loop in parallel
parallel.waitForAll(readPlayerInput, brainLoop)
