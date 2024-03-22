-- Copyright (C) 2024 BeamMP Ltd., BeamMP team and contributors.
-- Licensed under AGPL-3.0 (or later), see <https://www.gnu.org/licenses/>.
-- SPDX-License-Identifier: AGPL-3.0-or-later

--- MPUI API.
--- Author of this documentation is Titch
----@module MPUI
----@usage applyElectrics(...) -- internal access
----@usage MPUI.handle(...) -- external access

local M = {}
M.dependencies = { "MPCoreNetwork", "MPVehicleGE" }

local imgui = ui_imgui
local imu = require('ui/imguiUtils')
require('/common/extensions/ui/flowgraph/editor_api')(M)

--=========================================
-- Variables
--=========================================
local developerMode = true

local chatWindow = require("multiplayer.ui.chat")
local optionsWindow = require("multiplayer.ui.options")
local playerListWindow = require("multiplayer.ui.playerList")

local utils = require("multiplayer.ui.utils")
local configLoaded = false

local buttonSize = 16 -- Size for the image buttons
local maxWindowOpacity = 0.9
local windowOpacity = maxWindowOpacity
local fadeTimer = 0
local collapsed = false
local justExpanded = false

M.uiIcons = {
    settings = 0,
    send = 0,
    reload = 0,
    close = 0,
    down = 0,
    up = 0,
    back = 0,
    user = 0,
}

M.windowOpen = imgui.BoolPtr(true)
M.windowFlags = imgui.flags(imgui.WindowFlags_NoDocking, imgui.WindowFlags_NoTitleBar, imgui.WindowFlags_NoScrollbar)
M.windowCollapsedFlags = M.windowFlags + imgui.flags(imgui.WindowFlags_NoScrollWithMouse, imgui.WindowFlags_NoResize)
M.windowMinSize = imgui.ImVec2(200, 100)
M.windowPadding = imgui.ImVec2(5, 5)

M.canRender = true

M.settings = {}
M.defaultSettings = {
    colors = {
        windowBackground = imgui.ImVec4(0.13, 0.13, 0.13, maxWindowOpacity),
        buttonBackground = imgui.ImVec4(0.13, 0.13, 0.13, maxWindowOpacity),
        buttonHovered = imgui.ImVec4(0.95, 0.43, 0.49, 1),
        buttonActive = imgui.ImVec4(0.95, 0.43, 0.49, 1),
        textColor = imgui.ImVec4(1, 1, 1, 1),
        primaryColor = imgui.ImVec4(0.13, 0.13, 0.13, 1),
        secondaryColor = imgui.ImVec4(0.95, 0.43, 0.49, 1)
    },
    window = {
        inactiveFade = true,
        fadeTime = 2.5,
        uiScale = 1.0,
        fadeWhenCollapsed = false,
        showOnMessage = true
    }
}

local windows = {
    chat = chatWindow,
    options = optionsWindow,
    playerList = playerListWindow,
}

local windowTitle = "BeamMP Chat TEST"
local currentWindow = windows.chat
local lastSize = imgui.ImVec2(0, 0)
local titlebarHeight = 40

local pings = {}   -- { 'apple' = 12, 'banana' = 54, 'meow' = 69 }
local UIqueue = {} -- { editCount = x, show = bool, spawnCount = x }
local playersString = "" -- "player1,player2,player3"

local chatcounter = 0

local function colorToVec4(rgbTable, opacity)
    local v4 = ffi.new("ImVec4")
    v4.x = rgbTable.x
    v4.y = rgbTable.y
    v4.z = rgbTable.z
    v4.w = opacity
    return v4
end

--- Updates the loading information/message based on the provided data.
---@param data string The raw data message containing the code and message.
local function updateLoading(data)
	local code = string.sub(data, 1, 1)
	local msg = string.sub(data, 2)
	if code == "l" then
		guihooks.trigger('LoadingInfo', {message = msg})
	end
end

--- Prompts the user for auto join confirmation and triggers the AutoJoinConfirmation event.
---@param data string The message to display in the confirmation prompt.
local function promptAutoJoinConfirmation(data)
    --print(data)
    guihooks.trigger('AutoJoinConfirmation', {message = data})
    local jscode = "const [IP, PORT] = ['your_server_ip', 'your_server_port'], confirmationMessage = `Do you want to connect to the server at ${IP}:${PORT}?`, userConfirmed = window.confirm(confirmationMessage); userConfirmed ? alert('Connecting to the server...') : alert('Connection canceled.');"
    --bngApi
end

--- Splits a string into fields using the specified separator.
---@param s string The string to split.
---@param sep string (optional) The separator to use. Defaults to a space character.
---@return table An array containing the split fields.
local function split(s, sep)
    local fields = {}

    local sep = sep or " "
    local pattern = string.format("([^%s]+)", sep)
    string.gsub(s, pattern, function(c) fields[#fields + 1] = c end)

    return fields
end

--- Update the players string used to create the player list in the UI when in a session.
---@param data string
local function updatePlayersList(data)
	playersString = data or playersString
	local players = split(playersString, ",")
    local playerListData = {}

	for index, p in ipairs(players) do
		local player = MPVehicleGE.getPlayerByName(p)
		local username = p
		local color = {}
		local id = '?'
		if player then
			local prefix = ""
			for source, tag in pairs(player.nickPrefixes)
				do prefix = prefix..tag.." " end

			local suffix = ""
			for source, tag in pairs(player.nickSuffixes)
				do suffix = suffix..tag.." " end

			username = prefix..''..username..''..suffix..''..player.role.shorttag
			local c = player.role.forecolor
			color = {[0] = c.r, [1] = c.g, [2] = c.b, [3] = c.a}
			id = player.playerID
		end
		table.insert(playerListData, {name = p, formatted_name = username, color = color, id = id})
	end

    -- If we're in the main menu and in development mode, don't update the apps since there aren't any.
    -- This function will manually get called from `onExtensionLoaded` to temporarily populate some data (if development mode)
    if MPCoreNetwork.isMPSession() then
        if not developerMode and tableIsEmpty(players) then return end

        guihooks.trigger("playerList", jsonEncode(playerListData))
        guihooks.trigger("playerPings", jsonEncode(pings))
    end

	playerListWindow.updatePlayerList(pings) -- Send pings because this is a key-value table that contains name and the ping
end

--- Used to tell the Ui of new status for the updates queue.
local function sendQueue() -- sends queue to UI
	guihooks.trigger("setQueue", UIqueue)
end

--- This function is used to update the edit/spawn queue values for the UI indicator.
---@param spawnCount number
---@param editCount number
local function updateQueue( spawnCount, editCount)
	UIqueue = {spawnCount = spawnCount, editCount = editCount}
	UIqueue.show = spawnCount+editCount > 0
	sendQueue()
end

--- Used to set our ping in the top status bar. It also is used in the math for position prediction
---@param ping number
local function setPing(ping)
	if tonumber(ping) < 0 then return end -- not connected
	guihooks.trigger("setPing", ""..ping.." ms")
	pings[MPConfig.getNickname()] = ping
end


--- Set the users nickname so that we know what our username was in lua.
-- Useful in determining who we are 
---@param name any
local function setNickname(name)
	guihooks.trigger("setNickname", name)
end


--- Set the server name in the status bar at the top while in session
-- This is set as part of the joining process automatically
---@param serverName string
local function setServerName(serverName)
	serverName = serverName or (MPCoreNetwork.getCurrentServer() and MPCoreNetwork.getCurrentServer().name)
	guihooks.trigger("setServerName", serverName)
end


--- Update the player count in the top status bar when in a server. Should be preformatted
-- This is set as part of the joining process automatically and is updated during the session
---@param playerCount string
local function setPlayerCount(playerCount)
	guihooks.trigger("setPlayerCount", playerCount)
end


--- Display a prompt in the top corner as a notification, Good for server related events like joins/leaves
---@param text string
---@param type string
local function showNotification(text, type)
	if type and type == "error" then
		log('I', 'showNotification', "[UI Error] > "..tostring(text))
	else
		log('I', 'showNotification', "[Message] > "..tostring(text))
		local leftName = string.match(text, "^(.+) left the server!$")
		if leftName then MPVehicleGE.onPlayerLeft(leftName) end -- Interesting way of doing it
	end

	ui_message(''..text, 10, nil, nil)
end

--- Show a UI dialog / alert box to inform the user of something.
---@param options any
local function showMdDialog(options)
	guihooks.trigger("showMdDialog", options)
end

-- -------------------------------------------------------------
-- ----------------------- Chat Stuff --------------------------
-- -------------------------------------------------------------

--- Pushes multiple ImGui colors `{ImGuiCol, Vec4}` and returns the amount pushed
---@param colors table
---@return pushedCount number
local function pushColors(colors)
    local count = 0

    for _, color in ipairs(colors) do
        local id = color[1]
        if not id then
            log("E", "pushColors", "Invalid color passed into \"pushColors\", ignoring")
        else
            imgui.PushStyleColor2(id, color[2])
            count = count + 1
        end
    end

    return count
end

--- Render the IMGUI chat window and playerlist windows + the settings for them.
local function renderWindow()
    if not configLoaded then return end

    imgui.PushStyleVar2(imgui.StyleVar_WindowMinSize, (collapsed and imgui.ImVec2(lastSize.x, 20)) or M.windowMinSize)

    imgui.PushStyleVar2(imgui.StyleVar_WindowPadding, M.windowPadding)
    imgui.PushStyleVar1(imgui.StyleVar_WindowBorderSize, 0)

    local colors = M.settings.colors
    local colorCount = pushColors({
        -- Slider
        { imgui.Col_SliderGrab,            colorToVec4(colors.secondaryColor,   windowOpacity) },
        { imgui.Col_SliderGrabActive,      colorToVec4(colors.secondaryColor,   windowOpacity) },

        -- Resize Grip
        { imgui.Col_ResizeGrip,            colorToVec4(colors.primaryColor,     windowOpacity) },
        { imgui.Col_ResizeGripHovered,     colorToVec4(colors.secondaryColor,   windowOpacity) },
        { imgui.Col_ResizeGripActive,      colorToVec4(colors.secondaryColor,   windowOpacity) },

        -- Scrollbar
        { imgui.Col_ScrollbarBg,           colorToVec4(colors.primaryColor,     windowOpacity) },
        { imgui.Col_ScrollbarGrab,         colorToVec4(colors.secondaryColor,   windowOpacity) },
        { imgui.Col_ScrollbarGrabHovered,  colorToVec4(colors.secondaryColor,   windowOpacity) },
        { imgui.Col_ScrollbarGrabActive,   colorToVec4(colors.secondaryColor,   windowOpacity) },

        -- Secondary Colors
        { imgui.Col_TextSelectedBg,        colorToVec4(colors.secondaryColor,   windowOpacity) },
        { imgui.Col_Separator,             colorToVec4(colors.secondaryColor,   windowOpacity) },
        { imgui.Col_SeparatorHovered,      colorToVec4(colors.secondaryColor,   windowOpacity) },
        { imgui.Col_SeparatorActive,       colorToVec4(colors.secondaryColor,   windowOpacity) },

        -- Other Colors
        { imgui.Col_WindowBg,              colorToVec4(colors.windowBackground, windowOpacity) },
        { imgui.Col_CheckMark,             colorToVec4(colors.buttonActive,     windowOpacity) },
        { imgui.Col_Text,                  colorToVec4(colors.textColor,        windowOpacity) },

        -- Button Colors
        { imgui.Col_Button,                colorToVec4(colors.buttonBackground, windowOpacity) },
        { imgui.Col_ButtonHovered,         colorToVec4(colors.buttonHovered,    windowOpacity) },
        { imgui.Col_ButtonActive,          colorToVec4(colors.buttonActive,     windowOpacity) }
    })

    local uiScale = M.settings.window.uiScale

    if collapsed then
        imgui.SetNextWindowSize(imgui.ImVec2(lastSize.x, titlebarHeight))
    elseif justExpanded then
        imgui.SetNextWindowSize(lastSize)
        justExpanded = false
    end

    if imgui.Begin("BeamMP Chat", M.windowOpen, (collapsed and M.windowCollapsedFlags or M.windowFlags)) then
        if not collapsed then
            lastSize = imgui.GetWindowSize()
        end

        -- check to fade out if inactive, check if hovered
        if M.settings.window.inactiveFade then
            if imgui.IsWindowFocused(imgui.HoveredFlags_ChildWindows) or imgui.IsWindowHovered(imgui.HoveredFlags_ChildWindows)
                -- or imgui.IsAnyItemHovered() or imgui.IsAnyItemActive() or imgui.IsAnyItemFocused() -- Not exactly sure why I added this but it might be important.
                or (collapsed and not M.settings.window.fadeWhenCollapsed) then
                windowOpacity = maxWindowOpacity
                fadeTimer = 0
            else
                fadeTimer = fadeTimer + imgui.GetIO().DeltaTime
                if fadeTimer > M.settings.window.fadeTime then
                    windowOpacity = windowOpacity - 0.05
                    if windowOpacity < 0 then
                        windowOpacity = 0
                    end
                end
            end
        else
            windowOpacity = maxWindowOpacity
        end

        if currentWindow == windows.chat then
            local msgCount = windows.chat.newMessageCount
            if msgCount > 0 then
                windowTitle = "BeamMP Chat (" .. tostring(msgCount) .. ')'
            else
                windowTitle = "BeamMP Chat"
            end
        end

        -- Titlebar
        imgui.PushStyleVar1(imgui.StyleVar_Alpha, windowOpacity)
        imgui.SetWindowFontScale(uiScale)
        if imgui.BeginChild1("ChatTitlebar", imgui.ImVec2(0, titlebarHeight - 8), false, imgui.WindowFlags_NoScrollbar) then
            local style = imgui.GetStyle()
            local scaledButtonSize = buttonSize * uiScale

            local availHeight = imgui.GetContentRegionAvail().y
            local lineHeight = imgui.GetTextLineHeightWithSpacing()
            local buttonHeight = imgui.GetFrameHeightWithSpacing()
            local contentHeight = lineHeight + buttonHeight - 8

            local offsetY = (availHeight - contentHeight / 2) * 0.5

            imgui.SetCursorPosY(imgui.GetCursorPosY() + offsetY)

            -- Back button
            imgui.SetCursorPosX(style.ItemSpacing.x)
            if currentWindow ~= windows.chat then
                if utils.imageButton(M.uiIcons.back.texId, scaledButtonSize) then
                    collapsed = false
                    currentWindow = windows.chat
                end
                imgui.SameLine()
            end

            imgui.Text(windowTitle)
            imgui.SameLine()

            local availWidth = imgui.GetContentRegionMax().x
            local buttonStartPos = availWidth - style.ItemSpacing.x - ((scaledButtonSize + style.ItemSpacing.x) * 3)

            -- Collapsed button
            imgui.SetCursorPosX(buttonStartPos)
            if utils.imageButton(collapsed and M.uiIcons.down.texId or M.uiIcons.up.texId, scaledButtonSize) then
                collapsed = not collapsed
                if not collapsed then
                    justExpanded = true
                end
            end

            -- Player List button
            imgui.SameLine()
            if utils.imageButton(M.uiIcons.user.texId, scaledButtonSize) then
                if collapsed then
                    justExpanded = true
                    collapsed = false
                end

                currentWindow = windows.playerList
                windowTitle = "BeamMP Chat (Player List)"
            end

            -- Settings button
            imgui.SameLine()
            if utils.imageButton(M.uiIcons.settings.texId, scaledButtonSize) then
                if collapsed then
                    justExpanded = true
                    collapsed = false
                end

                currentWindow = windows.options
                windowTitle = "BeamMP Chat (Options)"
            end

            imgui.EndChild()

            if not collapsed then
                currentWindow.render()
            end
        end

        imgui.PopStyleVar()
        imgui.End()
    end

    imgui.PopStyleColor(colorCount)
    imgui.PopStyleVar(3)
end

--- Saves the configuration settings to file.
----@param settings table The settings to be saved. If not provided, MPUI.settings will be used.
local function saveConfig(settings)
    local jsonData = jsonEncode(settings or MPUI.settings)
    local config = io.open("./settings/BeamMP/chat.json", "w")

    -- If we can't write to the file, return the default settings.
    if not config then
        log("E", "saveConfig", "Failed writing to \"settings/BeamMP/chat.json\", maybe insufficient permissions?")
        return
    end

    config:write(jsonData)
    config:close()
end

--- This function is used to load the settings and config of the UI (chat)
local function loadConfig()
    local defaultSettings = deepcopy(M.defaultSettings) -- Use the default ones just in case we need to return early
    local config = io.open("./settings/BeamMP/chat.json", "r")

    -- If the config doesn't exist, create a new one
    if not config then
        log("I", "loadConfig", "No config found, creating default")

        local jsonData = jsonEncode(M.defaultSettings)
        config = io.open("./settings/BeamMP/chat.json", "w")

        -- If we can't write to the file, return the default settings.
        if not config then
            log("E", "loadConfig", "Failed creating \"settings/BeamMP/chat.json\", maybe insufficient permissions?")
            log("W", "loadConfig", "Using default settings")
            return defaultSettings
        end

        config:write(jsonData)
        config:close()

        log("I", "loadConfig", "Default config created")
    end

    -- Read config
    config = io.open("./settings/BeamMP/chat.json", "r")
    if not config then
        log("E", "loadConfig", "Failed reading \"settings/BeamMP/chat.json\"")
        return defaultSettings
    end

    local jsonData = config:read("*all")
    config:close()

    local settings = jsonDecode(jsonData)
    if not settings then
        log("E", "loadConfig", "Failed to decode config file, using default.")
        return defaultSettings
    end

    -- Find missing keys/settings
    local function findMissingKeys(src, tbl)
        local missing = {}
        for key, value in pairs(src) do
            if type(value) == "table" then
                local subKeys = findMissingKeys(value, tbl and tbl[key])
                for _, subKey in ipairs(subKeys) do
                    table.insert(missing, subKey)
                end
            elseif tbl == nil or tbl[key] == nil then
                table.insert(missing, key)
            end
        end

        return missing
    end

    if #findMissingKeys(M.defaultSettings, settings) > 0 then
        log('I', "loadConfig", "Missing one or more settings, resetting config file...")
        settings = deepcopy(M.defaultSettings)
        saveConfig(settings) -- we pass it in because "MPUI.lua" and "ui/options.lua" depend on eachother,
                                             -- so instead of doing "MPUI.options", we pass it in instead.
    end

    return settings
end

--- Function is for when the game receives a new chat message from the server. 
-- This is for handling the raw chat message
---@param rawMessage string The raw chat message with header codes
local function chatMessage(rawMessage) -- chat message received (angular)
    local message = string.sub(rawMessage, 2)

	chatcounter = chatcounter + 1

    local startPos, endPos = string.find(rawMessage, ":", 2)
    if startPos then
        local username = string.sub(rawMessage, 2, startPos - 1)
        local msg = string.sub(rawMessage, endPos + 1)

        local player = MPVehicleGE.getPlayerByName(username)

        if player then
            local c = player.role.forecolor
            local color = {[0] = c.r, [1] = c.g, [2] = c.b, [3] = c.a}

            log("M", "chatMessage", "Chat message received from: " .. username .. " >" .. msg) -- DO NOT REMOVE
            guihooks.trigger("chatMessage", {username = username, message = message, id = chatcounter, color = color})

            chatWindow.addMessage(username, msg, chatcounter, color)
        else
            log("M", "chatMessage", "Chat message received from: " .. username .. " >" .. msg) -- DO NOT REMOVE
            guihooks.trigger("chatMessage", {username = username, message = message, id = chatcounter})

            chatWindow.addMessage(username, msg, nil)
        end
        
        TriggerClientEvent("ChatMessageReceived", message, username) -- Username added last to not break other mods.
    end
end


--- Sends a chat message to the server for viewing by other players.
---@param msg string The chat message typed by the user
local function chatSend(msg)
	local c = 'C:'..MPConfig.getNickname()..": "..msg
	MPGameNetwork.send(c)
	TriggerClientEvent("ChatMessageSent", c)
end

local function bringToFront()
    windowOpacity = maxWindowOpacity
    fadeTimer = 0
end

--- Toggle the IMGUI chat to show or hide
local function toggleChat()
    if not M.canRender then
        M.canRender = true
        windowOpacity = maxWindowOpacity
    else
        M.canRender = false
    end
end

-- Bring chat to front and focus
local function focusChat()
    if not settings.getValue("enableNewChatMenu") then return end

    currentWindow = windows.chat
    bringToFront()
    currentWindow.requestFocus()
end

--- This function is for mapping player pings to names for the playerlist
---@param playerName string The player name
---@param ping number The players ping
local function setPlayerPing(playerName, ping)
	pings[playerName] = ping
end

--- Executes when the user or mod ends a mission/session (map) .
---@param mission table The mission object.
local function onClientEndMission()
    pings = {}
    chatWindow.chatMessages = {}
    chatWindow.clearHistory()
end

--- Triggered by BeamNG when the lua mod is loaded by the modmanager system.
local function onExtensionLoaded()
    M.settings = loadConfig()
    if M.settings then
        configLoaded = true
    end

    log("I", "onExtensionLoaded", "Config Loaded!")

    optionsWindow.onInit(M.settings)

    for k, _ in pairs(M.uiIcons) do
        local path = "./icons/" .. k .. ".png"
        local texObj = imu.texObj(path)

        -- We set the texture here because if it fails, we won't have any errors. It just won't render the textures.
        -- Feel free to change it if you want, but this works just fine and handles the button and everything, there's just no texture.
        M.uiIcons[k] = texObj

        if not FS:fileExists(path) then
            log("E", "onExtensionLoaded", "Missing icon: " .. k)
            goto continue
        end

        -- Ensure the texture gets loaded correctly
        if texObj.texId == nil then
            log("E", "onExtensionLoaded", "Failed loading icon: " .. k)
        end

        ::continue::
    end

    -- If we're in dev mode, just update the playerlist data so we can develop it in the main menu to make life easier
    if developerMode then
        pings = {["Daniel-W"] = 1}   -- { 'apple' = 12, 'banana' = 54, 'meow' = 69 }
        updatePlayersList("Daniel-W")
    end
end

--- onUpdate is a game eventloop function. It is called each frame by the game engine.
-- This is the main processing thread of BeamMP in the game
---@param dt float
local function onUpdate(dt)
    if not developerMode and (worldReadyState ~= 2 or not settings.getValue("enableNewChatMenu") or not M.canRender or MPCoreNetwork and not MPCoreNetwork.isMPSession()) then return end
    renderWindow()

    -- imgui.ShowDemoWindow()
end

M.updateLoading = updateLoading
M.promptAutoJoinConfirmation = promptAutoJoinConfirmation
M.updatePlayersList = updatePlayersList
M.setPing = setPing
M.setNickname = setNickname
M.setServerName = setServerName
M.chatMessage = chatMessage
M.chatSend = chatSend
M.setPlayerCount = setPlayerCount
M.showNotification = showNotification
M.setPlayerPing = setPlayerPing
M.updateQueue = updateQueue
M.sendQueue = sendQueue
M.showMdDialog = showMdDialog

M.saveConfig = saveConfig

M.bringToFront = bringToFront
M.toggleChat = toggleChat
M.focusChat = focusChat

M.onClientEndMission = onClientEndMission
M.onExtensionLoaded = onExtensionLoaded
M.onUpdate = onUpdate
M.onInit = function() setExtensionUnloadMode(M, "manual") end

return M
