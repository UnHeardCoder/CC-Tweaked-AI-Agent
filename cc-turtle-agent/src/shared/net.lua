-- shared/net.lua — Rednet messaging helpers
-- Wraps rednet open/send/receive for brain-turtle communication

local config = require("shared/config")

local net = {}

-- Open modem on any available side
function net.open()
    local sides = { "top", "bottom", "left", "right", "front", "back" }
    for _, side in ipairs(sides) do
        if peripheral.getType(side) == "modem" then
            rednet.open(side)
            print("[net] Modem opened on " .. side)
            return true
        end
    end
    -- Try wireless modem via peripheral.find
    local modem = peripheral.find("modem")
    if modem then
        local name = peripheral.getName(modem)
        rednet.open(name)
        print("[net] Modem opened on " .. name)
        return true
    end
    print("[net] WARNING: No modem found!")
    return false
end

-- Send a message table to the brain computer
function net.sendToBrain(msg)
    local payload = textutils.serializeJSON(msg)
    rednet.send(config.brain_id, payload, "turtle_agent")
end

-- Broadcast a message table to all computers
function net.broadcast(msg)
    local payload = textutils.serializeJSON(msg)
    rednet.broadcast(payload, "turtle_agent")
end

-- Receive a message with timeout; returns sender_id, message table
function net.receive(timeout)
    local sender, raw, protocol = rednet.receive("turtle_agent", timeout)
    if not sender then
        return nil, nil
    end
    local msg = textutils.unserializeJSON(raw)
    if not msg then
        -- Fallback: treat as plain string
        msg = { text = raw }
    end
    return sender, msg
end

-- Block until a message with a specific type field arrives
function net.waitFor(msgType, timeout)
    local deadline = os.clock() + (timeout or 30)
    while os.clock() < deadline do
        local remaining = deadline - os.clock()
        if remaining <= 0 then break end
        local sender, msg = net.receive(remaining)
        if msg and msg.type == msgType then
            return sender, msg
        end
    end
    return nil, nil
end

return net
