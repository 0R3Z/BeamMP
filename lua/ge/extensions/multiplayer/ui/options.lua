-- Copyright (C) 2024 BeamMP Ltd., BeamMP team and contributors.
-- Licensed under AGPL-3.0 (or later), see <https://www.gnu.org/licenses/>.
-- SPDX-License-Identifier: AGPL-3.0-or-later

--- multiplayer_ui_options API.
--- Author of this documentation is Titch
--- @module multiplayer_ui_options
--- @usage saveConfig(settings) -- internal access
--- @usage multiplayer_ui_options.saveConfig(settings) -- external access

local M = {}

local utils = require("multiplayer.ui.utils")

local imgui = ui_imgui
local longestSettingName = 0
local sortedSettings = {}

--- Converts a string to title case.
--- @param str string The input string.
--- @return string str The converted string in title case.
local function toTitleCase(str)
    return str:gsub("%u", function(c) return " " .. c end):gsub("^%l", string.upper)
end

-- ------------------------------
-- ---[ Utility Functions ]------
-- ------------------------------

local function renderFooter(btnHeight)
    if imgui.BeginChild1("##footer", imgui.ImVec2(0, btnHeight), false, imgui.WindowFlags_NoScrollbar) then
        imgui.SetCursorPosY((imgui.GetContentRegionAvail().y - imgui.GetFrameHeightWithSpacing()) * 0.5)

        if imgui.Button("Reset to default", imgui.ImVec2(0, btnHeight)) then
            MPUI.settings = deepcopy(MPUI.defaultSettings)
            sortedSettings = {}
            local newSortedSettings = {}
            for name, category in pairs(MPUI.defaultSettings) do
                newSortedSettings[name] = {}
                for settingName, setting in pairs(category) do
                    table.insert(newSortedSettings[name], { name = settingName, tab = setting })
                end
                table.sort(newSortedSettings[name], function(a, b) return a.name < b.name end)
            end
            sortedSettings = newSortedSettings
        end

        imgui.SameLine()

        if imgui.Button("Save", imgui.ImVec2(0, btnHeight)) then
            MPUI.saveConfig()
        end
        imgui.EndChild()
    end
end

local function option(label, px, avx, setWidth)
    setWidth = setWidth or false

    imgui.Text(label)
    imgui.SameLine()
    imgui.SetCursorPosX(px)

    if setWidth then
        local w = imgui.GetWindowWidth()
        local threshold = 400
        local capWidth = 400

        local itemWidth = (w <= threshold) and (avx - px) or math.min(avx - px, capWidth)
        imgui.SetNextItemWidth(itemWidth)
    end
end

local function sliderFloat(label, px, avx, value, mi, ma, fmt)
    fmt = fmt or "%.1f"
    option(label, px, avx, true)
    local pOpt = imgui.FloatPtr(value)
    if imgui.SliderFloat("##" .. label, pOpt, mi, ma, fmt) then
        value = pOpt[0]
    end
    return value
end

--------------------------------
-----[       Tabs        ]------
--------------------------------
local function renderTheming()
    local uiScale = MPUI.settings.window.uiScale
    local btnHeight = 28 * uiScale

    if imgui.BeginChild1("##tab_color", imgui.ImVec2(0, imgui.GetContentRegionAvail().y - btnHeight - 2), false) then
        for _, setting in pairs(sortedSettings.colors) do
            if #setting.name > longestSettingName then
                longestSettingName = #setting.name
            end
            -- All are colors, create text and then 3 sliders
            local color = ffi.new("float[4]", setting.tab.x, setting.tab.y, setting.tab.z, 1)

            imgui.Text(toTitleCase(setting.name))
            imgui.SameLine()
            imgui.SetCursorPosX((longestSettingName * 8 + 10) * MPUI.settings.window.uiScale)
            if imgui.ColorEdit3("##" .. setting.name, color, imgui.ColorEditFlags_NoInputs) then
                MPUI.settings.colors[setting.name] = imgui.ImVec4(color[0], color[1], color[2], 1)
                setting.tab = imgui.ImVec4(color[0], color[1], color[2], 1)
            end
        end

        imgui.EndChild()
    end

    renderFooter(btnHeight)
end

local function renderGeneral()
    local uiScale = MPUI.settings.window.uiScale

    local btnHeight = 28 * uiScale
    local mb = 2 -- todo: don't hardcode, use style
                 -- Daniel-W 20/03/2024: I have no idea what `mb` even means. Margin bottom maybe??
                 -- TODO: Remove these comments and cleanup
    if imgui.BeginChild1("##tab_general", imgui.ImVec2(0, imgui.GetContentRegionAvail().y - btnHeight - mb), false, imgui.WindowFlags_AlwaysAutoResize) then
        local posx = (longestSettingName * 8 + 10) * uiScale
        local availX = imgui.GetContentRegionAvail().x

        -- Inactive Fade
        imgui.Text("Inactive fade")
        imgui.SameLine()
        imgui.SetCursorPosX(posx)
        local pInactiveFade = imgui.BoolPtr(MPUI.settings.window.inactiveFade)
        if imgui.Checkbox("##inactive_fade", pInactiveFade) then
            MPUI.settings.window.inactiveFade = pInactiveFade[0]
        end

        MPUI.settings.window.fadeTime = sliderFloat("Fade Time", posx, availX, MPUI.settings.window.fadeTime, 0.1, 10, "%.2f")
        MPUI.settings.window.uiScale = sliderFloat("UI Scale", posx, availX, MPUI.settings.window.uiScale, 0.95, 1.5, "%.2f")

        -- Fade when collapsed
        imgui.Text("Fade when collapsed")
        imgui.SameLine()
        imgui.SetCursorPosX(posx)
        local pFadeWhenCollapsed = imgui.BoolPtr(MPUI.settings.window.fadeWhenCollapsed)
        if imgui.Checkbox("##fade_when_collapsed", pFadeWhenCollapsed) then
            MPUI.settings.window.fadeWhenCollapsed = pFadeWhenCollapsed[0]
        end

        -- Show on message
        imgui.Text("Show on message")
        imgui.SameLine()
        imgui.SetCursorPosX(posx)
        local pShowOnMessage = imgui.BoolPtr(MPUI.settings.window.showOnMessage)
        if imgui.Checkbox("##show_on_message", pShowOnMessage) then
            MPUI.settings.window.showOnMessage = pShowOnMessage[0]
        end

        -- Bottom Buttons
        imgui.EndChild()
    end

    renderFooter(btnHeight)
end

local tabs = {
    theming = {
        name = "Theming",
        render = renderTheming,
        id = 1,
    },
    general = {
        name = "General",
        render = renderGeneral,
        id = 2,
    }
}

local renderTab = renderTheming

local function render()
    imgui.PushStyleVar1(imgui.StyleVar_FrameRounding, 0)

    for _, tab in pairs(tabs) do
        local isActiveTab = (renderTab == tab.render)
        -- if isActiveTab then
        --     imgui.PushStyleColor1(imgui.Col_Button)
        -- end

        if imgui.Button(tab.name, imgui.ImVec2(imgui.GetWindowWidth() / 2, 23 * MPUI.settings.window.uiScale)) then
            renderTab = tab.render
        end

        -- if isActiveTab then
        --     imgui.PopStyleColor()
        -- end

        imgui.SameLine()
    end

    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()

    renderTab()
end

--- Initial call when the mod/module is loaded 
local function onInit(settings)
    sortedSettings = {} -- for reloading

    -- Sort tabs by id
    local newSortedTabs = {}
    for _, tab in pairs(tabs) do
        table.insert(newSortedTabs, tab)
    end
    table.sort(newSortedTabs, function(a, b) return a.id < b.id end)
    tabs = newSortedTabs

    -- Sort settings alphabetically
    local newSortedSettings = {}
    for name, category in pairs(settings) do
        newSortedSettings[name] = {}
        for settingName, setting in pairs(category) do
            table.insert(newSortedSettings[name], { name = settingName, tab = setting })
        end
        
        table.sort(newSortedSettings[name], function(a, b) return a.name < b.name end)
    end

    sortedSettings = newSortedSettings
end

M.render = render
M.onInit = onInit

return M
