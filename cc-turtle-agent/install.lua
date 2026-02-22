-- install.lua — Bootstrap installer for CC:Tweaked AI Turtle Agent
-- Run this with: wget run <repo_url>/install.lua
-- It downloads all project files and sets up the computer.

-- ============================================================
-- CONFIGURATION — Change this to your GitHub raw content URL
-- ============================================================
local REPO = "https://raw.githubusercontent.com/UnHeardCoder/CC-Tweaked-AI-Agent/main/cc-turtle-agent"

-- Files to download for the brain computer
local BRAIN_FILES = {
    { remote = "src/brain/startup.lua",    local_path = "startup.lua" },
    { remote = "src/shared/config.lua",    local_path = "shared/config.lua" },
    { remote = "src/shared/agent.lua",     local_path = "shared/agent.lua" },
    { remote = "src/shared/ai.lua",        local_path = "shared/ai.lua" },
    { remote = "src/shared/search.lua",    local_path = "shared/search.lua" },
    { remote = "src/shared/world.lua",     local_path = "shared/world.lua" },
    { remote = "src/shared/queue.lua",     local_path = "shared/queue.lua" },
    { remote = "src/shared/monitor.lua",   local_path = "shared/monitor.lua" },
    { remote = "src/shared/net.lua",       local_path = "shared/net.lua" },
}

-- Files to download for turtle computers
local TURTLE_FILES = {
    { remote = "src/turtle/startup.lua",   local_path = "startup.lua" },
    { remote = "src/shared/config.lua",    local_path = "shared/config.lua" },
    { remote = "src/shared/agent.lua",     local_path = "shared/agent.lua" },
    { remote = "src/shared/ai.lua",        local_path = "shared/ai.lua" },
    { remote = "src/shared/search.lua",    local_path = "shared/search.lua" },
    { remote = "src/shared/world.lua",     local_path = "shared/world.lua" },
    { remote = "src/shared/queue.lua",     local_path = "shared/queue.lua" },
    { remote = "src/shared/monitor.lua",   local_path = "shared/monitor.lua" },
    { remote = "src/shared/net.lua",       local_path = "shared/net.lua" },
}

-- Download a single file from the repo
local function download(remote_path, local_path)
    local url = REPO .. "/" .. remote_path
    local response = http.get(url)
    if not response then
        print("  FAILED: " .. remote_path)
        return false
    end
    -- Ensure parent directory exists
    local dir = fs.getDir(local_path)
    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    local f = fs.open(local_path, "w")
    if not f then
        print("  FAILED to write: " .. local_path)
        response.close()
        return false
    end
    f.write(response.readAll())
    f.close()
    response.close()
    print("  OK: " .. local_path)
    return true
end

-- ============================================================
-- MAIN INSTALLER
-- ============================================================

print("========================================")
print("  CC:Tweaked AI Turtle Agent Installer")
print("========================================")
print()

-- Detect or ask for computer role
local role = settings.get("agent.role")
if not role then
    print("What type of computer is this?")
    print("  b = Brain (advanced computer)")
    print("  t = Turtle")
    write("> ")
    local input = read()
    if input == "b" or input == "B" or input == "brain" then
        role = "brain"
    else
        role = "turtle"
    end
    settings.set("agent.role", role)
    settings.save()
    print()
end

print("Role: " .. role)
print("Computer ID: " .. os.getComputerID())
print()

-- Select file list based on role
local files = role == "brain" and BRAIN_FILES or TURTLE_FILES

-- Create required directories
if not fs.exists("shared") then fs.makeDir("shared") end
if not fs.exists("data") then fs.makeDir("data") end
if not fs.exists("data/logs") then fs.makeDir("data/logs") end

-- Download files
print("Downloading files...")
local success_count = 0
local fail_count = 0

for _, entry in ipairs(files) do
    -- Skip config.lua if it already exists (preserve player keys)
    if entry.local_path == "shared/config.lua" and fs.exists("shared/config.lua") then
        print("  SKIP: shared/config.lua (already exists, preserving keys)")
        success_count = success_count + 1
    else
        if download(entry.remote, entry.local_path) then
            success_count = success_count + 1
        else
            fail_count = fail_count + 1
        end
    end
end

-- If config.lua doesn't exist, download the example and rename it
if not fs.exists("shared/config.lua") then
    print()
    print("Setting up config from template...")
    local ok = download("data/config.example.lua", "shared/config.lua")
    if ok then
        print()
        print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
        print("!! IMPORTANT: Edit shared/config.lua !!")
        print("!! Add your Anthropic and Tavily keys !!")
        print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
    end
end

-- Print summary
print()
print("========================================")
print("  Installation Complete!")
print("========================================")
print("  Role:      " .. role)
print("  Downloaded: " .. success_count .. " files")
if fail_count > 0 then
    print("  Failed:    " .. fail_count .. " files")
end
print()

if role == "brain" then
    print("Next steps:")
    print("  1. Edit shared/config.lua with your API keys")
    print("  2. Attach an advanced monitor")
    print("  3. Attach a wireless modem")
    print("  4. Reboot (or wait 3 seconds)")
else
    print("Next steps:")
    print("  1. Edit shared/config.lua with your API keys")
    print("  2. Set brain_id to your brain's computer ID")
    print("  3. Equip a wireless modem (left or right)")
    print("  4. Reboot (or wait 3 seconds)")
end

print()
print("Rebooting in 3 seconds...")
os.sleep(3)
os.reboot()
