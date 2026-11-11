local basalt = require("basalt")
local imageLib = basalt.use("image")

local terminalRoot = basalt.getMainFrame()
terminalRoot.background = colors.black

local navWidth = 13
local imageSize = 16
local angleOffset = 0
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

graphPage:addLabel({
    x = 2,
    y = 2,
    text = "XZ Heading",
    foreground = colors.orange,
})

local headingLabel = graphPage:addLabel({
    x = 1,
    y = 3,
    width = 17,
    text = "Heading: --",
    foreground = colors.white,
})

graphPage:addLabel({
    x = imageSize + 3,
    y = 2,
    text = "Position / motion",
    foreground = colors.orange,
})

local positionXLabel = graphPage:addLabel({
    x = imageSize + 3,
    y = 3,
    width = 20,
    text = "X: --",
    foreground = colors.white,
})

local positionZLabel = graphPage:addLabel({
    x = imageSize + 3,
    y = 4,
    width = 20,
    text = "Z: --",
    foreground = colors.white,
})

local altitudeLabel = graphPage:addLabel({
    x = imageSize + 3,
    y = 5,
    width = 20,
    text = "Y: --",
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

local images = {}
for index = 0, 19 do
    images[index] = imageLib.load(fs.combine(shell.dir(), string.format("assets/arrow_%03d.bimg", index * 18)))
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
    local velocity = sublevel.getVelocity()
    local w, x, y, z = pose.orientation.a, pose.orientation.v.x, pose.orientation.v.y, pose.orientation.v.z
    local quaternionLength = math.sqrt(w * w + x * x + y * y + z * z)
    if quaternionLength == 0 then
        error("sublevel.getLastPose() returned a zero-length quaternion")
    end
    w, x, y, z = w / quaternionLength, x / quaternionLength, y / quaternionLength, z / quaternionLength

    local directionX = -2 * (x * z + w * y)
    local directionZ = 2 * (x * x + y * y) - 1
    local heading
    if directionX * directionX + directionZ * directionZ >= 0.000000000001 then
        heading = math.deg(math.atan2(directionX, -directionZ))
        heading = (heading + angleOffset) % 360
    end

    return {
        heading = heading,
        positionX = string.format("X: %.2f", position.x),
        positionZ = string.format("Z: %.2f", position.z),
        altitude = string.format("Y: %.2f", position.y),
        speed = string.format("Speed: %.2f", math.sqrt(velocity.x * velocity.x + velocity.z * velocity.z)),
        pressure = string.format("Pressure: %.3f", aero.getAirPressure(position)),
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
    if not heading then
        headingLabel.text = "Heading: unavailable"
        imageViewer.visible = false
        selectedAngle = nil
        return
    end

    local imageIndex = math.floor(heading / 18 + 0.5) % 20
    if selectedAngle ~= imageIndex then
        imageViewer.bimg = images[imageIndex]
        selectedAngle = imageIndex
    end

    imageViewer.visible = true
    local directionIndex = math.floor((heading + 22.5) / 45) % #directions + 1
    headingLabel.text = "Heading: " .. directions[directionIndex]
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
    text = "Coordinate angle correction",
    foreground = colors.white,
})

local angleOffsets = { 0, 90, 180, 270 }
local angleDropdown = settingsPage:addDropdown({
    x = 2,
    y = 6,
    width = 16,
    text = "+0",
})

for i, offset in ipairs(angleOffsets) do
    angleDropdown:addItem({
        text = "+" .. offset,
        value = offset,
        selected = i == 1,
    })
end

angleDropdown:onSelect(function(_, _, item)
    angleOffset = item.value
    refreshTelemetry()
end)

local pages = { graphPage, settingsPage }
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
    height = 2,
    text = "XZ Graph",
}):onClick(function()
    currentPage:set(1)
end)

navButtons[2] = nav:addButton({
    x = 2,
    y = 7,
    width = 10,
    height = 2,
    text = "Settings",
}):onClick(function()
    currentPage:set(2)
end)

nav:addButton({
    x = 2,
    y = 15,
    width = 10,
    height = 2,
    text = "Exit",
    background = colors.red,
}):onClick(function()
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
