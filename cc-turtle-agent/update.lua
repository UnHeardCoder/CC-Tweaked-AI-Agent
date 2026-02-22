-- update.lua — Pull latest code from GitHub without wiping data
-- Preserves: data/world.json, data/queue.json, shared/config.lua

-- ============================================================
-- CONFIGURATION — Must match install.lua
-- ============================================================
local REPO = "https://raw.githubusercontent.com/UnHeardCoder/cc-turtle-agent/main"

-- All code files that can be updated (NO data files, NO config)
local SHARED_FILES = {
    { remote = "src/shared/agent.lua",     local_path = "shared/agent.lua" },
    { remote = "src/shared/ai.lua",        local_path = "shared/ai.lua" },
    { remote = "src/shared/search.lua",    local_path = "shared/search.lua" },
    { remote = "src/shared/world.lua",     local_path = "shared/world.lua" },
    { remote = "src/shared/queue.lua",     local_path = "shared/queue.lua" },
    { remote = "src/shared/monitor.lua",   local_path = "shared/monitor.lua" },
    { remote = "src/shared/net.lua",       local_path = "shared/net.lua" },
}

-- Download a single file, overwriting existing
local function download(remote_path, local_path)
    local url = REPO .. "/" .. remote_path
    local response = http.get(url)
    if not response then
        print("  FAILED: " .. remote_path)
        return false
    end
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
-- MAIN UPDATER
-- ============================================================

print("========================================")
print("  CC:Tweaked AI Turtle Agent Updater")
print("========================================")
print()

local role = settings.get("agent.role") or "unknown"
print("Role: " .. role)
print("Computer ID: " .. os.getComputerID())
print()

-- Update shared modules
print("Updating shared modules...")
local ok_count = 0
local fail_count = 0

for _, entry in ipairs(SHARED_FILES) do
    if download(entry.remote, entry.local_path) then
        ok_count = ok_count + 1
    else
        fail_count = fail_count + 1
    end
end

-- Update role-specific startup.lua
print()
print("Updating startup.lua...")
if role == "brain" then
    download("src/brain/startup.lua", "startup.lua")
elseif role == "turtle" then
    download("src/turtle/startup.lua", "startup.lua")
else
    print("  Unknown role — skipping startup.lua")
    print("  Run install.lua first to set your role.")
end

-- Summary
print()
print("========================================")
print("  Update Complete!")
print("========================================")
print("  Updated:  " .. ok_count .. " shared files")
if fail_count > 0 then
    print("  Failed:   " .. fail_count .. " files")
end
print()
print("  PRESERVED: shared/config.lua (your API keys)")
print("  PRESERVED: data/world.json (world knowledge)")
print("  PRESERVED: data/queue.json (command queue)")
print()
print("Rebooting in 3 seconds...")
os.sleep(3)
os.reboot()
