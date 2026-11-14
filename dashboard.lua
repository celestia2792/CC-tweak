local basalt = require("basalt")
local xml = basalt.use("xml")
local frame = basalt.getMainFrame()
local dialog, monitorDropdown, programDropdown, connection_list
local outUnit = basalt.state("")
local connectionList = {}
local monitorPrograms = {}
local monitorConnections = {}
local noMonitorPrograms = {}

local scope = {}

local function saveFile()
    local file = fs.open(fs.combine(shell.dir(), "connections.txt"), "w")
    file.write(textutils.serialise(connectionList))
    file.close()
    connection_list.items=connectionList
end

function scope.addNewConnection()
    local selectedMonitor = monitorDropdown:getSelectedItem()
    local selectedProgram = programDropdown:getSelectedItem()
    if selectedMonitor and selectedProgram then
        connectionList[#connectionList+1] = {
            monitor = selectedMonitor.text,
            program = selectedProgram.text,
            text = selectedProgram.text .. "->" .. selectedMonitor.text,
            isRunning = false
        }
        saveFile()
        dialog:alert("Added", connectionList[#connectionList].text)
    else
        dialog:alert("Error", "Select value")
    end
end

local function startNoMonitorConnection(connection)
    local process = noMonitorPrograms[connection]
    if process and coroutine.status(process) ~= "dead" then
        error("Program is already running")
    end

    connection.error = nil
    process = basalt.schedule(function()
        local programPath = "/" .. fs.combine(shell.dir(), connection.program)
        local ok, result = pcall(shell.execute, programPath)
        local message
        if not ok then
            message = tostring(result)
        elseif not result then
            message = "Program exited with an error"
        else
            message = "Finished"
        end

        connection.isRunning = false
        connection.error = message
        if ok and result then
            connection.fg = nil
        else
            connection.fg = colors.red
        end
        noMonitorPrograms[connection] = nil
        saveFile()
        if connection_list:getSelectedItem() == connection then
            outUnit:set(message)
        end
    end)

    if coroutine.status(process) == "dead" then
        return connection.error == "Finished"
    end

    noMonitorPrograms[connection] = process
    connection.isRunning = true
    connection.error = "Running..."
    connection.fg = colors.green
    return true
end

local function startConnection(connection)
    if connection.monitor == "no_monitor" then
        return startNoMonitorConnection(connection)
    end

    local runner = monitorPrograms[connection.monitor]
    if not runner then
        local monitor = peripheral.wrap(connection.monitor)
        local width, height = monitor.getSize()
        local monitorFrame = basalt.createFrame(monitor)
        runner = monitorFrame:addProgram({
            x = 1,
            y = 1,
            width = width,
            height = height,
        })
        local monitorName = connection.monitor
        runner:on("done", function(_, succeeded)
            local activeConnection = monitorConnections[monitorName]
            if not activeConnection or not succeeded then
                return
            end
            activeConnection.isRunning = false
            activeConnection.error = "Finished"
            activeConnection.fg = nil
            saveFile()
            if connection_list:getSelectedItem() == activeConnection then
                outUnit:set(activeConnection.error)
            end
        end)
        runner:on("error", function(_, message)
            local activeConnection = monitorConnections[monitorName]
            if not activeConnection then
                return
            end
            activeConnection.fg = colors.red
            activeConnection.error = message
            activeConnection.isRunning = false
            saveFile()
            if connection_list:getSelectedItem() == activeConnection then
                outUnit:set(message)
            end
        end)
        monitorPrograms[connection.monitor] = runner
    end
    if runner.running then
        error("A program is already running on " .. connection.monitor)
    end
    connection.error = nil
    monitorConnections[connection.monitor] = connection
    runner:execute(fs.combine(shell.dir(), connection.program))
    if connection.error and connection.error ~= "Finished" then
        return false
    end
    connection.isRunning = runner.running
    connection.error = runner.running and "Running..." or "Finished"
    connection.fg = connection.isRunning and colors.green or nil
    return true
end

local function loadFile()
    local file = fs.open(fs.combine(shell.dir(), "connections.txt"), "r")
    connectionList = textutils.unserialise(file.readAll())
    file.close()
    connection_list.items=connectionList
    for _, i in ipairs(connectionList) do
        i.error = nil
        i.fg = nil
        if i.isRunning then
            local ok, started = pcall(startConnection, i)
            if not ok then
                i.isRunning = false
                i.error = tostring(started)
                i.fg = colors.red
            elseif not started then
                i.isRunning = false
                i.fg = colors.red
            else
                i.fg = i.isRunning and colors.green or nil
            end
        end
    end
end

function scope.runBtnPressed()
    local selectedConnection = connection_list:getSelectedItem()
    if selectedConnection then
        if selectedConnection.isRunning then
            dialog:alert("Error", "Program already running")
            return false
        else
            local ok, started = pcall(startConnection, selectedConnection)
            if not ok then
                selectedConnection.isRunning = false
                selectedConnection.error = tostring(started)
                selectedConnection.fg = colors.red
            elseif not started then
                selectedConnection.isRunning = false
                selectedConnection.fg = colors.red
            end
            saveFile()
            outUnit:set(selectedConnection.error)
            return ok and started
        end
    else
       dialog:alert("Error", "Select value")
       return false
    end
end

function scope.stopBtnPressed()
    local selectedConnection = connection_list:getSelectedItem()
    if selectedConnection then
        if selectedConnection.isRunning then
            if selectedConnection.monitor == "no_monitor" then
                local process = noMonitorPrograms[selectedConnection]
                if process and coroutine.status(process) ~= "dead" then
                    if not coroutine.close then
                        error("Cannot stop background programs on this ComputerCraft version")
                    end
                    coroutine.close(process)
                end
                noMonitorPrograms[selectedConnection] = nil
            else
                local runner = monitorPrograms[selectedConnection.monitor]
                runner:stop()
                runner:destroy()
                monitorPrograms[selectedConnection.monitor] = nil
                monitorConnections[selectedConnection.monitor] = nil
            end
            selectedConnection.isRunning = false
            selectedConnection.fg = nil
            selectedConnection.error = "Stopped"
            outUnit:set(selectedConnection.error)
            saveFile()
        else
            dialog:alert("Error", "Program is not running")
            return false
        end
    else
       dialog:alert("Error", "Select value")
       return false
    end
end

function scope.removeConnection()
    local index = connection_list:getSelectedIndex()
    scope.stopBtnPressed()
    if index then
        dialog:alert("Removed", table.remove(connectionList, index).text)
        saveFile()
    else
        dialog:alert("Error", "Select value")
    end
end

function scope.exit()
    saveFile()
    basalt.stop()
end

local function tableToItems(tbl)
    local items = {}
    for k, v in ipairs(tbl) do
        items[k] = {
            text = v
        }
    end
    return items
end

local created = xml.loadFile(frame, fs.combine(shell.dir(), "ui/dashboard.xml"), scope)
local appShell = assert(created[1], "XML did not create an app shell")

dialog = appShell:find("dialog")
monitorDropdown = appShell:find("monitor_dropdown")
local monitorNames = peripheral.getNames()
monitorNames[#monitorNames + 1] = "no_monitor"
monitorDropdown.items = tableToItems(monitorNames)
programDropdown = appShell:find("program_dropdown")
local programs = fs.list(shell.dir())
for index = #programs, 1, -1 do
    if programs[index] == "dashboard.lua" or programs[index] == "dashboard" then
        table.remove(programs, index)
    end
end
programDropdown.items = tableToItems(programs)
connection_list = appShell:find("connection_list")
connection_list:onChange(function (_,index,item)
    if item then
        outUnit:set(item.error)
    end
end)
appShell:find("outUnit").text=outUnit
loadFile()

basalt.run()