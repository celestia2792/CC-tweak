local function getRotationAngle(w, x, y, z, cx, cz, tx, tz)
    local current_dir_x = -2 * (x * z + w * y)
    local current_dir_z = 2 * (x * x + y * y) - 1
    
    local current_yaw = math.atan2(current_dir_x, -current_dir_z)
    
    local dx = tx - cx
    local dz = tz - cz
    
    local target_yaw = math.atan2(dx, -dz)
    
    local diff_rad = target_yaw - current_yaw
    local diff_deg = math.deg(diff_rad)
    
    local rotation_angle = (diff_deg + 180) % 360 - 180
    local direction = rotation_angle >= 0 and "right" or "top"
    local abs_angle = math.abs(rotation_angle)
    if abs_angle > 90 then
        signal = 15
    else
        signal = abs_angle*0.166
    end
    return {direction, signal}
end
 
 
local dest_x = tonumber(read())
local dest_z = tonumber(read())

local pos = sublevel.getLastPose()
print(unpack(getRotationAngle(pos.orientation.a, pos.orientation.v.x, pos.orientation.v.y, pos.orientation.v.z, pos.position.x, pos.position.z, dest_x, dest_z)))
