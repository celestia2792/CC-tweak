local BOX_SIDE = "bottom"
local CRAFTER_SIDE = "left"
local RETURN_SIDE = "up"
local CRAFTER_SIZE = "25" --5x5 size

local box = peripheral.wrap(BOX_SIDE)
 
local function DoCraft()
    local craftSize = #box.list()
    local str = box.getItemDetail(craftSize).displayName
    for i = 1, 25 do
        local craftData = string.byte(str, i) - 48
        if craftData ~= 0 then
            box.pushItems(CRAFTER_SIDE, craftData, 1, i)
        end
    end
    redstone.setOutput(CRAFTER_SIDE, true)
    sleep(1)
    redstone.setOutput(CRAFTER_SIDE, false)
    box.pushItems(RETURN_SIDE, craftSize)
    sleep(5)
end
 
while true do
    sleep(0.5)
    if #box.list() ~= 0 then DoCraft() end
end
