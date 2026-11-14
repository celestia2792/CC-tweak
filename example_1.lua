local basalt = require("basalt")

local theme = basalt.use("theme")
basalt.use("charts")

local palette = theme.applyPreset("basalt")
local frame = basalt.getMainFrame()

-- Domain model --------------------------------------------------------------

local services = {
    { name = "Gateway", status = "ONLINE", load = 32 },
    { name = "Storage", status = "ONLINE", load = 48 },
    { name = "Crafter", status = "OFFLINE", load = 0 },
    { name = "Monitor", status = "ONLINE", load = 27 },
}

local pollingEnabled = basalt.state(true)
local refreshSeconds = basalt.state(2)
local operatorName = basalt.state("Alex")
local onlineCount = basalt.state(0)
local averageLoad = basalt.state(0)
local lastUpdate = basalt.state("Waiting for first sample")

local function makeRows()
    local rows = {}
    for index, service in ipairs(services) do
        rows[index] = {
            service.name,
            service.status,
            service.load .. "%",
        }
    end
    return rows
end

local function recalculate()
    local online = 0
    local load = 0

    for _, service in ipairs(services) do
        if service.status == "ONLINE" then
            online = online + 1
            load = load + service.load
        end
    end

    onlineCount:set(online)
    averageLoad:set(online > 0 and math.floor(load / online) or 0)
end

recalculate()

-- Application shell ---------------------------------------------------------

frame:addLabel({
    x = 2,
    y = 1,
    text = "BASALT CONTROL ROOM",
    foreground = palette.lava,
})

frame:addButton({
    x = 45,
    y = 1,
    width = 6,
    height = 1,
    text = "Exit",
    foreground = palette.bg,
    background = palette.danger,
}):onClick(function()
    basalt.stop()
end)

local tabs = frame:addTabControl({
    x = 1,
    y = 2,
    width = basalt.fill(),
    height = basalt.fill(),
})

local overviewPage = tabs:addTab("Overview")
local servicesPage = tabs:addTab("Services")
local settingsPage = tabs:addTab("Settings")

-- Overview page -------------------------------------------------------------

overviewPage:addLabel({
    x = 2,
    y = 2,
    text = "SYSTEM OVERVIEW",
    foreground = palette.muted,
})

overviewPage:addLabel({
    x = 2,
    y = 4,
    width = 31,
    text = basalt.computed(function()
        return onlineCount:get() .. "/" .. #services .. " services online"
    end),
})

overviewPage:addProgressBar({
    x = 2,
    y = 5,
    width = 31,
    progress = averageLoad,
    showPercentage = true,
})

local loadGraph = overviewPage:addPixelGraph({
    x = 2,
    y = 7,
    width = 31,
    height = 8,
    minValue = 0,
    maxValue = 100,
    background = palette.surface,
})
loadGraph:addSeries("load", {
    color = palette.lava,
    pointCount = 62,
})
loadGraph:addPoint("load", averageLoad:get())

overviewPage:addLabel({
    x = 36,
    y = 2,
    text = "LIVE STATUS",
    foreground = palette.muted,
})

overviewPage:addLabel({
    x = 36,
    y = 4,
    width = 14,
    text = basalt.computed(function()
        return pollingEnabled:get() and "POLLING ON" or "POLLING OFF"
    end),
    foreground = basalt.computed(function()
        return pollingEnabled:get() and palette.success or palette.warning
    end),
})

overviewPage:addLabel({
    x = 36,
    y = 6,
    width = 14,
    height = 2,
    text = operatorName:map(function(value)
        return "Operator:\n" .. (value ~= "" and value or "Unknown")
    end),
})

overviewPage:addLabel({
    x = 36,
    y = 10,
    width = 14,
    height = 3,
    text = lastUpdate,
    foreground = palette.muted,
})

overviewPage:addLabel({
    x = 2,
    y = 15,
    width = 31,
    text = "Average load history",
    foreground = palette.muted,
})

-- Services page -------------------------------------------------------------

local serviceTable = servicesPage:addTable({
    x = 2,
    y = 2,
    width = 34,
    height = 12,
    columns = {
        { name = "Service", width = 14 },
        { name = "Status", width = 10 },
        { name = "Load", width = 7 },
    },
    data = makeRows(),
    sortable = true,
})

local selectionText = basalt.state("Select a service to manage it.")

servicesPage:addLabel({
    x = 2,
    y = 15,
    width = 47,
    height = 2,
    text = selectionText,
    foreground = palette.muted,
})

servicesPage:addLabel({
    x = 38,
    y = 2,
    text = "ACTIONS",
    foreground = palette.muted,
})

local toggleButton = servicesPage:addButton({
    x = 38,
    y = 4,
    width = 12,
    height = 3,
    text = "Toggle",
})

local refreshButton = servicesPage:addButton({
    x = 38,
    y = 8,
    width = 12,
    height = 3,
    text = "Refresh",
})

serviceTable:onSelect(function(_, index)
    local service = services[index]
    selectionText:set(
        service.name .. ": " .. service.status
            .. ", load " .. service.load .. "%"
    )
end)

-- Settings page -------------------------------------------------------------

settingsPage:addLabel({
    x = 2,
    y = 2,
    text = "DASHBOARD SETTINGS",
    foreground = palette.muted,
})

settingsPage:addLabel({
    x = 2,
    y = 5,
    text = "Operator",
})

local operatorInput = settingsPage:addInput({
    x = 15,
    y = 5,
    width = 20,
    placeholder = "Operator name",
})
operatorInput:bind("text", operatorName)

settingsPage:addLabel({
    x = 2,
    y = 8,
    width = 12,
    text = refreshSeconds:map(function(value)
        return "Refresh: " .. value .. "s"
    end),
})

local intervalSlider = settingsPage:addSlider({
    x = 15,
    y = 8,
    width = 20,
    min = 1,
    max = 5,
    step = 1,
})
intervalSlider:bind("value", refreshSeconds)

settingsPage:addLabel({
    x = 2,
    y = 11,
    text = "Live polling",
})

local pollingSwitch = settingsPage:addSwitch({
    x = 15,
    y = 11,
})
pollingSwitch:bind("checked", pollingEnabled)

local saveButton = settingsPage:addButton({
    x = 15,
    y = 14,
    width = 14,
    height = 2,
    text = "Save",
    foreground = palette.bg,
    background = palette.lava,
})

settingsPage:addLabel({
    x = 37,
    y = 5,
    width = 13,
    height = 7,
    text = basalt.computed(function()
        local name = operatorName:get()
        if name == "" then name = "Unknown" end

        local mode = pollingEnabled:get() and "Live" or "Paused"
        return "PREVIEW\n\n" .. name .. "\n" .. mode .. "\nEvery "
            .. refreshSeconds:get() .. "s"
    end),
    foreground = palette.muted,
})

-- Root overlays and application actions ------------------------------------

local toast = frame:addToast({
    duration = 2,
    maxWidth = 24,
})

local dialog = frame:addDialog({
    boxWidth = 34,
})

local sample = 0
local wave = { 7, -4, 9, -6, 3, -8, 5 }

local function refreshMetrics()
    sample = sample + 1

    for index, service in ipairs(services) do
        if service.status == "ONLINE" then
            local change = wave[(sample + index - 2) % #wave + 1]
            service.load = math.max(5, math.min(95, service.load + change))
            serviceTable:updateCell(index, 3, service.load .. "%")
        end
    end

    recalculate()
    loadGraph:addPoint("load", averageLoad:get())
    lastUpdate:set("Sample #" .. sample .. "\nAverage: "
        .. averageLoad:get() .. "%")
end

toggleButton:onClick(function()
    local index = serviceTable.selected
    if not index then
        toast:warning("Select a service first")
        return
    end

    local service = services[index]
    local nextStatus = service.status == "ONLINE" and "OFFLINE" or "ONLINE"

    dialog:confirm(
        "Change service?",
        "Set " .. service.name .. " to " .. nextStatus .. "?",
        function(confirmed)
            if confirmed then
                service.status = nextStatus
                service.load = nextStatus == "ONLINE" and 20 or 0

                serviceTable:updateCell(index, 2, service.status)
                serviceTable:updateCell(index, 3, service.load .. "%")
                recalculate()

                selectionText:set(
                    service.name .. ": " .. service.status
                        .. ", load " .. service.load .. "%"
                )
                toast:success(service.name .. " is now " .. service.status)
            else
                toast:info("No changes made")
            end
            toggleButton:focus()
        end
    )
    dialog:focus()
end)

refreshButton:onClick(function()
    refreshMetrics()
    toast:info("Metrics refreshed")
end)

saveButton:onClick(function()
    local name = operatorName:get()
    if name:match("^%s*$") then
        toast:warning("Enter an operator name")
        operatorInput:focus()
        return
    end

    toast:success("Settings saved")
end)

basalt.schedule(function()
    while true do
        sleep(refreshSeconds:get())
        if pollingEnabled:get() then
            refreshMetrics()
        end
    end
end)

serviceTable:focus()
basalt.run()