local basalt = require("basalt")
local imageLib = basalt.use("image")

local terminalRoot = basalt.getMainFrame()
terminalRoot.background = colors.black
local toast = terminalRoot:addToast({})
local monitor = peripheral.find("monitor")
local relay = peripheral.find("redstone_relay")
local navWidth = 13
local imageSize = 16
local angleOffsets = { 0, 90, 180, 270 }
local sides = { "top", "bottom", "left", "right", "front", "back" }
if relay then
    for _, side in ipairs(sides) do
        relay.setOutput(side, false)
    end
end
local configPath = fs.combine(shell.dir(), "config.txt")
local defaultConfig = {
    angleOffset = 0,
    altitudeOffset = 0,
    cwSide = "top",
    ccwSide = "bottom",
    fwdSide = "front",
    Dest_X = 0,
    Dest_Z = 0,
    MaxThrust = 0,
    PilotEnable = false,
}

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function isInteger(value)
    return isFiniteNumber(value) and value % 1 == 0
end

local function parseNumberInput(text, label, integerOnly)
    local value = tonumber(text)
    if not isFiniteNumber(value) then
        return nil, "Enter a valid " .. label .. "."
    end
    if integerOnly and not isInteger(value) then
        return nil, label .. " must be an integer."
    end
    return value
end

local function isValidAngleOffset(value)
    for _, offset in ipairs(angleOffsets) do
        if value == offset then
            return true
        end
    end
    return false
end

local function isValidSide(value)
    for _, side in ipairs(sides) do
        if value == side then
            return true
        end
    end
    return false
end

local function loadConfig()
    if not fs.exists(configPath) then
        return defaultConfig
    end

    local file = fs.open(configPath, "r")
    if not file then
        return defaultConfig, "Unable to read config file: " .. configPath
    end

    local readOk, contents = pcall(file.readAll)
    local closeOk, closeError = pcall(file.close)
    if not readOk then
        return defaultConfig, "Unable to read config file: " .. tostring(contents)
    end
    if not closeOk then
        return defaultConfig, "Unable to close config file: " .. tostring(closeError)
    end

    local parsed, config = pcall(textutils.unserialize, contents)
    if not parsed or type(config) ~= "table" then
        return defaultConfig, "Invalid config file: " .. configPath
    end

    for key, value in pairs(defaultConfig) do
        if config[key] == nil then
            config[key] = value
        end
    end

    if not isValidAngleOffset(config.angleOffset) then
        return defaultConfig, "Invalid angle offset in config file: " .. configPath
    end
    if not isFiniteNumber(config.altitudeOffset) then
        return defaultConfig, "Invalid altitude offset in config file: " .. configPath
    end
    if not isValidSide(config.cwSide)
        or not isValidSide(config.ccwSide)
        or not isValidSide(config.fwdSide) then
        return defaultConfig, "Invalid side selection in config file: " .. configPath
    end
    if not isInteger(config.Dest_X) or not isInteger(config.Dest_Z) then
        return defaultConfig, "Destination coordinates in config must be integers."
    end
    if not isInteger(config.MaxThrust) or config.MaxThrust < 0 or config.MaxThrust > 15 then
        return defaultConfig, "MaxThrust in config must be an integer from 0 to 15."
    end
    if type(config.PilotEnable) ~= "boolean" then
        return defaultConfig, "PilotEnable in config must be a boolean."
    end

    return config
end

local function saveConfig(config)
    local file = fs.open(configPath, "w")
    if not file then
        return false, "Unable to write config file: " .. configPath
    end

    local writeOk, writeError = pcall(function()
        file.write(textutils.serialize(config))
    end)
    local closeOk, closeError = pcall(file.close)
    if not writeOk then
        return false, "Unable to write config file: " .. tostring(writeError)
    end
    if not closeOk then
        return false, "Unable to close config file: " .. tostring(closeError)
    end
    return true
end

if monitor then
    local terminal = term.current()
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()
    monitor.setCursorPos(1, 1)
    monitor.setCursorBlink(false)

    local mirroredTerminal = setmetatable({}, {
        __index = function(_, method)
            local terminalMethod = terminal[method]
            local monitorMethod = monitor[method]
            if type(terminalMethod) ~= "function" or type(monitorMethod) ~= "function" then
                return terminalMethod
            end

            return function(...)
                local results = table.pack(terminalMethod(...))
                monitorMethod(...)
                return table.unpack(results, 1, results.n)
            end
        end,
    })
    terminalRoot:setTerm(mirroredTerminal)
    terminalRoot.monitor = peripheral.getName(monitor)
end

local config, configError = loadConfig()
if configError then
    toast:error(configError)
end
local angleOffset = config.angleOffset
local altitudeOffset = config.altitudeOffset
CW_SIDE = config.cwSide
CCW_SIDE = config.ccwSide
FWD_SIDE = config.fwdSide
local Dest_X, Dest_Z, MaxThrust, PilotEnable =
    config.Dest_X, config.Dest_Z, config.MaxThrust, config.PilotEnable
local saveSettings
local autopilotSwitch
local destinationXLabel
local destinationZLabel
local maxThrustLabel
local maxThrustProgress
local destinationDistanceLabel
local arrivedLabel
local autopilotState = basalt.state(PilotEnable)
local currentPage = basalt.state(1)
local selectedAngle
local telemetryState

local nav = terminalRoot:addFrame({
    x = 1,
    y = 1,
    width = navWidth,
    height = basalt.fill(),
    background = colors.gray,
})

local content = terminalRoot:addFrame({
    x = navWidth + 1,
    y = 1,
    width = basalt.fill(),
    height = basalt.fill(),
    background = colors.black,
})

local graphPage = content:addFrame({
    width = basalt.percent(1),
    height = basalt.percent(1),
    background = colors.black,
})

local settingsPage = content:addFrame({
    width = basalt.percent(1),
    height = basalt.percent(1),
    background = colors.black,
    visible = false,
})

local autopilotPage = content:addFrame({
    width = basalt.percent(1),
    height = basalt.percent(1),
    background = colors.black,
    visible = false,
})

autopilotPage:addLabel({
    x = 2,
    y = 2,
    text = "AutoPilot",
    foreground = colors.orange,
})

autopilotPage:addLabel({
    x = 2,
    y = 4,
    text = "Pilot Enable",
    foreground = colors.white,
})

autopilotSwitch = autopilotPage:addSwitch({
    x = 27,
    y = 4,
    width = 6,
    height = 1,
    checked = PilotEnable,
}):onChange(function()
    local visible = autopilotSwitch.checked
    destinationXLabel.visible = visible
    destinationZLabel.visible = visible
    maxThrustLabel.visible = visible
    maxThrustProgress.visible = visible
    destinationDistanceLabel.visible = visible
    arrivedLabel.visible = visible and arrivedLabel.visible

    if not autopilotSwitch.checked and relay then
        relay.setOutput(CW_SIDE, false)
        relay.setOutput(CCW_SIDE, false)
        relay.setOutput(FWD_SIDE, false)
    end

    autopilotState:update(function()
        return autopilotSwitch.checked
    end)
    saveSettings()
end)

autopilotPage:addLabel({
    x = 2,
    y = 6,
    text = "Destination X",
    foreground = colors.white,
})

local destXInput = autopilotPage:addInput({
    x = 27,
    y = 6,
    width = 10,
    text = tostring(Dest_X),
})

autopilotPage:addLabel({
    x = 2,
    y = 8,
    text = "Destination Z",
    foreground = colors.white,
})

local destZInput = autopilotPage:addInput({
    x = 27,
    y = 8,
    width = 10,
    text = tostring(Dest_Z),
})

autopilotPage:addLabel({
    x = 2,
    y = 10,
    text = "MaxThrust",
    foreground = colors.white,
})

local maxThrustSlider = autopilotPage:addSlider({
    x = 27,
    y = 10,
    width = 11,
    min = 0,
    max = 15,
    step = 1,
    value = MaxThrust,
})

autopilotPage:addButton({
    x = 29,
    y = 2,
    width = 8,
    height = 1,
    text = "Save",
    background = colors.green,
}):onClick(function()
    saveSettings()
end)

graphPage:addLabel({
    x = 2,
    y = 2,
    text = "Heading",
    foreground = colors.orange,
})

local headingLabel = graphPage:addLabel({
    x = 8,
    y = 3,
    width = 17,
    text = "--",
    foreground = colors.white,
})

graphPage:addLabel({
    x = imageSize + 3,
    y = 2,
    text = "Status",
    foreground = colors.orange,
})

local positionXLabel = graphPage:addLabel({
    x = imageSize + 3,
    y = 3,
    width = 20,
    text = "CurrentPos_X: --",
    foreground = colors.white,
})

local positionZLabel = graphPage:addLabel({
    x = imageSize + 3,
    y = 4,
    width = 20,
    text = "CurrentPos_Z: --",
    foreground = colors.white,
})

local altitudeLabel = graphPage:addLabel({
    x = imageSize + 3,
    y = 5,
    width = 20,
    text = "Altitude: --",
    foreground = colors.white,
})

local speedLabel = graphPage:addLabel({
    x = imageSize + 3,
    y = 6,
    width = 20,
    text = "Speed: --",
    foreground = colors.white,
})

local pressureLabel = graphPage:addLabel({
    x = imageSize + 3,
    y = 7,
    width = 20,
    text = "Pressure: --",
    foreground = colors.white,
})

local autopilotStatusLabel = graphPage:addLabel({
    x = imageSize + 3,
    y = 9,
    width = 20,
})
autopilotStatusLabel.text = autopilotState:map(function(enabled)
    return enabled and "AutoPilot: enabled" or "AutoPilot: disabled"
end)
autopilotStatusLabel.foreground = autopilotState:map(function(enabled)
    return enabled and colors.green or colors.red
end)

destinationXLabel = graphPage:addLabel({
    x = imageSize + 3,
    y = 10,
    width = 30,
    text = "Destination_X: --",
    visible = PilotEnable,
})

destinationZLabel = graphPage:addLabel({
    x = imageSize + 3,
    y = 11,
    width = 30,
    text = "Destination_Z: --",
    visible = PilotEnable,
})

maxThrustLabel = graphPage:addLabel({
    x = imageSize + 3,
    y = 12,
    width = 30,
    text = "MaxThrust: --",
    visible = PilotEnable,
})

maxThrustProgress = graphPage:addProgressBar({
    x = imageSize + 3,
    y = 13,
    width = 18,
    progress = MaxThrust / 15 * 100,
    visible = PilotEnable,
})

destinationDistanceLabel = graphPage:addLabel({
    x = imageSize + 3,
    y = 14,
    width = 30,
    text = "Distance: --",
    visible = PilotEnable,
})

arrivedLabel = graphPage:addLabel({
    x = imageSize + 3,
    y = 15,
    width = 30,
    text = "Arrived",
    foreground = colors.green,
    visible = false,
})

graphPage:addLabel({
    x = imageSize + 3,
    y = 17,
    width = 20,
    text = monitor and "Monitor: connected" or "Monitor: not found",
    foreground = monitor and colors.green or colors.red,
})

graphPage:addLabel({
    x = imageSize + 3,
    y = 18,
    width = 20,
    text = relay and "Relay: connected" or "Relay: not found",
    foreground = relay and colors.green or colors.red,
})

local sourceImages = {
    [0] = {
        animated = false,
        width = 16,
        height = 16,
        [1] = {
            { "                ", "                ", "      0000      " },
            { "                ", "                ", "    00    00    " },
            { "                ", "                ", "   0   0    0   " },
            { "                ", "                ", "  0    0     0  " },
            { "                ", "                ", " 0    000     0 " },
            { "                ", "                ", " 0    000     0 " },
            { "                ", "                ", "0     0 0      0" },
            { "                ", "                ", "0    00 00     0" },
            { "                ", "                ", "0    0   0     0" },
            { "                ", "                ", "0   00   00    0" },
            { "                ", "                ", " 0  0     0   0 " },
            { "                ", "                ", " 0            0 " },
            { "                ", "                ", "  0          0  " },
            { "                ", "                ", "   0        0   " },
            { "                ", "                ", "    00    00    " },
            { "                ", "                ", "      0000      " }
        }
    },
    [1] = {
        animated = false,
        width = 16,
        height = 16,
        [1] = {
            { "                ", "                ", "      0000      " },
            { "                ", "                ", "    00    00    " },
            { "                ", "                ", "   0     0  0   " },
            { "                ", "                ", "  0     00   0  " },
            { "                ", "                ", " 0     000    0 " },
            { "                ", "                ", " 0    0000    0 " },
            { "                ", "                ", "0     0000     0" },
            { "                ", "                ", "0    00000     0" },
            { "                ", "                ", "0   0   00     0" },
            { "                ", "                ", "0  0    00     0" },
            { "                ", "                ", " 0       0    0 " },
            { "                ", "                ", " 0       0    0 " },
            { "                ", "                ", "  0          0  " },
            { "                ", "                ", "   0        0   " },
            { "                ", "                ", "    00    00    " },
            { "                ", "                ", "      0000      " }
        }
    },
    [2] = {
        animated = false,
        width = 16,
        height = 16,
        [1] = {
            { "                ", "                ", "      0000      " },
            { "                ", "                ", "    00    00    " },
            { "                ", "                ", "   0        0   " },
            { "                ", "                ", "  0       0  0  " },
            { "                ", "                ", " 0       00   0 " },
            { "                ", "                ", " 0     000    0 " },
            { "                ", "                ", "0     0000     0" },
            { "                ", "                ", "0   00  0      0" },
            { "                ", "                ", "0  0    0      0" },
            { "                ", "                ", "0      00      0" },
            { "                ", "                ", " 0     0      0 " },
            { "                ", "                ", " 0     0      0 " },
            { "                ", "                ", "  0          0  " },
            { "                ", "                ", "   0        0   " },
            { "                ", "                ", "    00    00    " },
            { "                ", "                ", "      0000      " }
        }
    },
    [3] = {
        animated = false,
        width = 16,
        height = 16,
        [1] = {
            { "                ", "                ", "      0000      " },
            { "                ", "                ", "    00    00    " },
            { "                ", "                ", "   0        0   " },
            { "                ", "                ", "  0          0  " },
            { "                ", "                ", " 0         0  0 " },
            { "                ", "                ", " 0      000   0 " },
            { "                ", "                ", "0    000000    0" },
            { "                ", "                ", "0  00   00     0" },
            { "                ", "                ", "0      00      0" },
            { "                ", "                ", "0      0       0" },
            { "                ", "                ", " 0    00      0 " },
            { "                ", "                ", " 0    0       0 " },
            { "                ", "                ", "  0          0  " },
            { "                ", "                ", "   0        0   " },
            { "                ", "                ", "    00    00    " },
            { "                ", "                ", "      0000      " }
        }
    },
    [4] = {
        animated = false,
        width = 16,
        height = 16,
        [1] = {
            { "                ", "                ", "      0000      " },
            { "                ", "                ", "    00    00    " },
            { "                ", "                ", "   0        0   " },
            { "                ", "                ", "  0          0  " },
            { "                ", "                ", " 0            0 " },
            { "                ", "                ", " 0 00000  000 0 " },
            { "                ", "                ", "0     000000   0" },
            { "                ", "                ", "0       000    0" },
            { "                ", "                ", "0      00      0" },
            { "                ", "                ", "0      0       0" },
            { "                ", "                ", " 0    0       0 " },
            { "                ", "                ", " 0   0        0 " },
            { "                ", "                ", "  0          0  " },
            { "                ", "                ", "   0        0   " },
            { "                ", "                ", "    00    00    " },
            { "                ", "                ", "      0000      " }
        }
    },
}

local function rotateImage(image)
    local rows = {}
    for y = 1, image.width do
        local channels = { "", "", "" }
        for x = 1, image.height do
            local sourceRow = image.height - x + 1
            for channel = 1, 3 do
                local source = image[1][sourceRow][channel]
                channels[channel] = channels[channel] .. source:sub(y, y)
            end
        end
        rows[y] = channels
    end

    return {
        animated = image.animated,
        width = image.height,
        height = image.width,
        [1] = rows,
    }
end

local images = {}
for quadrant = 0, 3 do
    for sourceIndex = 0, 4 do
        local image = sourceImages[sourceIndex]
        for _ = 1, quadrant do
            image = rotateImage(image)
        end
        images[quadrant * 5 + sourceIndex] = image
    end
end
local directions = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

local imageViewer = graphPage:addImage({
    x = 1,
    y = 4,
})
imageViewer.bimg = images[0]

local function readTelemetry()
    local pose = sublevel.getLastPose()
    local position = pose.position
    position.y = position.y + altitudeOffset
    local velocity = sublevel.getVelocity()
    local w, x, y, z = pose.orientation.a, pose.orientation.v.x, pose.orientation.v.y, pose.orientation.v.z
    local quaternionLength = math.sqrt(w * w + x * x + y * y + z * z)
    w, x, y, z = w / quaternionLength, x / quaternionLength, y / quaternionLength, z / quaternionLength

    local directionX = -2 * (x * z + w * y)
    local directionZ = 2 * (x * x + y * y) - 1
    local heading = (math.deg(math.atan2(directionX, -directionZ)) + angleOffset) % 360

    return {
        heading = heading,
        positionX = string.format("CurrentPos_X: %d", position.x),
        positionZ = string.format("CurrentPos_Z: %d", position.z),
        altitude = string.format("Altitude: %d m", position.y),
        speed = string.format("Speed: %.1f m/s", math.sqrt(velocity.x * velocity.x + velocity.z * velocity.z)),
        pressure = string.format("Pressure: %d%%", 100 * aero.getAirPressure(position)),
    }
end

telemetryState = basalt.state(readTelemetry())

positionXLabel.text = telemetryState:map(function(data)
    return data.positionX
end)
positionZLabel.text = telemetryState:map(function(data)
    return data.positionZ
end)
altitudeLabel.text = telemetryState:map(function(data)
    return data.altitude
end)
speedLabel.text = telemetryState:map(function(data)
    return data.speed
end)
pressureLabel.text = telemetryState:map(function(data)
    return data.pressure
end)

local function refreshTelemetry()
    local telemetry = readTelemetry()
    telemetryState:update(function()
        return telemetry
    end)

    local heading = telemetry.heading
    local imageIndex = math.floor(heading / 18 + 0.5) % 20
    if selectedAngle ~= imageIndex then
        imageViewer.bimg = images[imageIndex]
        selectedAngle = imageIndex
    end

    local directionIndex = math.floor((heading + 22.5) / 45) % #directions + 1
    headingLabel.text = directions[directionIndex]
    if autopilotSwitch.checked then
        local position = sublevel.getLastPose().position
        local deltaX = Dest_X - position.x
        local deltaZ = Dest_Z - position.z
        local rotation = (math.deg(math.atan2(deltaX, -deltaZ)) - heading + 180) % 360 - 180
        local rotationMagnitude = math.abs(rotation)
        local distance = math.sqrt(deltaX * deltaX + deltaZ * deltaZ)
        destinationXLabel.text = string.format("Destination_X: %d", Dest_X)
        destinationZLabel.text = string.format("Destination_Z: %d", Dest_Z)
        maxThrustLabel.text = string.format("MaxThrust: %d / 15", MaxThrust)
        maxThrustProgress.progress = MaxThrust / 15 * 100
        destinationDistanceLabel.text = string.format("Distance: %.1f m", distance)
        arrivedLabel.visible = distance <= 50

        if relay then
            if distance > 50 then
                relay.setAnalogOutput(rotation < 0 and CCW_SIDE or CW_SIDE,
                    rotationMagnitude > 90 and 15 or rotationMagnitude * 0.166)
                if distance > 500 then
                    relay.setAnalogOutput(FWD_SIDE, MaxThrust)
                else
                    relay.setAnalogOutput(FWD_SIDE, MaxThrust * (distance / 500))
                end
            else
                relay.setOutput(CW_SIDE, false)
                relay.setOutput(CCW_SIDE, false)
                relay.setOutput(FWD_SIDE, false)
            end
        end
    end
end

settingsPage:addLabel({
    x = 2,
    y = 2,
    text = "Settings",
    foreground = colors.orange,
})

settingsPage:addLabel({
    x = 2,
    y = 4,
    text = "Angle correction",
    foreground = colors.white,
})

local angleDropdown = settingsPage:addDropdown({
    x = 27,
    y = 4,
    width = 10,
    text = "+" .. angleOffset,
})

local pendingAngleOffset = angleOffset
for _, offset in ipairs(angleOffsets) do
    angleDropdown:addItem({
        text = "+" .. offset,
        value = offset,
        selected = offset == angleOffset,
    })
end

angleDropdown:onSelect(function(_, _, item)
    pendingAngleOffset = item.value
end)

settingsPage:addLabel({
    x = 2,
    y = 6,
    text = "Altitude correction (m)",
    foreground = colors.white,
})

local altitudeOffsetInput = settingsPage:addInput({
    x = 27,
    y = 6,
    width = 10,
    text = tostring(altitudeOffset),
    placeholder = "Altitude offset",
})

local pendingSides = {
    cwSide = CW_SIDE,
    ccwSide = CCW_SIDE,
    fwdSide = FWD_SIDE,
}

local function addSideDropdown(label, y, key)
    local selectedSide = pendingSides[key]
    settingsPage:addLabel({
        x = 2,
        y = y,
        text = label,
        foreground = colors.white,
    })

    local dropdown = settingsPage:addDropdown({
        x = 27,
        y = y,
        width = 10,
        text = selectedSide,
    })

    for _, side in ipairs(sides) do
        dropdown:addItem({
            text = side,
            value = side,
            selected = side == selectedSide,
        })
    end

    dropdown:onSelect(function(_, _, item)
        pendingSides[key] = item.value
    end)
end

addSideDropdown("CW_SIDE", 8, "cwSide")
addSideDropdown("CCW_SIDE", 10, "ccwSide")
addSideDropdown("FWD_SIDE", 12, "fwdSide")

saveSettings = function()
    local newAltitudeOffset, altitudeError = parseNumberInput(
        altitudeOffsetInput.text,
        "altitude correction"
    )
    if not newAltitudeOffset then
        toast:error(altitudeError)
        return
    end

    local newDestX, destXError = parseNumberInput(destXInput.text, "Destination X", true)
    if not newDestX then
        toast:error(destXError)
        return
    end

    local newDestZ, destZError = parseNumberInput(destZInput.text, "Destination Z", true)
    if not newDestZ then
        toast:error(destZError)
        return
    end

    local newConfig = {
        angleOffset = pendingAngleOffset,
        altitudeOffset = newAltitudeOffset,
        cwSide = pendingSides.cwSide,
        ccwSide = pendingSides.ccwSide,
        fwdSide = pendingSides.fwdSide,
        Dest_X = newDestX,
        Dest_Z = newDestZ,
        MaxThrust = maxThrustSlider.value,
        PilotEnable = autopilotSwitch.checked,
    }
    local saved, saveError = saveConfig(newConfig)
    if not saved then
        toast:error(saveError)
        return
    end

    angleOffset, altitudeOffset = newConfig.angleOffset, newConfig.altitudeOffset
    CW_SIDE, CCW_SIDE, FWD_SIDE = newConfig.cwSide, newConfig.ccwSide, newConfig.fwdSide
    Dest_X, Dest_Z, MaxThrust, PilotEnable =
        newConfig.Dest_X, newConfig.Dest_Z, newConfig.MaxThrust, newConfig.PilotEnable
    refreshTelemetry()
    toast:success("Settings saved.")
end

settingsPage:addButton({
    x = 29,
    y = 2,
    width = 8,
    height = 1,
    text = "Save",
    background = colors.green,
}):onClick(saveSettings)

local pages = { graphPage, settingsPage, autopilotPage }
local navButtons = {}

local function showPage(index)
    for i, page in ipairs(pages) do
        page.visible = i == index
    end
    for i, button in ipairs(navButtons) do
        button.background = i == index and colors.blue or colors.gray
    end
end

navButtons[1] = nav:addButton({
    x = 2,
    y = 3,
    width = 10,
    height = 1,
    text = "Overview",
}):onClick(function()
    currentPage:set(1)
end)

navButtons[2] = nav:addButton({
    x = 2,
    y = 7,
    width = 10,
    height = 1,
    text = "Settings",
}):onClick(function()
    currentPage:set(2)
end)

navButtons[3] = nav:addButton({
    x = 2,
    y = 11,
    width = 10,
    height = 1,
    text = "AutoPilot",
}):onClick(function()
    currentPage:set(3)
end)

nav:addButton({
    x = 2,
    y = 15,
    width = 10,
    height = 1,
    text = "Exit",
    background = colors.red,
}):onClick(function()
    if relay then
    for _, side in ipairs(sides) do
        relay.setOutput(side, false)
    end
end
    basalt.stop()
end)

currentPage:subscribe(showPage, true)
refreshTelemetry()

parallel.waitForAny(function()
    basalt.run()
end, function()
    while true do
        sleep(0.2)
        refreshTelemetry()
    end
end)
