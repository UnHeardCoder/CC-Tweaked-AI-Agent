-- shared/ai.lua — All AI API calls via OpenRouter
-- Uses OpenRouter's OpenAI-compatible endpoint to access Claude and other models

local config = require("shared/config")

local ai = {}

local API_URL = "https://openrouter.ai/api/v1/chat/completions"

-- Send a raw message to the AI via OpenRouter
-- Returns response text string, or nil + error string
function ai.ask(system_prompt, user_message)
    local body = textutils.serializeJSON({
        model = config.model,
        max_tokens = 1024,
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

return ai
