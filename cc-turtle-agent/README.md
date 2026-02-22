# CC:Tweaked AI Turtle Agent

An AI-powered turtle agent network for [CC:Tweaked](https://tweaked.cc/) in
**FTB StoneBlock 4** (Minecraft 1.21.1 NeoForge). A "Brain" advanced computer
orchestrates multiple turtles, each running a ReAct agent loop powered by the
**Anthropic Claude API**. Turtles can mine, craft, build, explore, and look up
recipes via web search — all driven by natural language commands.

## Architecture

```
┌─────────────────────────────────────────────┐
│           Player Terminal Input              │
│              "smelt 64 iron ore"             │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│              BRAIN (Advanced Computer)       │
│                                             │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐ │
│  │ Command  │  │ AI Task  │  │  Monitor   │ │
│  │  Queue   │→ │ Decomp.  │→ │  Display   │ │
│  └──────────┘  └──────────┘  └───────────┘ │
│        │            │                       │
│        │     ┌──────┴──────┐                │
│        │     │  Claude API │                │
│        │     └──────┬──────┘                │
│        │            │                       │
│  ┌─────┴────────────┴─────────────┐         │
│  │        Rednet (wireless)       │         │
│  └────┬──────────┬──────────┬─────┘         │
└───────┼──────────┼──────────┼───────────────┘
        │          │          │
        ▼          ▼          ▼
┌──────────┐ ┌──────────┐ ┌──────────┐
│ Turtle 1 │ │ Turtle 2 │ │ Turtle 3 │
│  miner   │ │  crafter  │ │  scout   │
│          │ │          │ │          │
│ ReAct    │ │ ReAct    │ │ ReAct    │
│ Loop:    │ │ Loop:    │ │ Loop:    │
│ Observe  │ │ Observe  │ │ Observe  │
│ Reason   │ │ Reason   │ │ Reason   │
│ Act      │ │ Act      │ │ Act      │
│ Report   │ │ Report   │ │ Report   │
└──────────┘ └──────────┘ └──────────┘

Data Flow:
  world.json ←→ Brain ←rednet→ Turtles
  Claude API ←http→ Brain & Turtles
  Tavily API ←http→ Turtles (web search)
```

## Prerequisites

- **CC:Tweaked** mod installed (included in FTB StoneBlock 4)
- **HTTP API enabled** in CC:Tweaked config
  (`computercraft-server.toml` → `http.enabled = true`)
- **Wireless Modems** on the brain and all turtles
- **Advanced Monitor** attached to the brain (recommended: 4x3 block)
- An **Anthropic API key** — [sign up here](https://console.anthropic.com/)
- A **Tavily API key** — [sign up here](https://tavily.com/)
- Optional: GPS cluster for coordinate tracking

## Quick Start

### 1. Fork this repo

Fork this repository on GitHub and note your username.

### 2. Install on the Brain computer

Open an **Advanced Computer** in-game and run:

```
wget run https://raw.githubusercontent.com/YOURNAME/cc-turtle-agent/main/install.lua
```

Select `b` for brain when prompted.

### 3. Install on each Turtle

Open each **Turtle** in-game and run:

```
wget run https://raw.githubusercontent.com/YOURNAME/cc-turtle-agent/main/install.lua
```

Select `t` for turtle when prompted.

### 4. Configure API keys

On **every** computer/turtle, edit `shared/config.lua`:

```
edit shared/config.lua
```

Fill in:
- `config.anthropic_key` — your Anthropic API key
- `config.tavily_key` — your Tavily API key
- `config.brain_id` — the computer ID of your brain (run `id` on the brain)
- `config.repo` — your forked repo's raw URL

### 5. Reboot everything

```
reboot
```

The brain will start displaying on the monitor. Turtles will register
automatically.

## Usage

Type commands into the brain's terminal. The AI will decompose them into
sub-tasks and assign them to available turtles.

### Example Commands

```
mine 10 blocks forward and deposit in the chest
smelt 64 iron ore
explore north for 20 blocks and report what you find
craft a diamond pickaxe
build a 3x3 room here
go to the furnace and check if smelting is done
find and mine any nearby iron ore
look up the recipe for a mekanism metallurgic infuser
```

### Teaching the AI About Your Base

Register machines and locations so the AI knows your layout:

The world knowledge grows automatically as turtles explore, but you can also
edit `data/world.json` directly or use the brain terminal to guide turtles
to specific locations.

## Updating

To pull the latest code without losing your world data or API keys:

```
wget run https://raw.githubusercontent.com/YOURNAME/cc-turtle-agent/main/update.lua
```

Or if you already have `update.lua` on disk:

```
update
```

## File Structure

```
(on each CC computer after install)
├── startup.lua          ← Brain or turtle main loop
├── shared/
│   ├── config.lua       ← Your API keys (local only, not in git)
│   ├── agent.lua        ← ReAct loop engine
│   ├── ai.lua           ← Claude API integration
│   ├── search.lua       ← Tavily web search
│   ├── world.lua        ← World knowledge persistence
│   ├── queue.lua        ← Command queue (brain only)
│   ├── monitor.lua      ← Monitor display (brain only)
│   └── net.lua          ← Rednet messaging
└── data/
    ├── world.json       ← Persistent world knowledge
    ├── queue.json       ← Pending commands
    └── logs/            ← Agent step logs
```

## How the ReAct Loop Works

Each turtle runs an **Observe → Reason → Act → Report** cycle:

1. **Observe**: Read fuel level, inventory, surrounding blocks
2. **Reason**: Send observations + goal + world context to Claude API;
   AI returns `{ thought, action, params, confidence }`
3. **Act**: Execute the chosen action (move, dig, place, search, etc.)
4. **Report**: Send result back to the brain via rednet

The loop continues until the AI declares `task_complete` or `task_failed`,
or the step limit is reached.

## Troubleshooting

**"No modem found"**
Attach a wireless modem to any side of the computer/turtle. For turtles,
use `equip` to place it on the left or right side.

**"HTTP error" or API calls failing**
- Check that HTTP is enabled in `computercraft-server.toml`
- Verify your API keys in `shared/config.lua`
- Make sure your server can reach `api.anthropic.com` and `api.tavily.com`

**"Failed to parse API response"**
- The AI model may have returned unexpected output. Check `data/logs/` for
  the full response. This is usually transient.

**Turtle not responding**
- Make sure the turtle has fuel (`refuel` command)
- Check that the turtle and brain are on the same rednet frequency
- Verify `config.brain_id` matches the brain's actual computer ID

**"Too long without yielding"**
- This should not happen — all loops include `os.sleep()` calls. If it does,
  reboot the affected computer.

## API Costs

This project uses `claude-haiku-3-5-20241022` by default for fast, cheap
responses. Each turtle step makes one API call. Typical costs:

- ~$0.001 per reasoning step
- A 50-step task costs roughly $0.05
- Idle turtles make zero API calls

You can monitor usage at [console.anthropic.com](https://console.anthropic.com/).

## Links

- [Anthropic API](https://console.anthropic.com/) — Claude API keys
- [Tavily](https://tavily.com/) — Web search API keys
- [CC:Tweaked Docs](https://tweaked.cc/) — ComputerCraft API reference
- [FTB StoneBlock 4](https://www.feed-the-beast.com/) — Modpack info
