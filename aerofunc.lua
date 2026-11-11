sublevel.getLastPose()
--[[
테이블을 반환
{
    orientation = {
    a = number, -- quaternion w
    v = {
        x = number, -- quaternion x
        y = number, -- quaternion y
        z = number, -- quaternion z
        }
    }
    position = {
        x = number, -- position x
        y = number, -- position y
        z = number, -- position z
    }
}
]]
sublevel.getVelocity()
--[[
테이블을 반환
{
    x = number, -- velocity x
    y = number, -- velocity y
    z = number, -- velocity z
}
]]