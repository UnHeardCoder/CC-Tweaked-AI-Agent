-- shared/coder.lua — Self-coding AI agent loop
-- Observe files -> Reason -> Write/Edit code -> Learn
-- Works on the brain computer without any turtles
--
-- SAFETY: All .lua writes are syntax-checked before saving.
-- System files are backed up before modification.
-- If the AI breaks something, backups auto-restore on reboot.

local ai = require("shared/ai")
local search = require("shared/search")
local world = require("shared/world")

local coder = {}

-- Files the AI must never read/write (contain secrets)
local PROTECTED_FILES = {
    ["shared/config.lua"] = true,
    ["config.lua"] = true,
    ["recovery.lua"] = true,
}

-- System files that get backed up before any modification
local SYSTEM_FILES = {
    ["startup.lua"] = true,
    ["shared/coder.lua"] = true,
    ["shared/ai.lua"] = true,
    ["shared/monitor.lua"] = true,
    ["shared/world.lua"] = true,
    ["shared/queue.lua"] = true,
    ["shared/search.lua"] = true,
    ["shared/net.lua"] = true,
    ["shared/agent.lua"] = true,
    ["update.lua"] = true,
}

-- Normalize a path: remove leading slashes
local function normPath(path)
    if not path then return "" end
    return path:gsub("^/+", "")
end

-- Check if a path is protected (no access at all)
local function isProtected(path)
    return PROTECTED_FILES[normPath(path)] == true
end

-- Check if a path is a system file (needs backup before edit)
local function isSystemFile(path)
    return SYSTEM_FILES[normPath(path)] == true
end

-- Create a backup of a file before modifying it
local function backupFile(path)
    path = normPath(path)
    if not fs.exists(path) then return end
    if not fs.exists("data/backups") then
        fs.makeDir("data/backups")
    end
    -- Use __ as path separator in backup name
    local backup_name = path:gsub("/", "__")
    local backup_path = fs.combine("data/backups", backup_name)
    if fs.exists(backup_path) then fs.delete(backup_path) end
    fs.copy(path, backup_path)
end

-- Restore a file from its backup
local function restoreFile(path)
    path = normPath(path)
    local backup_name = path:gsub("/", "__")
    local backup_path = fs.combine("data/backups", backup_name)
    if not fs.exists(backup_path) then return false end
    if fs.exists(path) then fs.delete(path) end
    fs.copy(backup_path, path)
    return true
end

-- Validate Lua syntax by trying to compile it
-- Returns true if valid, or false + error message
local function validateLua(content)
    local func, err = load(content, "validate")
    if func then return true end
    return false, err
end

-- Gather current state of the computer
local function observe()
    local obs = {}

    -- List files on the computer (excluding rom/ and protected files)
    local function listDir(dir, prefix)
        local items = {}
        if not fs.exists(dir) then return items end
        for _, name in ipairs(fs.list(dir)) do
            local path = fs.combine(dir, name)
            local display_path = prefix .. name
            if fs.isDir(path) then
                if name ~= "rom" and name ~= ".git"
                    and name ~= "data" then
                    for _, sub in ipairs(
                        listDir(path, prefix .. name .. "/")) do
                        table.insert(items, sub)
                    end
                end
            elseif not isProtected(display_path) then
                table.insert(items, display_path)
            end
        end
        return items
    end

    local files = listDir("/", "")
    obs.files = table.concat(files, ", ")
    obs.free_space = fs.getFreeSpace("/")
    obs.computer_id = os.getComputerID()
    obs.time = textutils.formatTime(os.time(), true)

    return obs
end

-- Execute a single coding action returned by the AI
local function executeAction(action, params)
    params = params or {}

    if action == "read_file" then
        local path = params.path
        if not path then return false, "no path specified" end
        if isProtected(path) then
            return false, path .. " is protected"
        end
        if not fs.exists(path) then
            return false, "file not found: " .. path
        end
        if fs.isDir(path) then
            return false, "path is a directory"
        end
        local f = fs.open(path, "r")
        if not f then return false, "cannot open: " .. path end
        local content = f.readAll()
        f.close()
        if #content > 2000 then
            content = content:sub(1, 2000)
                .. "\n... (truncated, " .. #content
                .. " chars total)"
        end
        return true, "FILE " .. path .. ":\n" .. content

    elseif action == "write_file" then
        local path = params.path
        local content = params.content
        if not path then return false, "no path specified" end
        if isProtected(path) then
            return false, path .. " is protected"
        end
        if not content then
            return false, "no content specified"
        end

        -- SAFETY: validate Lua syntax before writing .lua files
        if path:match("%.lua$") then
            local valid, syn_err = validateLua(content)
            if not valid then
                return false, "SYNTAX ERROR — code rejected, "
                    .. "file NOT written: " .. tostring(syn_err)
            end
        end

        -- Backup system files before overwriting
        if isSystemFile(path) then
            backupFile(path)
        end

        local dir = fs.getDir(path)
        if dir and dir ~= "" and not fs.exists(dir) then
            fs.makeDir(dir)
        end
        local f = fs.open(path, "w")
        if not f then return false, "cannot write: " .. path end
        f.write(content)
        f.close()
        return true, "wrote " .. #content .. " chars to " .. path

    elseif action == "edit_file" then
        local path = params.path
        local find_str = params.find
        local replace_str = params.replace or ""
        if not path or not find_str then
            return false, "need path and find params"
        end
        if isProtected(path) then
            return false, path .. " is protected"
        end
        if not fs.exists(path) then
            return false, "file not found: " .. path
        end
        local f = fs.open(path, "r")
        if not f then return false, "cannot read: " .. path end
        local content = f.readAll()
        f.close()

        -- Plain string find (no pattern matching)
        local start_idx, end_idx = content:find(find_str, 1, true)
        if not start_idx then
            return false, "text not found in file"
        end
        local new_content = content:sub(1, start_idx - 1)
            .. replace_str .. content:sub(end_idx + 1)

        -- SAFETY: validate Lua syntax before writing .lua files
        if path:match("%.lua$") then
            local valid, syn_err = validateLua(new_content)
            if not valid then
                return false, "SYNTAX ERROR — edit rejected, "
                    .. "file NOT changed: " .. tostring(syn_err)
            end
        end

        -- Backup system files before overwriting
        if isSystemFile(path) then
            backupFile(path)
        end

        f = fs.open(path, "w")
        if not f then return false, "cannot write: " .. path end
        f.write(new_content)
        f.close()
        return true, "edited " .. path

    elseif action == "list_files" then
        local dir = params.path or "/"
        if not fs.exists(dir) then
            return false, "directory not found"
        end
        if not fs.isDir(dir) then
            return false, "not a directory"
        end
        local items = {}
        for _, name in ipairs(fs.list(dir)) do
            local full = fs.combine(dir, name)
            if fs.isDir(full) then
                table.insert(items, name .. "/")
            else
                table.insert(items, name
                    .. " (" .. fs.getSize(full) .. "b)")
            end
        end
        return true, "files in " .. dir .. ": "
            .. table.concat(items, ", ")

    elseif action == "delete_file" then
        local path = params.path
        if not path then return false, "no path specified" end
        if not fs.exists(path) then
            return false, "not found: " .. path
        end
        if isProtected(path) or path == "startup.lua" then
            return false, "cannot delete critical system file"
        end
        fs.delete(path)
        return true, "deleted " .. path

    elseif action == "run_code" then
        local code = params.code
        if not code then return false, "no code to run" end
        -- Capture printed output
        local output = {}
        local env = setmetatable({
            print = function(...)
                local parts = {}
                for i = 1, select("#", ...) do
                    parts[i] = tostring(select(i, ...))
                end
                local line = table.concat(parts, "\t")
                table.insert(output, line)
                print(line)
            end
        }, { __index = _G })
        local func, err = load(code, "ai_code", "t", env)
        if not func then
            return false, "syntax error: " .. tostring(err)
        end
        local ok, result = pcall(func)
        local out_str = table.concat(output, "\n")
        if ok then
            local msg = "code executed"
            if #out_str > 0 then
                msg = msg .. "\nOutput:\n" .. out_str
            end
            if result ~= nil then
                msg = msg .. "\nReturned: " .. tostring(result)
            end
            return true, msg
        else
            local msg = "runtime error: " .. tostring(result)
            if #out_str > 0 then
                msg = msg .. "\nOutput before error:\n" .. out_str
            end
            return false, msg
        end

    elseif action == "run_file" then
        local path = params.path
        if not path then return false, "no path specified" end
        if not fs.exists(path) then
            return false, "file not found: " .. path
        end
        local ok, err = pcall(shell.run, path)
        if ok then
            return true, "ran " .. path .. " successfully"
        else
            return false, "error running " .. path
                .. ": " .. tostring(err)
        end

    elseif action == "search_web" then
        local query = params.query or "CC:Tweaked Lua help"
        local answer, snippets, err = search.query(query)
        if answer then
            local result = "SEARCH: " .. answer:sub(1, 500)
            if snippets and #snippets > 0 then
                for _, s in ipairs(snippets) do
                    result = result .. "\n- " .. s.title
                        .. ": " .. s.content:sub(1, 150)
                end
            end
            return true, result
        end
        return false, "search failed: " .. tostring(err)

    elseif action == "learn" then
        local topic = params.topic or "general"
        local info = params.info
        if not info then return false, "no info to learn" end
        local w = world.load()
        w.knowledge = w.knowledge or {}
        w.knowledge[topic] = info
        world.save(w)
        return true, "learned about: " .. topic

    elseif action == "recall" then
        local topic = params.topic
        local w = world.load()
        w.knowledge = w.knowledge or {}
        if topic then
            local info = w.knowledge[topic]
            if info then
                return true, "knowledge[" .. topic
                    .. "]: " .. tostring(info)
            end
            return false, "no knowledge about: " .. topic
        else
            local topics = {}
            for k, _ in pairs(w.knowledge) do
                table.insert(topics, k)
            end
            if #topics > 0 then
                return true, "known topics: "
                    .. table.concat(topics, ", ")
            end
            return true, "no knowledge stored yet"
        end

    elseif action == "task_complete" then
        return true, "TASK_COMPLETE: "
            .. tostring(params.summary or "done")

    elseif action == "task_failed" then
        return false, "TASK_FAILED: "
            .. tostring(params.reason or "unknown")

    else
        return false, "unknown action: " .. tostring(action)
    end
end

-- Log a step to data/logs/
local function logStep(goal, step, data)
    if not fs.exists("data/logs") then fs.makeDir("data/logs") end
    local hash = 0
    for i = 1, #goal do
        hash = (hash * 31 + string.byte(goal, i)) % 100000
    end
    local path = "data/logs/code_" .. hash .. ".log"
    local f = fs.open(path, "a")
    if f then
        f.writeLine("Step " .. step .. ": "
            .. textutils.serializeJSON(data))
        f.close()
    end
end

-- Run the self-coding agent loop
-- goal: what the user wants done
-- display: function(type, text, color) for monitor output
-- max_steps: max reasoning iterations
function coder.run(goal, display, max_steps)
    max_steps = max_steps or 30
    local history = {}
    local world_data = world.load()

    display = display or function() end

    display("task", goal, "cyan")

    local repeat_count = 0
    local last_action_key = ""

    for step = 1, max_steps do
        display("step", "Step " .. step .. "/" .. max_steps, "white")

        -- 1. Observe
        local observations = observe()

        -- 2. Reason
        local decision, err = ai.codeReason(
            goal, observations, world_data, history)
        if not decision then
            display("error", "Reasoning failed: "
                .. tostring(err), "red")
            table.insert(history, {
                action = "reason_failed",
                result = tostring(err)
            })
            os.sleep(2)
            goto continue
        end

        -- Loop detection: same action+path 3 times = warning
        local action_key = decision.action .. ":"
            .. tostring(decision.params
                and decision.params.path or "")
        if action_key == last_action_key then
            repeat_count = repeat_count + 1
        else
            repeat_count = 1
            last_action_key = action_key
        end
        if repeat_count >= 3 then
            display("error", "Loop detected — same action "
                .. repeat_count .. "x. Forcing new approach.", "red")
            table.insert(history, {
                action = "SYSTEM_WARNING",
                result = "You are stuck in a loop repeating '"
                    .. decision.action .. "'. Try a completely "
                    .. "different approach or use task_complete/"
                    .. "task_failed to finish.",
                success = false
            })
            -- After 5 repeats, force-fail the task
            if repeat_count >= 5 then
                display("failed",
                    "Force-stopped: stuck in loop", "red")
                return false, "force-stopped: stuck in loop"
            end
        end

        display("think", decision.thought, "yellow")
        local action_label = decision.action
        if decision.params then
            if decision.params.path then
                action_label = action_label
                    .. ": " .. decision.params.path
            elseif decision.params.topic then
                action_label = action_label
                    .. ": " .. decision.params.topic
            end
        end
        display("action", action_label, "lime")

        -- 3. Act
        local pcall_ok, ok, result = pcall(executeAction,
            decision.action, decision.params)
        if not pcall_ok then
            -- pcall itself failed (executeAction threw an error)
            -- ok contains the error message in this case
            result = "error: " .. tostring(ok)
            ok = false
        end

        -- Show code being written
        if decision.action == "write_file" and ok
            and decision.params and decision.params.content then
            display("code", decision.params.path
                .. " written", "cyan")
        end

        -- Show result (truncated for display)
        local display_result = tostring(result)
        if #display_result > 300 then
            display_result = display_result:sub(1, 300) .. "..."
        end
        display("result", display_result,
            ok and "white" or "red")

        -- Record in history
        table.insert(history, {
            action = decision.action,
            params = decision.params,
            thought = decision.thought,
            result = tostring(result):sub(1, 500),
            success = ok
        })

        logStep(goal, step, history[#history])

        -- 4. Check terminal actions
        if decision.action == "task_complete" then
            local summary = decision.params
                and decision.params.summary or "Done!"
            display("complete", summary, "lime")
            -- Record completed task for learning
            local w = world.load()
            w.completed_tasks = w.completed_tasks or {}
            table.insert(w.completed_tasks, {
                goal = goal,
                summary = summary,
                steps = step
            })
            while #w.completed_tasks > 20 do
                table.remove(w.completed_tasks, 1)
            end
            world.save(w)
            return true, summary
        end

        if decision.action == "task_failed" then
            local reason = decision.params
                and decision.params.reason or "Failed"
            display("failed", reason, "red")
            return false, reason
        end

        os.sleep(0.2)
        ::continue::
    end

    display("failed", "Reached max steps", "red")
    return false, "max steps reached"
end

return coder
