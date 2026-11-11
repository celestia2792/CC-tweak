local basalt = require("basalt")

local terminalRoot = basalt.getMainFrame()
local monitorName = "monitor_0"
local monitor = peripheral.wrap(monitorName)
local monitorRoot = basalt.createFrame(monitor, monitorName)

terminalRoot.background = colors.black
monitorRoot.background = colors.gray

local count = basalt.state(0)

local monitorWidth, monitorHeight = monitor.getSize()
local plotRadius = math.max(1, math.min(
    math.floor((monitorWidth - 3) / 2),
    math.floor((monitorHeight - 6) / 2),
    8
))
local plotSize = plotRadius * 2 + 1
local plotX = math.floor((monitorWidth - plotSize) / 2) + 1
local plotY = 6

local function readPose()
    local pose = sublevel.getLastPose()
    local orientation = pose.orientation
    local vector = orientation.v
    local w, x, y, z = orientation.a, vector.x, vector.y, vector.z
    local positionX, positionZ = pose.position.x, pose.position.z

    if type(w) ~= "number" or type(x) ~= "number" or type(y) ~= "number"
        or type(z) ~= "number" or type(positionX) ~= "number" or type(positionZ) ~= "number" then
        error("sublevel.getLastPose() returned invalid position or orientation data")
    end

    local magnitude = math.sqrt(w * w + x * x + y * y + z * z)
    if magnitude == 0 then
        error("sublevel.getLastPose() returned a zero-length quaternion")
    end

    w, x, y, z = w / magnitude, x / magnitude, y / magnitude, z / magnitude

    local directionX = -2 * (x * z + w * y)
    local directionZ = 2 * (x * x + y * y) - 1
    local horizontalMagnitude = math.sqrt(directionX * directionX + directionZ * directionZ)
    local yaw

    if horizontalMagnitude > 0.000001 then
        directionX = directionX / horizontalMagnitude
        directionZ = directionZ / horizontalMagnitude
        yaw = math.deg(math.atan2(directionX, -directionZ))
    end

    local grid = {}
    local center = plotRadius + 1
    for row = 1, plotSize do
        grid[row] = {}
        for column = 1, plotSize do
            if row == center and column == center then
                grid[row][column] = "+"
            elseif row == center then
                grid[row][column] = "-"
            elseif column == center then
                grid[row][column] = "|"
            else
                grid[row][column] = " "
            end
        end
    end

    if yaw then
        local scaledX = directionX * plotRadius
        local scaledZ = directionZ * plotRadius
        local endX = scaledX >= 0 and math.floor(scaledX + 0.5) or math.ceil(scaledX - 0.5)
        local endZ = scaledZ >= 0 and math.floor(scaledZ + 0.5) or math.ceil(scaledZ - 0.5)
        local x0, z0 = center, center
        local x1, z1 = center + endX, center + endZ
        local deltaX = math.abs(x1 - x0)
        local stepX = x0 < x1 and 1 or -1
        local deltaZ = -math.abs(z1 - z0)
        local stepZ = z0 < z1 and 1 or -1
        local lineError = deltaX + deltaZ

        while true do
            grid[z0][x0] = "."
            if x0 == x1 and z0 == z1 then
                break
            end

            local doubledError = 2 * lineError
            if doubledError >= deltaZ then
                lineError = lineError + deltaZ
                x0 = x0 + stepX
            end
            if doubledError <= deltaX then
                lineError = lineError + deltaX
                z0 = z0 + stepZ
            end
        end

        local arrow
        if math.abs(directionX) > math.abs(directionZ) * 2.4 then
            arrow = directionX > 0 and ">" or "<"
        elseif math.abs(directionZ) > math.abs(directionX) * 2.4 then
            arrow = directionZ > 0 and "v" or "^"
        elseif directionX * directionZ > 0 then
            arrow = "\\"
        else
            arrow = "/"
        end

        grid[z1][x1] = arrow
        grid[center][center] = "O"
    end

    local rows = {}
    for row = 1, plotSize do
        rows[row] = table.concat(grid[row])
    end

    return {
        positionText = string.format("X: %.1f  Z: %.1f", positionX, positionZ),
        yawText = yaw and string.format("Yaw: %.1f deg", yaw) or "Yaw: unavailable",
        rows = rows,
    }
end

local poseState = basalt.state(readPose())

local function refreshPose()
    poseState:update(function()
        return readPose()
    end)
end

terminalRoot:addLabel({
    x = 2,
    y = 2,
    text = "MAIN TERMINAL",
    foreground = colors.orange,
})

terminalRoot:addLabel({
    x = 2,
    y = 5,
    width = 21,
    text = count:map(function(value)
        return "Shared count: " .. value
    end),
})

terminalRoot:addButton({
    x = 2,
    y = 8,
    width = 21,
    height = 3,
    text = "Increment",
    background = colors.blue,
}):onClick(function()
    count:update(function(value) return value + 1 end)
end)

terminalRoot:addButton({
    x = 2,
    y = 12,
    width = 21,
    height = 3,
    text = "Refresh pose",
}):onClick(function()
    refreshPose()
end)

terminalRoot:addButton({
    x = 2,
    y = 16,
    width = 21,
    height = 2,
    text = "Exit",
    background = colors.red,
}):onClick(function()
    basalt.stop()
end)

monitorRoot:addLabel({
    x = plotX,
    y = 1,
    width = plotSize,
    text = "XZ HEADING",
    foreground = colors.yellow,
})

monitorRoot:addLabel({
    x = 2,
    y = 2,
    width = monitorWidth - 2,
    text = count:map(function(value)
        return "Shared count: " .. value
    end),
})

monitorRoot:addLabel({
    x = 2,
    y = 3,
    width = monitorWidth - 2,
    text = poseState:map(function(pose)
        return pose.positionText
    end),
})

monitorRoot:addLabel({
    x = 2,
    y = 4,
    width = monitorWidth - 2,
    text = poseState:map(function(pose)
        return pose.yawText
    end),
})

for row = 1, plotSize do
    local rowIndex = row
    monitorRoot:addLabel({
        x = plotX,
        y = plotY + row - 1,
        width = plotSize,
        text = poseState:map(function(pose)
            return pose.rows[rowIndex]
        end),
        foreground = colors.lime,
    })
end

parallel.waitForAny(function()
    basalt.run()
end, function()
    while true do
        sleep(0.2)
        refreshPose()
    end
end)
