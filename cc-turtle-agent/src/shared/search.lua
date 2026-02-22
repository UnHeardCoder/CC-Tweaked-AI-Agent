-- shared/search.lua — Tavily web search calls
-- Provides real-time web search for recipe lookups and game info

local config = require("shared/config")

local search = {}

local TAVILY_URL = "https://api.tavily.com/search"

-- Perform a web search via Tavily API
-- Returns answer string and array of result snippets, or nil + error
function search.query(query_string)
    local body = textutils.serializeJSON({
        api_key = config.tavily_key,
        query = query_string,
        search_depth = "basic",
        max_results = 3,
        include_answer = true
    })

    local headers = {
        ["content-type"] = "application/json"
    }

    local response, err = http.post(TAVILY_URL, body, headers)
    if not response then
        local msg = "Search HTTP error: " .. tostring(err)
        print("[search] " .. msg)
        return nil, nil, msg
    end

    local raw = response.readAll()
    response.close()

    local data = textutils.unserializeJSON(raw)
    if not data then
        return nil, nil, "Failed to parse search response"
    end

    -- Extract answer and snippets
    local answer = data.answer or "No direct answer found."
    local snippets = {}
    if data.results then
        for _, result in ipairs(data.results) do
            table.insert(snippets, {
                title = result.title or "",
                content = result.content or "",
                url = result.url or ""
            })
        end
    end

    return answer, snippets
end

-- Convenience: look up a Minecraft/StoneBlock 4 item or recipe
function search.wikiLookup(item_name)
    local query = "minecraft stoneblock 4 " .. tostring(item_name) .. " recipe"
    return search.query(query)
end

return search
