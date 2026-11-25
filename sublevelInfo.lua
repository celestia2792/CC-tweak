local UPDATE_INTERVAL = 0.2

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function normalizeQuaternion(orientation)
    local w, x, y, z = orientation.a, orientation.v.x, orientation.v.y, orientation.v.z
    local length = math.sqrt(w * w + x * x + y * y + z * z)
    if length < 1e-12 then
        error("Sublevel returned an invalid orientation")
    end
    return w / length, x / length, y / length, z / length
end

local function readValues()
    local pose = assert(sublevel.getLastPose(), "Pose unavailable")
    local w, x, y, z = normalizeQuaternion(pose.orientation)

    local pitch = math.asin(clamp(2 * (w * x - y * z), -1, 1))
    local roll = -math.atan2(
        2 * (w * z + x * y),
        1 - 2 * (x * x + z * z)
    )

    local upX = 2 * (x * y + z * w)
    local upY = 1 - 2 * (x * x + z * z)
    local upZ = 2 * (y * z - x * w)
    local levelPitch = -math.atan2(upZ, upY)
    local levelRoll = math.atan2(upX, upY)

    local directionX = -2 * (x * z + w * y)
    local directionZ = 2 * (x * x + y * y) - 1
    local heading = math.deg(math.atan2(directionX, -directionZ))
    heading = (heading + 360) % 360

    local velocity = sublevel.getVelocity()
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

    return {
        pitch = math.deg(pitch),
        roll = math.deg(roll),
        levelPitch = math.deg(levelPitch),
        levelRoll = math.deg(levelRoll),
        heading = heading,
        upX = upX,
        upY = upY,
        upZ = upZ,
        vx = velocity.x,
        vy = velocity.y,
        vz = velocity.z,
        ax = angularVelocity.x,
        ay = angularVelocity.y,
        az = angularVelocity.z,
        pitchRate = pitchRate,
        rollRate = rollRate,
        position = pose.position,
    }
end

local baseline = readValues()
local nextOutput = os.clock()

term.setTextColor(colors.white)
print("Hold the airship at one level heading to establish the baseline.")
print("Then test only yaw, only pitch, and only roll.")

while true do
    if os.clock() >= nextOutput then
        local current = readValues()
        term.clear()
        term.setCursorPos(1, 1)

        print("GYRO AXIS TEST")
        print(string.format(
            "X-axis angle: %7.2f deg  Z-axis angle: %7.2f deg",
            current.pitch,
            current.roll
        ))
        print(string.format(
            "World-up X angle: %7.2f deg  Z angle: %7.2f deg",
            current.levelPitch,
            current.levelRoll
        ))
        print(string.format(
            "Heading: %7.2f deg  delta: %+7.2f deg",
            current.heading,
            ((current.heading - baseline.heading + 540) % 360) - 180
        ))
        print(string.format(
            "Delta X angle: %+7.2f deg  Z angle: %+7.2f deg",
            current.pitch - baseline.pitch,
            current.roll - baseline.roll
        ))
        print(string.format(
            "World-up X/Y/Z: %+.3f / %+.3f / %+.3f",
            current.upX,
            current.upY,
            current.upZ
        ))
        print(string.format(
            "Angular X/Y/Z: %+.3f / %+.3f / %+.3f",
            current.ax,
            current.ay,
            current.az
        ))
        print(string.format(
            "X/Z axis rate: %+.3f / %+.3f",
            current.pitchRate,
            current.rollRate
        ))
        print(string.format(
            "Position X/Y/Z: %.1f / %.1f / %.1f",
            current.position.x,
            current.position.y,
            current.position.z
        ))
        print(string.format(
            "Velocity X/Y/Z: %+.2f / %+.2f / %+.2f",
            current.vx,
            current.vy,
            current.vz
        ))

        term.setCursorPos(1, 13)
        print("Tests:")
        print("1. Yaw only: heading changes, X/Z axis angles should stay near 0.")
        print("2. X-axis tilt: X angle and world-up X angle should change together.")
        print("3. Z-axis tilt: Z angle and world-up Z angle should change together.")

        nextOutput = os.clock() + UPDATE_INTERVAL
    end
    sleep(UPDATE_INTERVAL)
end