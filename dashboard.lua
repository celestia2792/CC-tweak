local basalt = require("basalt")

local frame = basalt.getMainFrame()
frame.background = colors.black

local currentPage = basalt.state(1)

local nav = frame:addFrame({
    x = 1,
    y = 1,
    width = 13,
    height = basalt.fill(),
    background = colors.gray,
})

local content = frame:addFrame({
    x = 14,
    y = 1,
    width = basalt.fill(),
    height = basalt.fill(),
    background = colors.black,
})

local home = content:addFrame({
    width = basalt.percent(1),
    height = basalt.percent(1),
    background = colors.black,
})

home:addLabel({
    x = 2,
    y = 2,
    text = "Dashboard",
    foreground = colors.orange,
})

local search = home:addInput({
    x = 2,
    y = 5,
    width = 22,
    placeholder = "Search",
})

local settings = content:addFrame({
    width = basalt.percent(1),
    height = basalt.percent(1),
    background = colors.black,
    visible = false,
})

settings:addLabel({
    x = 2,
    y = 2,
    text = "Settings",
    foreground = colors.orange,
})

local name = settings:addInput({
    x = 2,
    y = 5,
    width = 22,
    placeholder = "Computer name",
})

local pages = { home, settings }
local focusTargets = { search, name }
local buttons = {}

local function showPage(index)
    for i, page in ipairs(pages) do page.visible = i == index end
    for i, button in ipairs(buttons) do
        button.background = i == index and colors.blue or colors.gray
    end
    focusTargets[index]:focus()
end

buttons[1] = nav:addButton({
    x = 2,
    y = 3,
    width = 10,
    height = 2,
    text = "Home",
}):onClick(function()
    currentPage:set(1)
end)

buttons[2] = nav:addButton({
    x = 2,
    y = 7,
    width = 10,
    height = 2,
    text = "Settings",
}):onClick(function()
    currentPage:set(2)
end)

nav:addButton({
    x = 2,
    y = 15,
    width = 10,
    height = 2,
    text = "Exit",
    background = colors.red,
}):onClick(function()
    basalt.stop()
end)

currentPage:subscribe(showPage, true)
basalt.run()