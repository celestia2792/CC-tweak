local box = peripheral.wrap("bottom")
 
local function DoCraft()
    local craftSize = #box.list()
    local str = box.getItemDetail(craftSize).displayName
    for i = 1, 25 do
        local craftData = string.byte(str, i) - 48
        if craftData ~= 0 then
            box.pushItems("left", craftData, 1, i)
        end
    end
    redstone.setOutput("left", true)
    sleep(1)
    redstone.setOutput("left", false)
    box.pushItems("back", craftSize)
    sleep(5)
end
 
while true do
    sleep(0.5)
    if #box.list() ~= 0 then DoCraft() end
end
