-- config.example.lua
-- Copy this file to src/shared/config.lua and fill in your real API keys.
-- NEVER commit src/shared/config.lua to version control.

local config = {}

-- Anthropic API key — get one at https://console.anthropic.com/
config.anthropic_key = "sk-ant-YOUR_KEY_HERE"

-- Tavily API key — get one at https://tavily.com/
config.tavily_key = "tvly-YOUR_KEY_HERE"

-- CC computer ID of the brain (run `id` on the brain computer to find it)
config.brain_id = 0

-- Claude model to use (haiku for speed and low cost)
config.model = "claude-haiku-3-5-20241022"

-- GitHub raw content base URL for your fork
-- Change YOURNAME to your GitHub username after forking
config.repo = "https://raw.githubusercontent.com/YOURNAME/cc-turtle-agent/main"

return config
