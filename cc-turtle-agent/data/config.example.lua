-- config.example.lua
-- Copy this file to src/shared/config.lua and fill in your real API keys.
-- NEVER commit src/shared/config.lua to version control.

local config = {}

-- OpenRouter API key — get one at https://openrouter.ai/keys
config.openrouter_key = "sk-or-v1-YOUR_KEY_HERE"

-- Tavily API key — get one at https://tavily.com/
config.tavily_key = "tvly-YOUR_KEY_HERE"

-- CC computer ID of the brain (run `id` on the brain computer to find it)
config.brain_id = 0

-- Model to use via OpenRouter (see https://openrouter.ai/models)
-- Using Claude 3.5 Haiku for speed and low cost
config.model = "anthropic/claude-3.5-haiku-20241022"

-- GitHub raw content base URL for your fork
config.repo = "https://raw.githubusercontent.com/UnHeardCoder/cc-turtle-agent/main"

return config
