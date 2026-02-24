-- shared/ai.lua — All AI API calls via OpenRouter
-- Uses OpenRouter's OpenAI-compatible endpoint to access Claude and other models

local config = require("shared/config")

local ai = {}

local API_URL = "https://openrouter.ai/api/v1/chat/completions"

-- Send a raw message to the AI via OpenRouter
-- Returns response text string, or nil + error string
function ai.ask(system_prompt, user_message, max_tokens)
    max_tokens = max_tokens or 1024

    local body = textutils.serializeJSON({
        model = config.model,
        max_tokens = max_tokens,
        messages = {
            { role = "system", content = system_prompt },
            { role = "user",   content = user_message }
        }
    })

    local headers = {
        ["Authorization"] = "Bearer " .. config.openrouter_key,
        ["Content-Type"]  = "application/json"
    }

    local response, err = http.post(API_URL, body, headers)
    if not response then
        local msg = "HTTP error: " .. tostring(err)
        print("[ai] " .. msg)
        return nil, msg
    end

    local raw = response.readAll()
    response.close()

    local data = textutils.unserializeJSON(raw)
    if not data then
        return nil, "Failed to parse API response"
    end

    if data.error then
        local msg = "API error: " .. tostring(data.error.message or data.error)
        print("[ai] " .. msg)
        return nil, msg
    end

    -- OpenRouter returns OpenAI-compatible format: choices[1].message.content
    if data.choices and data.choices[1]
        and data.choices[1].message
        and data.choices[1].message.content then
        return data.choices[1].message.content
    end

    return nil, "No text in API response"
end

-- Build a structured reasoning prompt and ask the AI for the next action
-- Returns parsed table { thought, action, params, confidence } or nil
function ai.reason(goal, observations, world_data, history)
    local system_prompt = [[You are an AI agent controlling a CC:Tweaked turtle in FTB StoneBlock 4 (Minecraft 1.21.1).
You are underground in a void world. You control a turtle that can move, dig, place, inspect, and interact.

Available turtle actions:
- forward, back, up, down — movement (costs 1 fuel each)
- turnLeft, turnRight — rotation (free)
- dig, digUp, digDown — break block in front/above/below
- place, placeUp, placeDown — place selected item
- inspect, inspectUp, inspectDown — examine block (returns name, metadata)
- suck, suckUp, suckDown — pick up items from ground or container
- drop, dropUp, dropDown — drop items from inventory
- craft — craft using items in inventory (requires crafting table equipped)
- select(slot) — select inventory slot 1-16
- refuel — consume fuel items in selected slot
- report_to_brain — send a message back to the brain
- request_fuel — ask brain for fuel delivery
- search_web — search the internet for information (recipes, guides)
- task_complete — declare the current task finished successfully
- task_failed — declare the current task failed

IMPORTANT: Respond with ONLY valid JSON. No markdown, no explanation outside the JSON.
Respond with exactly this JSON format:
{"thought": "your reasoning about what to do next", "action": "action_name", "params": {}, "confidence": 0.0}

For actions with parameters:
- select: {"slot": 1}
- place/drop: {"slot": 1} (optional, uses current slot if omitted)
- suck: {"count": 64} (optional)
- search_web: {"query": "search terms"}
- report_to_brain: {"message": "text"}
- task_complete: {"summary": "what was accomplished"}
- task_failed: {"reason": "why it failed"}

Confidence is 0.0 to 1.0 indicating how sure you are this is the right next step.]]

    -- Build world summary (truncated for token efficiency)
    local world_summary = "World knowledge: "
    if world_data then
        local machine_count = 0
        for _ in pairs(world_data.machines or {}) do
            machine_count = machine_count + 1
        end
        local item_count = 0
        for _ in pairs(world_data.items or {}) do
            item_count = item_count + 1
        end
        world_summary = world_summary .. machine_count .. " machines, "
            .. item_count .. " items tracked"
        -- Include machine names
        local names = {}
        for name, info in pairs(world_data.machines or {}) do
            table.insert(names, name .. " at " .. info.x .. "," .. info.y .. "," .. info.z)
        end
        if #names > 0 then
            world_summary = world_summary .. "\nMachines: " .. table.concat(names, "; ")
        end
    end

    -- Build observation text
    local obs_text = "Current observations:\n"
    if observations then
        for k, v in pairs(observations) do
            obs_text = obs_text .. "- " .. tostring(k) .. ": " .. tostring(v) .. "\n"
        end
    end

    -- Build history text (last few steps)
    local hist_text = ""
    if history and #history > 0 then
        hist_text = "Recent actions:\n"
        local start = math.max(1, #history - 5)
        for i = start, #history do
            local h = history[i]
            hist_text = hist_text .. "- Step " .. i .. ": "
                .. tostring(h.action) .. " -> " .. tostring(h.result) .. "\n"
        end
    end

    local user_message = "GOAL: " .. tostring(goal) .. "\n\n"
        .. world_summary .. "\n\n"
        .. obs_text .. "\n"
        .. hist_text .. "\n"
        .. "What is the single next action to take?"

    local response, err = ai.ask(system_prompt, user_message)
    if not response then
        return nil, err
    end

    -- Parse the JSON response
    local parsed = textutils.unserializeJSON(response)
    if not parsed then
        -- Try to extract JSON from response if wrapped in other text
        local json_start = response:find("{")
        local json_end = response:find("}[^}]*$")
        if json_start and json_end then
            local json_str = response:sub(json_start, json_end)
            parsed = textutils.unserializeJSON(json_str)
        end
    end

    if not parsed then
        return nil, "Failed to parse AI response as JSON: " .. response:sub(1, 100)
    end

    return parsed
end

-- Coding-focused reasoning for the self-coding brain agent
-- Returns parsed table { thought, action, params } or nil
function ai.codeReason(goal, observations, world_data, history, context)
    local system_prompt = [[You are an AI coding agent running on a CC:Tweaked computer in Minecraft.
You can read, write, and edit Lua files. You can run code. You can search the web.
You can improve your own source code and create new programs.

You are running on an Advanced Computer with an attached monitor.
The computer uses CC:Tweaked (ComputerCraft for Minecraft) with Lua 5.1.

IMPORTANT FACTS ABOUT CC:TWEAKED:
- Turtles are NOT peripherals. You CANNOT detect turtles with peripheral.find("turtle").
- Turtles communicate via REDNET (wireless modem protocol). Both sides need a wireless modem.
- To find turtles, the user should type "scan" in the terminal (built-in command).
- peripheral.find() only finds devices DIRECTLY attached to this computer (monitors, modems, etc.)
- The turtle API only works ON a turtle computer, not from a regular computer.

Available CC:Tweaked APIs you can use in code:
- fs: file system (fs.open, fs.list, fs.exists, fs.makeDir, fs.delete, fs.combine)
- http: HTTP requests (http.get, http.post)
- os: timers, events, sleep (os.sleep, os.startTimer, os.pullEvent)
- term: terminal output (term.write, term.clear, term.setCursorPos, term.setTextColor)
- textutils: JSON, serialization (textutils.serializeJSON, textutils.unserializeJSON)
- colors: color constants (colors.red, colors.white, colors.lime, etc.)
- peripheral: device access (peripheral.find, peripheral.wrap) — finds attached devices NOT turtles
- rednet: wireless networking — used to communicate with turtles
- shell: run programs (shell.run)
- settings: persistent settings
- gps: GPS positioning
- turtle: turtle control (ONLY works on turtle computers, NOT on this computer)
- redstone: redstone signals (redstone.setOutput, redstone.getInput)
- paintutils: drawing to terminal/monitor

Available actions you can take:
- read_file: Read a file. Params: {"path": "filename"}
- write_file: Create/overwrite a file. Params: {"path": "filename", "content": "code here"}
- edit_file: Find and replace text in a file (plain text, not pattern). Params: {"path": "filename", "find": "old text", "replace": "new text"}
- list_files: List directory contents. Params: {"path": "/"}
- delete_file: Delete a file. Params: {"path": "filename"}
- run_code: Execute Lua code directly and see output. Params: {"code": "print('hello')"}
- run_file: Execute a Lua file. Params: {"path": "filename"}
- search_web: Search the internet for info. Params: {"query": "search terms"}
- learn: Store knowledge for future tasks. Params: {"topic": "name", "info": "what you learned"}
- recall: Retrieve stored knowledge. Params: {"topic": "name"} or {} to list all topics
- send_turtle_task: Send a task to a connected turtle. The turtle has its OWN AI agent that will figure out the details — just describe the goal in plain English. Params: {"turtle_id": 2, "goal": "move forward 3 blocks"}
  IMPORTANT: After sending a task, use task_complete. Do NOT write scripts or code for the turtle — it handles that itself.
- task_complete: Finish successfully. Params: {"summary": "what was accomplished"}
- task_failed: Give up. Params: {"reason": "why it failed"}

TURTLE TASK GUIDELINES:
- send_turtle_task dispatches a goal to the turtle's own AI. You do NOT need to write code for it.
- Keep goals simple and direct: "move forward 5 blocks", "dig a 3x3 tunnel", "turn right and move forward"
- After sending a turtle task, immediately use task_complete to report what you did.
- Do NOT try to write navigation scripts, movement files, or any code for turtles from this computer.
- The turtle API (turtle.forward, etc.) does NOT work on this computer — only on the turtle itself.

IMPORTANT RULES:
1. Respond with ONLY valid JSON. No markdown, no backticks, no explanation outside JSON.
2. Write clean Lua code for CC:Tweaked (Lua 5.1). Use fs API not io. Use textutils not json.
3. You CAN modify your own source files to improve yourself. System files are auto-backed up.
4. All .lua files are SYNTAX CHECKED before saving. If your code has syntax errors, the write is rejected.
5. NEVER touch shared/config.lua or recovery.lua — they are protected and cannot be accessed.
6. Test code after writing it with run_code or run_file.
7. If something fails, try a DIFFERENT approach. Do NOT repeat the same failing action more than twice.
8. Use learn/recall to build up knowledge over time.
9. When writing multi-line code in write_file content, use \n for newlines.
10. The edit_file action uses plain text matching (not patterns/regex).
11. If an action returns an error saying a file is protected or has a syntax error, do NOT retry the same thing.
12. Focus on the user's actual task. Do not get sidetracked by config files or system setup.
13. When improving system files, make SMALL targeted changes. Read first, understand, then edit carefully.

Respond in exactly this JSON format:
{"thought": "your reasoning about what to do next", "action": "action_name", "params": {}}]]

    -- Build observation text
    local obs_text = "Computer state:\n"
    for k, v in pairs(observations) do
        obs_text = obs_text .. "- " .. tostring(k) .. ": "
            .. tostring(v) .. "\n"
    end

    -- Include turtle status from context
    context = context or {}
    local turtle_text = ""
    if context.turtle_status then
        turtle_text = "Connected turtles: "
            .. context.turtle_status .. "\n"
        if context.known_turtles then
            for id, info in pairs(context.known_turtles) do
                turtle_text = turtle_text .. "  Turtle #" .. id
                    .. " — role: " .. tostring(info.role)
                    .. ", fuel: " .. tostring(info.fuel) .. "\n"
            end
        end
        turtle_text = turtle_text
            .. "Use send_turtle_task to give a turtle a job.\n\n"
    else
        turtle_text = "No turtles connected. "
            .. "User can type 'scan' to find turtles.\n\n"
    end

    -- Include stored knowledge
    local knowledge_text = ""
    if world_data and world_data.knowledge then
        local entries = {}
        for topic, info in pairs(world_data.knowledge) do
            table.insert(entries, topic .. ": "
                .. tostring(info):sub(1, 100))
        end
        if #entries > 0 then
            knowledge_text = "Stored knowledge:\n"
                .. table.concat(entries, "\n") .. "\n\n"
        end
    end

    -- Include recently completed tasks
    local past_text = ""
    if world_data and world_data.completed_tasks then
        local recent = {}
        local start = math.max(1, #world_data.completed_tasks - 5)
        for i = start, #world_data.completed_tasks do
            local t = world_data.completed_tasks[i]
            table.insert(recent, t.goal .. " -> "
                .. tostring(t.summary))
        end
        if #recent > 0 then
            past_text = "Recently completed tasks:\n"
                .. table.concat(recent, "\n") .. "\n\n"
        end
    end

    -- Build action history for this task
    local hist_text = ""
    if history and #history > 0 then
        hist_text = "Actions taken so far in this task:\n"
        local start = math.max(1, #history - 8)
        for i = start, #history do
            local h = history[i]
            local label = tostring(h.action)
            if h.params and h.params.path then
                label = label .. " (" .. h.params.path .. ")"
            end
            hist_text = hist_text .. "- Step " .. i .. ": "
                .. label .. " -> "
                .. tostring(h.result):sub(1, 200) .. "\n"
        end
    end

    local user_message = "GOAL: " .. tostring(goal) .. "\n\n"
        .. obs_text .. "\n"
        .. turtle_text
        .. knowledge_text
        .. past_text
        .. hist_text .. "\n"
        .. "What is the single next action to take?"

    -- Use higher token limit for coding (need room for code content)
    local response, err = ai.ask(system_prompt, user_message, 4096)
    if not response then
        return nil, err
    end

    -- Parse JSON response
    local parsed = textutils.unserializeJSON(response)
    if not parsed then
        -- Try to extract JSON if wrapped in extra text
        local json_start = response:find("{")
        local json_end = response:find("}[^}]*$")
        if json_start and json_end then
            parsed = textutils.unserializeJSON(
                response:sub(json_start, json_end))
        end
    end

    if not parsed then
        return nil, "Failed to parse AI response: "
            .. response:sub(1, 100)
    end

    return parsed
end

return ai
