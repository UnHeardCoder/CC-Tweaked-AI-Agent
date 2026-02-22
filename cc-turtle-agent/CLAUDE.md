# CC:Tweaked AI Turtle Agent — Project Context

## What This Project Is

An AI-powered turtle agent network for CC:Tweaked (ComputerCraft) running in
FTB StoneBlock 4 (Minecraft 1.21.1 NeoForge). A "Brain" advanced computer
orchestrates multiple turtles, each running a local ReAct agent loop powered
by AI models via OpenRouter (Claude, GPT, Gemini, and more).

## Environment

- **Modpack**: FTB StoneBlock 4 — void world, no surface, dense underground.
- **Mod**: CC:Tweaked 1.21.x — Lua 5.2-compatible runtime inside Minecraft.
- **Computers**: Advanced computers (color monitors, rednet) and turtles
  (mining/crafting variants with movement, inventory, peripheral access).

## CC:Tweaked API Surface

Key APIs used throughout this codebase:

| API | Purpose |
|---|---|
| `turtle.*` | Movement, digging, placing, inspecting, sucking, dropping, crafting, refueling |
| `peripheral.*` | Wrap monitors, modems, inventories |
| `http.*` | HTTP GET/POST for API calls (must be enabled in server config) |
| `rednet.*` | Wireless messaging between computers over modems |
| `fs.*` | File system — read, write, list, exists, makeDir |
| `textutils.*` | `serializeJSON` / `unserializeJSON` for all JSON work |
| `os.*` | `sleep`, `pullEvent`, `getComputerID`, `getComputerLabel` |
| `settings.*` | Persistent key-value store across reboots |
| `colors.*` / `colours.*` | Color constants for monitors |
| `term.*` | Terminal output (local screen) |

## StoneBlock 4 Context

- Void world: turtles operate underground; no sky, no surface biomes.
- Modded ores and machines (e.g., Mekanism, Thermal, Applied Energistics).
- Crafting recipes may differ from vanilla — the AI uses web search (Tavily)
  to look up modpack-specific recipes at runtime.

## Coding Conventions

- **All Lua**, compatible with CC:Tweaked 1.21.x (Lua 5.2 subset).
- **JSON via textutils**: `textutils.serializeJSON(t)` and
  `textutils.unserializeJSON(s)` — never hand-roll JSON.
- **Error handling**: Every `http.post`/`http.get` checks for `nil` response.
  Every turtle action is wrapped in `pcall()`.
- **File paths**: Forward slashes, relative to the computer root.
- **Modules**: `local mod = require("shared/module_name")`.
- **Config**: `src/shared/config.lua` is gitignored; copy from
  `data/config.example.lua` and fill in API keys.
- **Keep files short**: Target under 200 lines each.

## ReAct Loop (shared/agent.lua)

Each agent step follows Observe → Reason → Act → Report:

1. **Observe** — Gather current state: facing direction, fuel level,
   inventory summary, blocks in front/above/below.
2. **Reason** — Send observations + world context + goal to OpenRouter API.
   AI returns `{ thought, action, params, confidence }`.
3. **Act** — Dispatch the chosen action (move, dig, place, search, etc.).
4. **Report** — Send result back to the brain via rednet.

The loop continues until the AI returns `task_complete`, `task_failed`,
or the step limit is reached.

## File Responsibilities

| File | Role |
|---|---|
| `src/brain/startup.lua` | Brain main loop — queue processing, task decomposition, turtle management |
| `src/turtle/startup.lua` | Turtle agent loop — listens for tasks, runs agent, reports back |
| `src/shared/agent.lua` | ReAct loop — observe/reason/act/report cycle |
| `src/shared/ai.lua` | OpenRouter API calls (supports any model) |
| `src/shared/search.lua` | Tavily web search integration |
| `src/shared/world.lua` | world.json persistence helpers |
| `src/shared/queue.lua` | File-backed FIFO command queue |
| `src/shared/monitor.lua` | Monitor display with colors and scrolling |
| `src/shared/net.lua` | Rednet messaging helpers |
| `src/shared/config.lua` | API keys and settings (gitignored) |
| `install.lua` | One-command bootstrap installer |
| `update.lua` | Pull latest code without wiping data |
