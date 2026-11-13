local basalt = require("basalt")
basalt.use("bigfont")
local xml = basalt.use("xml")
local frame = basalt.getMainFrame()


local scope = {}

function scope.exit()
    basalt.stop()
end

local created = xml.loadFile(frame, fs.combine(shell.dir(), "ui/dashboard.xml"), scope)
local appShell = assert(created[1], "XML did not create an app shell")

dropdown = appShell:find("monitor_dropdown")

local peripheralList = peripheral.getNames()
local monitorList
for _, i in ipairs(peripheralList) do
    m
end

basalt.run()