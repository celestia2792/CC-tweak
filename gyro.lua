local ENGINE_1 = {
    side = "right",
    position = {x = 20480943, y = 136, z = 20481047},
}
local ENGINE_2 = {
    side = "left",
    position = {x = 20480943, y = 136, z = 20481015},
}
local ENGINE_3 = {
    side = "back",
    position = {x = 20481040, y = 136, z = 20481047},
}
local ENGINE_4 = {
    side = "front",
    position = {x = 20481040, y = 136, z = 20481015},
}
local relay = assert(peripheral.wrap("redstone_relay_5"), "redstone_relay_5 not found")
local relay2 = assert(peripheral.wrap("redstone_relay_7"), "redstone_relay_7 not found")

local UPDATE_INTERVAL = 0.05
local KP = 0.04
local REFERENCE_KI = 0.01
local REFERENCE_PRESSURE = 0.4091
local KD = 0.5
local INTEGRAL_LIMIT = 40
local engines = { ENGINE_1, ENGINE_2, ENGINE_3, ENGINE_4 }
local xIntegral, zIntegral = 0, 0

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function pid(
    angle,
    angularVelocity,
    integral,
    integrate,
    kp,
    ki,
    kd
)
    local error = -angle
    local nextIntegral = integral
    if integrate then
        nextIntegral = clamp(
            integral + error * UPDATE_INTERVAL,
            -INTEGRAL_LIMIT,
            INTEGRAL_LIMIT
        )
    end

    local control = kp * error + ki * nextIntegral - kd * angularVelocity
    return control, nextIntegral, error
end

local function getCurrentGains(position)
    local pressure = aero.getAirPressure(position)
    if type(pressure) ~= "number" or pressure <= 0 then
        error("Aero returned an invalid air pressure")
    end
    local scale = REFERENCE_PRESSURE / pressure
    return KP * scale, REFERENCE_KI * scale, KD * scale
end

local function readAttitudeAndRates(pose)
    local orientation = pose.orientation
    local w, x, y, z = orientation.a, orientation.v.x, orientation.v.y, orientation.v.z
    local length = math.sqrt(w * w + x * x + y * y + z * z)
    if length < 1e-12 then
        error("Sublevel returned an invalid orientation")
    end
    w, x, y, z = w / length, x / length, y / length, z / length

    local xAngle = math.asin(clamp(2 * (w * x - y * z), -1, 1))
    local zAngle = -math.atan2(2 * (w * z + x * y), 1 - 2 * (x * x + z * z))

    local angularVelocity = sublevel.getAngularVelocity()
    local xRate =
        (1 - 2 * (y * y + z * z)) * angularVelocity.x
        + 2 * (x * y + w * z) * angularVelocity.y
        + 2 * (x * z - w * y) * angularVelocity.z
    local zRate = -(
        2 * (x * z + w * y) * angularVelocity.x
        + 2 * (y * z - w * x) * angularVelocity.y
        + (1 - 2 * (x * x + y * y)) * angularVelocity.z
    )

    return
        math.deg(xAngle),
        math.deg(zAngle),
        xRate,
        zRate,
        w,
        x,
        y,
        z
end
local function stopEngines()
    for _, engine in ipairs(engines) do
        relay2.setOutput(engine.side, false)
        relay.setAnalogOutput(engine.side, 15)
    end
end

local function setEngine(side, demand)
    local reversed = demand < 0
    local magnitude = clamp(math.abs(demand), 0, 1)

    relay2.setOutput(side, reversed)
    relay.setAnalogOutput(
        side,
        15 - math.floor(magnitude * 15 + 0.5)
    )
end

local function getBodyAxes(w, x, y, z)
    local forwardX = -2 * (x * z + w * y)
    local forwardZ = 2 * (x * x + y * y) - 1
    local forwardLength = math.sqrt(forwardX * forwardX + forwardZ * forwardZ)
    if forwardLength < 1e-12 then
        error("Unable to determine the airship forward axis")
    end
    forwardX = forwardX / forwardLength
    forwardZ = forwardZ / forwardLength

    local rightX = forwardZ
    local rightZ = -forwardX
    return rightX, rightZ, forwardX, forwardZ
end

local function applyControls(
    w,
    x,
    y,
    z,
    xControl,
    zControl
)
    local center = sublevel.getCenterOfMass()
    if type(center) ~= "table" then
        error("Sublevel returned an invalid center of mass")
    end

    local rightX, rightZ, forwardX, forwardZ =
        getBodyAxes(w, x, y, z)

    local maxRightArm = 0
    local maxForwardArm = 0

    for index, engine in ipairs(engines) do
        local deltaX = engine.position.x - center.x
        local deltaZ = engine.position.z - center.z
        local rightArm = deltaX * rightX + deltaZ * rightZ
        local forwardArm = deltaX * forwardX + deltaZ * forwardZ

        engine.rightArm = rightArm
        engine.forwardArm = forwardArm
        maxRightArm = math.max(maxRightArm, math.abs(rightArm))
        maxForwardArm = math.max(maxForwardArm, math.abs(forwardArm))
    end

    if maxRightArm < 1e-12 or maxForwardArm < 1e-12 then
        error("Engine layout does not provide independent X/Z torque axes")
    end

    local maxDemand = 0
    for index, engine in ipairs(engines) do
        local demand =
            zControl * engine.rightArm / maxRightArm
            + xControl * engine.forwardArm / maxForwardArm

        engine.demand = demand
        maxDemand = math.max(maxDemand, math.abs(demand))
    end

    local scale = math.max(1, maxDemand)
    for index, engine in ipairs(engines) do
        setEngine(engine.side, engine.demand / scale)
    end
end

stopEngines()
assert(sublevel.isInPlotGrid(), "This computer is not on a Sable sublevel")

local ok, err = pcall(function()
    while true do
        local pose = sublevel.getLastPose()
        local xAngle, zAngle, xRate, zRate, w, x, y, z =
            readAttitudeAndRates(pose)
        local kp, ki, kd = getCurrentGains(pose.position)
        local xControl, nextXIntegral, xError =
            pid(
                xAngle,
                xRate,
                xIntegral,
                true,
                kp,
                ki,
                kd
            )
        local zControl, nextZIntegral, zError =
            pid(
                zAngle,
                zRate,
                zIntegral,
                true,
                kp,
                ki,
                kd
            )

        if math.abs(xControl) + math.abs(zControl) > 1 then
            if xControl * xError > 0 then
                xControl, nextXIntegral =
                    pid(
                        xAngle,
                        xRate,
                        xIntegral,
                        false,
                        kp,
                        ki,
                        kd
                    )
            end
            if zControl * zError > 0 then
                zControl, nextZIntegral =
                    pid(
                        zAngle,
                        zRate,
                        zIntegral,
                        false,
                        kp,
                        ki,
                        kd
                    )
            end
        end

        xIntegral = nextXIntegral
        zIntegral = nextZIntegral
        applyControls(
            w,
            x,
            y,
            z,
            xControl,
            zControl
        )
        sleep(UPDATE_INTERVAL)
    end
end)

stopEngines()
if not ok then
    error(err, 0)
end
