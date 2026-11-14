local basalt = require("basalt")
local xml = basalt.use("xml")
local frame = basalt.getMainFrame()
local dialog
local scope = {}
local configs = {}

local function saveConfigs()
    local file = fs.open(fs.combine(shell.dir(), "configs_panel.txt"), "w")
    file.write(textutils.serialise(configs))
    file.close()
end

local function loadConfigs()
    local file = fs.open(fs.combine(shell.dir(), "configs_panel.txt"), "w")
    configs = textutils.unserialise(file.readAll())
    file.close()
end

function scope.exit()
    saveConfigs()
    basalt.stop()
end

local created = xml.loadFile(frame, fs.combine(shell.dir(), "ui/controlpanel.xml"), scope)
local appShell = assert(created[1], "XML did not create an app shell")

dialog = appShell:find("dialog")

loadConfigs()
basalt.run()