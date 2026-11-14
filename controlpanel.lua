local basalt = require("basalt")
local xml = basalt.use("xml")
local frame = basalt.getMainFrame()
local dialog, tabCtl, peripheralList, configSelection, configList
local stressValue, fuelProgress, fuelAmount, engineControls, manualControl
local scope = {}
local configs = {}
local currentStress, currentStressCapacity

local function tableToItems(tbl)
    local items = {}
    for k, v in ipairs(tbl) do
        items[k] = {
            text = v
        }
    end
    return items
end

function scope.saveConfigs()
    local file = fs.open(fs.combine(shell.dir(), "configs_panel.txt"), "w")
    file.write(textutils.serialise(configs))
    file.close()
end

function scope.addConfig()
    local selectedItem = peripheralList:getSelectedItem()
    local targetConfig = configSelection:getSelectedItem()
    if not selectedItem then
        dialog:alert("Error", "Select Peripheral")
        return
    end
    if not targetConfig then
        dialog:alert("Error", "Select Configure")
        return
    end
    configs[targetConfig.text][#configs[targetConfig.text] + 1] = selectedItem.text
    configList:addItem(selectedItem.text)
    scope.saveConfigs()
end

function scope.removeConfig()
    local selectedIndex = configList:getSelectedIndex()
    local targetConfig = configSelection:getSelectedItem()
    if not selectedIndex then
        dialog:alert("Error", "Select Peripheral")
        return
    end
    if not targetConfig then
        dialog:alert("Error", "Select Configure")
        return
    end
    table.remove(configs[targetConfig.text], selectedIndex)
    configList:removeItem(selectedIndex)
    scope.saveConfigs()
end

local function loadConfigs()
    local file = fs.open(fs.combine(shell.dir(), "configs_panel.txt"), "r")
    configs = textutils.unserialise(file.readAll())
    if type(configs) ~= "table" or next(configs) == nil then
        configs = {
            engineRelays={},
            fuelTanks={},
            stressometer={},
            manualControl=false,
        }
    end
    if configs.manualControl == nil then
        configs.manualControl = false
    end
    file.close()
end

function scope.printConfig(_, _, item)
    configList.items=tableToItems(configs[item.text])
end

function scope.exit()
    scope.saveConfigs()
    basalt.stop()
end

local created = xml.loadFile(frame, fs.combine(shell.dir(), "ui/controlpanel.xml"), scope)
local appShell = assert(created[1], "XML did not create an app shell")

configList = appShell:find("configList")
dialog = appShell:find("dialog")
tabCtl = appShell:find("tabCtl")
local tabs = {}
for _, child in ipairs(tabCtl:getChildren()) do
    tabs[#tabs + 1] = {
        title = child.name,
        frame = child,
    }
    child.visible = #tabs == 1
end
rawset(tabCtl, "_tabs", tabs)
tabCtl.active = #tabs > 0 and 1 or 0
tabCtl:markDirty()
peripheralList = appShell:find("peripheralList")
loadConfigs()
configSelection = appShell:find("configSelection")
for key, value in pairs(configs) do
    if type(value) == "table" then
        configSelection:addItem(key)
    end
end
peripheralList.items = tableToItems(peripheral.getNames())
stressValue = appShell:find("stressValue")
fuelProgress = appShell:find("fuelProgress")
fuelAmount = appShell:find("fuelAmount")
engineControls = appShell:find("engineControls")
manualControl = appShell:find("manualControl")
manualControl.checked = configs.manualControl == true

local function updateStress()
    currentStress, currentStressCapacity = nil, nil
    local stressometerName = configs.stressometer[1]
    if not stressometerName then
        stressValue.text = "No stressometer configured"
        stressValue.foreground = colors.red
        return
    end

    local stressometer = peripheral.wrap(stressometerName)
    if not stressometer or type(stressometer.getStress) ~= "function"
        or type(stressometer.getStressCapacity) ~= "function" then
        stressValue.text = "Stressometer unavailable: " .. stressometerName
        stressValue.foreground = colors.red
        return
    end

    local ok, stress, capacity = pcall(function()
        return stressometer.getStress(), stressometer.getStressCapacity()
    end)
    if not ok then
        stressValue.text = "Stress read error: " .. tostring(stress)
        stressValue.foreground = colors.red
    elseif type(stress) ~= "number" or type(capacity) ~= "number" then
        stressValue.text = "Invalid stress readings"
        stressValue.foreground = colors.red
    else
        currentStress = stress
        currentStressCapacity = capacity
        stressValue.text = string.format("%.0f / %.0f", stress, capacity)
        stressValue.foreground = colors.white
    end
end

local function updateFuel()
    local tanks = configs.fuelTanks
    local capacity = #tanks * 288000
    if #tanks == 0 then
        fuelAmount.text = "No fuel tanks configured"
        fuelAmount.foreground = colors.red
        fuelProgress.progress = 0
        return
    end

    local amount = 0
    for _, tankName in ipairs(tanks) do
        local tank = peripheral.wrap(tankName)
        if not tank or type(tank.tanks) ~= "function" then
            fuelAmount.text = "Fuel tank unavailable: " .. tankName
            fuelAmount.foreground = colors.red
            fuelProgress.progress = 0
            return
        end

        local ok, contents = pcall(tank.tanks)
        if not ok then
            fuelAmount.text = "Fuel read error: " .. tostring(contents)
            fuelAmount.foreground = colors.red
            fuelProgress.progress = 0
            return
        end
        if type(contents) ~= "table" then
            fuelAmount.text = "Invalid fuel data: " .. tankName
            fuelAmount.foreground = colors.red
            fuelProgress.progress = 0
            return
        end

        for _, fluid in ipairs(contents) do
            if type(fluid.amount) ~= "number" then
                fuelAmount.text = "Invalid fuel amount: " .. tankName
                fuelAmount.foreground = colors.red
                fuelProgress.progress = 0
                return
            end
            amount = amount + fluid.amount
        end
    end

    fuelAmount.text = string.format("%.0f / %.0f", amount, capacity)
    fuelAmount.foreground = colors.white
    fuelProgress.progress = math.min(100, amount / capacity * 100)
end

local ENGINE_CAPACITY = 147456
local STRESS_RESERVE = 50000
local configuredEngines = {}
for _, relayName in ipairs(configs.engineRelays) do
    configuredEngines[#configuredEngines + 1] = relayName
end
table.sort(configuredEngines)

local engines = {}
local panelWidth = math.max(1, math.floor(engineControls.width))
local switchX = math.max(1, panelWidth - 3)
local statusX = math.max(1, switchX - 5)
local nameWidth = math.max(1, statusX - 2)

for index, relayName in ipairs(configuredEngines) do
    local engineName = relayName
    local row = index
    local engine = {
        relayName = engineName,
        name = "Engine_" .. (index - 1),
        available = false,
    }

    engineControls:addLabel({
        x = 1,
        y = row,
        width = nameWidth,
        height = 1,
        text = engine.name,
    })
    local stateLabel = engineControls:addLabel({
        x = statusX,
        y = row,
        width = 4,
        height = 1,
        text = "----",
    })
    engine.switch = engineControls:addSwitch({
        x = switchX,
        y = row,
        width = 4,
        height = 1,
    })

    local function updateStateLabel(text, color)
        stateLabel.text = text
        stateLabel.foreground = color
    end

    engine.refresh = function()
        local relay = peripheral.wrap(engine.relayName)
        if not relay or type(relay.getOutput) ~= "function"
            or type(relay.setOutput) ~= "function" then
            engine.available = false
            engine.switch.disabled = true
            updateStateLabel("ERR", colors.red)
            return
        end

        local ok, output = pcall(relay.getOutput, "bottom")
        if not ok or type(output) ~= "boolean" then
            engine.available = false
            engine.switch.disabled = true
            updateStateLabel("ERR", colors.red)
            return
        end

        engine.available = true
        engine.switch.disabled = false
        engine.switch.checked = not output
        updateStateLabel(output and "OFF" or "ON", output and colors.gray or colors.green)
    end

    engine.setRunning = function(enabled)
        local relay = peripheral.wrap(engine.relayName)
        if not relay or type(relay.setOutput) ~= "function" then
            engine.available = false
            engine.switch.disabled = true
            updateStateLabel("ERR", colors.red)
            return false, "Relay unavailable: " .. engine.relayName
        end

        local ok, err = pcall(relay.setOutput, "bottom", not enabled)
        if not ok then
            engine.available = false
            engine.switch.disabled = true
            updateStateLabel("ERR", colors.red)
            return false, tostring(err)
        end

        engine.available = true
        engine.switch.checked = enabled
        updateStateLabel(enabled and "ON" or "OFF", enabled and colors.green or colors.gray)
        return true
    end

    engine.switch:onChange(function(_, enabled)
        local ok, err = engine.setRunning(enabled)
        if not ok then
            engine.switch.checked = not enabled
            dialog:alert("Engine relay error", tostring(err))
        end
    end)

    engine.refresh()
    engines[#engines + 1] = engine
end

if #configuredEngines == 0 then
    engineControls:addLabel({
        x = 1,
        y = 1,
        width = panelWidth,
        height = 1,
        text = "No engine relays configured",
        foreground = colors.red,
    })
end

manualControl:onChange(function(_, isManual)
    configs.manualControl = isManual
    scope.saveConfigs()
end)

local function updateAutomaticControl()
    if manualControl.checked then
        return
    end
    if currentStress == nil or currentStressCapacity == nil then
        return
    end

    local activeCount = 0
    for _, engine in ipairs(engines) do
        if not engine.available then
            return
        end
        if engine.switch.checked then
            activeCount = activeCount + 1
        end
    end

    local expectedCapacity = activeCount * ENGINE_CAPACITY
    if math.abs(currentStressCapacity - expectedCapacity) > 1 then
        return
    end

    if currentStress > 0
        and currentStress + STRESS_RESERVE > currentStressCapacity then
        for _, engine in ipairs(engines) do
            if not engine.switch.checked then
                engine.setRunning(true)
                return
            end
        end
        return
    end

    for index = #engines, 1, -1 do
        local engine = engines[index]
        if engine.switch.checked
            and (currentStress <= 0
                or currentStressCapacity - ENGINE_CAPACITY
                    >= currentStress + STRESS_RESERVE) then
            engine.setRunning(false)
            return
        end
    end
end

basalt.schedule(function()
    while true do
        updateStress()
        updateFuel()
        for _, engine in ipairs(engines) do
            engine.refresh()
        end
        updateAutomaticControl()
        sleep(1)
    end
end)

basalt.run()