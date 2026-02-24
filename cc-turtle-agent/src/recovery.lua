-- recovery.lua — Emergency recovery script
-- Run this manually if the AI broke its own code:
--   Type "recovery" at the CraftOS shell
--
-- This file is PROTECTED — the AI cannot modify or delete it.

print("========================================")
print("  AI Brain Recovery Tool")
print("========================================")
print()

-- Option 1: Restore from backups
if fs.exists("data/backups") then
    local backups = fs.list("data/backups")
    if #backups > 0 then
        print("Found " .. #backups .. " backup(s):")
        for _, name in ipairs(backups) do
            -- Backup names use __ as path separator
            local original = name:gsub("__", "/")
            print("  " .. name .. " -> " .. original)
        end
        print()
        print("Restore from backups? (y/n)")
        write("> ")
        local input = read()
        if input == "y" or input == "Y" then
            for _, name in ipairs(backups) do
                local backup_path = fs.combine("data/backups", name)
                if not fs.isDir(backup_path) then
                    local original = name:gsub("__", "/")
                    -- Ensure parent directory exists
                    local dir = fs.getDir(original)
                    if dir and dir ~= "" and not fs.exists(dir) then
                        fs.makeDir(dir)
                    end
                    if fs.exists(original) then
                        fs.delete(original)
                    end
                    fs.copy(backup_path, original)
                    print("  Restored: " .. original)
                end
            end
            print()
            print("Backups restored! Rebooting...")
            os.sleep(2)
            os.reboot()
            return
        end
    else
        print("No backups found in data/backups/")
    end
else
    print("No backup directory found.")
end

print()

-- Option 2: Re-download from GitHub
print("Re-download all code from GitHub? (y/n)")
print("(This will overwrite all code files but keep")
print(" your config, world data, and queue.)")
write("> ")
local input = read()
if input == "y" or input == "Y" then
    if fs.exists("update.lua") then
        print("Running update.lua...")
        shell.run("update.lua")
    else
        print("update.lua not found. Trying installer...")
        local REPO = "https://raw.githubusercontent.com/UnHeardCoder/CC-Tweaked-AI-Agent/main/cc-turtle-agent"
        local response = http.get(REPO .. "/update.lua")
        if response then
            local f = fs.open("update.lua", "w")
            if f then
                f.write(response.readAll())
                f.close()
                response.close()
                print("Downloaded update.lua. Running...")
                shell.run("update.lua")
            else
                response.close()
                print("Failed to write update.lua")
            end
        else
            print("Failed to download. Check internet connection.")
        end
    end
else
    print()
    print("Recovery cancelled. You can also try:")
    print("  - Edit the broken file manually")
    print("  - Run: update.lua (re-downloads all code)")
    print("  - Delete startup.lua and run install.lua")
end
