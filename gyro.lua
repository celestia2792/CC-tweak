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
local relay = peripheral.wrap("redstone_relay_5")
local relay2 = peripheral.wrap("redstone_relay_7")

local UPDATE_INTERVAL = 0.05
local REFERENCE_PRESSURE = 0.4091
local X_PID = {
    kp = 0.01,
    ki = 0.01,
    kd = 0.5,
    integralLimit = 15,
}
local Z_PID = {
    kp = 0.03,
    ki = 0.015,
    kd = 0.5,
    integralLimit = 50,
}
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
    kd,
    integralLimit
)
    local error = -angle
    local nextIntegral = integral
    if integrate then
        nextIntegral = clamp(
            integral + error * UPDATE_INTERVAL,
            -integralLimit,
            integralLimit
        )
    end

    local control = kp * error + ki * nextIntegral - kd * angularVelocity
    return control, nextIntegral, error
end

local function getPressureScale(position)
    local pressure = aero.getAirPressure(position)
    if type(pressure) ~= "number" or pressure <= 0 then
        error("Aero returned an invalid air pressure")
    end
    return REFERENCE_PRESSURE / pressure
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

local function setEngine(side, demand)
    local reversed = demand < 0
    local magnitude = clamp(math.abs(demand), 0, 1)

    relay2.setOutput(side, reversed)
    relay.setAnalogOutput(
        side,
        15 - math.floor(magnitude * 15 + 0.5)
    )
end

local function applyControls(
    xControl,
    zControl
)
    local center = sublevel.getCenterOfMass()
    if type(center) ~= "table" then
        error("Sublevel returned an invalid center of mass")
    end

    local maxRightArm = 0
    local maxForwardArm = 0

    for index, engine in ipairs(engines) do
        local deltaX = engine.position.x - center.x
        local deltaZ = engine.position.z - center.z
        local rightArm = -1 * deltaX
        local forwardArm = -1 * deltaZ

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

while true do
    local pose = sublevel.getLastPose()
    local xAngle, zAngle, xRate, zRate =
        readAttitudeAndRates(pose)
    local pressureScale = getPressureScale(pose.position)
    local xControl, nextXIntegral, xError =
        pid(
            xAngle,
            xRate,
            xIntegral,
            true,
            X_PID.kp * pressureScale,
            X_PID.ki * pressureScale,
            X_PID.kd * pressureScale,
            X_PID.integralLimit
        )
    local zControl, nextZIntegral, zError =
        pid(
            zAngle,
            zRate,
            zIntegral,
            true,
            Z_PID.kp * pressureScale,
            Z_PID.ki * pressureScale,
            Z_PID.kd * pressureScale,
            Z_PID.integralLimit
        )

    if math.abs(xControl) + math.abs(zControl) > 1 then
        if xControl * xError > 0 then
            xControl, nextXIntegral =
                pid(
                    xAngle,
                    xRate,
                    xIntegral,
                    false,
                    X_PID.kp * pressureScale,
                    X_PID.ki * pressureScale,
                    X_PID.kd * pressureScale,
                    X_PID.integralLimit
                )
        end
        if zControl * zError > 0 then
            zControl, nextZIntegral =
                pid(
                    zAngle,
                    zRate,
                    zIntegral,
                    false,
                    Z_PID.kp * pressureScale,
                    Z_PID.ki * pressureScale,
                    Z_PID.kd * pressureScale,
                    Z_PID.integralLimit
                )
        end
    end

    xIntegral = nextXIntegral
    zIntegral = nextZIntegral
    applyControls(
        xControl,
        zControl
    )
    sleep(UPDATE_INTERVAL)
end
