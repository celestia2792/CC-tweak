local ENGINE_1 = "right" -- forward/left
local ENGINE_2 = "left" -- forward/right
local ENGINE_3 = "back" -- backward/left
local ENGINE_4 = "front" -- backward/right
local relay = assert(peripheral.wrap("redstone_relay_5"), "redstone_relay_5 not found")

local UPDATE_INTERVAL = 0.05
local KP = 0.04
local KI = 0.01
local KD = 0.5
local INTEGRAL_LIMIT = 40
local sides = { ENGINE_1, ENGINE_2, ENGINE_3, ENGINE_4 }
local pitchIntegral, rollIntegral = 0, 0

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function pid(angle, angularVelocity, integral, dt, integrate)
    local error = -angle
    local nextIntegral = integral
    if integrate then
        nextIntegral = clamp(
            integral + error * dt,
            -INTEGRAL_LIMIT,
            INTEGRAL_LIMIT
        )
    end

    local control = KP * error + KI * nextIntegral - KD * angularVelocity
    return control, nextIntegral, error
end

local function readAttitudeAndRates()
    local orientation = sublevel.getLastPose().orientation
    local w, x, y, z = orientation.a, orientation.v.x, orientation.v.y, orientation.v.z
    local length = math.sqrt(w * w + x * x + y * y + z * z)
    if length < 1e-12 then
        error("Sublevel returned an invalid orientation")
    end
    w, x, y, z = w / length, x / length, y / length, z / length

    local pitch = math.asin(clamp(2 * (w * x - y * z), -1, 1))
    local roll = -math.atan2(2 * (w * z + x * y), 1 - 2 * (x * x + z * z))

    local angularVelocity = sublevel.getAngularVelocity()
    local pitchRate =
        (1 - 2 * (y * y + z * z)) * angularVelocity.x
        + 2 * (x * y + w * z) * angularVelocity.y
        + 2 * (x * z - w * y) * angularVelocity.z
    local rollRate = -(
        2 * (x * z + w * y) * angularVelocity.x
        + 2 * (y * z - w * x) * angularVelocity.y
        + (1 - 2 * (x * x + y * y)) * angularVelocity.z
    )

    return math.deg(pitch), math.deg(roll), pitchRate, rollRate
end

local function stopEngines()
    for _, side in ipairs(sides) do
        relay.setAnalogOutput(side, 15)
    end
end

local function setEngine(side, demand)
    demand = clamp(demand, 0, 1)
    relay.setAnalogOutput(side, 15 - math.floor(demand * 15 + 0.5))
end

local function applyControls(pitchControl, rollControl)
    local scale = math.max(1, math.abs(pitchControl) + math.abs(rollControl))
    pitchControl = pitchControl / scale
    rollControl = rollControl / scale

    setEngine(ENGINE_1, pitchControl + rollControl)
    setEngine(ENGINE_2, pitchControl - rollControl)
    setEngine(ENGINE_3, -pitchControl + rollControl)
    setEngine(ENGINE_4, -pitchControl - rollControl)
end

stopEngines()
assert(sublevel.isInPlotGrid(), "This computer is not on a Sable sublevel")

local ok, err = pcall(function()
    while true do
        local pitch, roll, pitchRate, rollRate = readAttitudeAndRates()
        local pitchControl, nextPitchIntegral, pitchError =
            pid(pitch, pitchRate, pitchIntegral, UPDATE_INTERVAL, true)
        local rollControl, nextRollIntegral, rollError =
            pid(roll, rollRate, rollIntegral, UPDATE_INTERVAL, true)

        if math.abs(pitchControl) + math.abs(rollControl) > 1 then
            if pitchControl * pitchError > 0 then
                pitchControl, nextPitchIntegral =
                    pid(pitch, pitchRate, pitchIntegral, UPDATE_INTERVAL, false)
            end
            if rollControl * rollError > 0 then
                rollControl, nextRollIntegral =
                    pid(roll, rollRate, rollIntegral, UPDATE_INTERVAL, false)
            end
        end

        pitchIntegral = nextPitchIntegral
        rollIntegral = nextRollIntegral
        applyControls(pitchControl, rollControl)
        sleep(UPDATE_INTERVAL)
    end
end)

stopEngines()
if not ok then
    error(err, 0)
end
