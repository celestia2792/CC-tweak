local basalt = require("basalt")

local frame = basalt.getMainFrame()
frame.background = colors.black

local timeLabel = frame:addLabel({
    x = 2,
    y = 2,
})

local lastLoad = frame:addLabel({
    x = 2,
    y = 1,
})

lastLoad.text = "Booted at Day" .. os.day() .. " / " .. textutils.formatTime(os.time())

basalt.schedule(function ()
    while true do
        timeLabel.text = "Now time: Day" .. os.day() .. " / " .. textutils.formatTime(os.time())
        sleep(1)
    end
end)

basalt.run()