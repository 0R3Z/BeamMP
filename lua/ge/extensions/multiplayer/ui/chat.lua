-- Copyright (C) 2024 BeamMP Ltd., BeamMP team and contributors.
-- Licensed under AGPL-3.0 (or later), see <https://www.gnu.org/licenses/>.
-- SPDX-License-Identifier: AGPL-3.0-or-later

--- multiplayer_ui_chat API.
--- Author of this documentation is Titch
--- @module multiplayer_ui_chat
--- @usage colorFromRGB(r,g,b,a) -- internal access
--- @usage multiplayer_ui_chat.addMessage(username, message, id, color) -- external access

local M = {
    chatMessages = {},
    newMessageCount = 0
}

local utils = require("multiplayer.ui.utils")
local ffi = require('ffi')

local imgui = ui_imgui
local heightOffset = 20
local forceBottom = false
local scrollToBottom = false
local chatMessageBuf = imgui.ArrayChar(256)
local wasMessageSent = false
local history = {}
local historyPos = -1
local requestInputFocus = false

--- Creates an ImGui ImVec4 color based on the provided RGBA values.
--- @param r number The red component of the color (0-255).
--- @param g number The green component of the color (0-255).
--- @param b number The blue component of the color (0-255).
--- @param a number The alpha component of the color (0-255).
--- @return table Returns an ImVec4 color table representing the specified RGB values.
local function colorFromRGB(r, g, b, a)
    return imgui.ImVec4(r / 255, g / 255, b / 255, a / 255)
end

local colorCodes = {
    ['0'] = colorFromRGB(000,000,000,255),
    ['1'] = colorFromRGB(000,000,170,255),
    ['2'] = colorFromRGB(000,170,000,255),
    ['3'] = colorFromRGB(000,170,170,255),
    ['4'] = colorFromRGB(170,000,000,255),
    ['5'] = colorFromRGB(170,000,170,255),
    ['6'] = colorFromRGB(255,170,000,255),
    ['7'] = colorFromRGB(170,170,170,255),
    ['8'] = colorFromRGB(085,085,085,255),
    ['9'] = colorFromRGB(085,085,255,255),
    ['a'] = colorFromRGB(085,255,085,255),
    ['b'] = colorFromRGB(085,255,255,255),
    ['c'] = colorFromRGB(255,085,085,255),
    ['d'] = colorFromRGB(255,085,255,255),
    ['e'] = colorFromRGB(255,255,085,255),
    ['f'] = colorFromRGB(255,255,255,255),
    ['r'] = colorFromRGB(255,255,255,255),
}

--- Converts a text string into a list of colored text segments for use in IMGUI.
--- @param text string The input text to be formatted.
--- @param nocolor boolean (optional) If true, all text segments will have the default color.
--- @return table Returns a table containing colored text segments.
local function textToColorAndText(text, nocolor)
    local color = colorCodes[string.sub(text, 1, 1)] or colorCodes["r"]
    local text = string.sub(text, 2, #text)
    if(nocolor) then color = colorCodes["r"] end

    local txtList = {}

    local currentTxt = ""
    local wasSpace = false
    local c = ""

    for i = 1, #text do
        c = text:sub(i,i)

        if c == " " then 
            wasSpace = true
            currentTxt = currentTxt .. c
        else
            if(not wasSpace) then
                currentTxt = currentTxt .. c
            else
                table.insert(txtList, {
                    color = color,
                    text = currentTxt
                })
                currentTxt = c
            end
            wasSpace = false
        end
    end

    if(currentTxt ~= "") then
        table.insert(txtList, {
            color = color,
            text = currentTxt
        })
    end

    return txtList
end

--- Formats a text string with color codes and returns a list of colored text segments for use in IMGUI.
--- @param text string The input text to be formatted.
--- @param nocolor boolean (optional) If true, all text segments will have the default color.
--- @return table Returns a table containing colored text segments.
local function formatTextWithColor(text, nocolor)
    if(string.sub(text, 1, 1) ~= "^") then
        text = "^f" .. text
    end

    local txtList = {}

    local startIdx, endIdx = string.find(text, "%^")

    while startIdx do
        local partStr = string.sub(text, 1, startIdx - 1)
        if partStr ~= "" then
            for _, v in ipairs(textToColorAndText(partStr, nocolor)) do
                table.insert(txtList, v)
            end
        end

        text = string.sub(text, endIdx + 1)
        startIdx, endIdx = string.find(text, "%^")
    end

    for _, v in ipairs(textToColorAndText(text, nocolor)) do
        table.insert(txtList, v)
    end

    return txtList
end


--- Callback function for ImGui input text.
--- @param data table The input text data.
--- @return number Returns 0 to prevent further processing or 1 to allow further processing.
local inputCallbackC = ffi.cast("ImGuiInputTextCallback", function(data)
    if data.EventFlag == imgui.InputTextFlags_CallbackHistory then
        local prevHistoryPos = historyPos
        if data.EventKey == imgui.Key_UpArrow then
            historyPos = historyPos - 1
            if historyPos < 1 then
                if historyPos < 0 then
                    historyPos = #history
                else
                    historyPos = 1
                end
            end
        elseif data.EventKey == imgui.Key_DownArrow then
            if #history > 0 and historyPos == #history then
                ffi.fill(data.Buf, data.BufSize, 0)  -- Clear the buffer
                data.CursorPos = 0
                data.SelectionStart = 0
                data.SelectionEnd = 0
                data.BufTextLen = 0
                data.BufDirty = imgui.Bool(true)
                historyPos = -1
                return imgui.Int(0)  -- Return 0 to prevent further processing
            elseif historyPos == -1 then -- Empty, not on any history
                return imgui.Int(0)
            end

            historyPos = historyPos + 1
        end

        if #history > 0 and prevHistoryPos ~= historyPos then
            local t = history[historyPos]
            if type(t) ~= "string" then return imgui.Int(0) end
            local inplen = string.len(t)
            local inplenInt = imgui.Int(inplen)
            ffi.copy(data.Buf, t, math.min(data.BufSize - 1, inplen + 1))
            data.CursorPos = inplenInt
            data.SelectionStart = inplenInt
            data.SelectionEnd = inplenInt
            data.BufTextLen = inplenInt
            data.BufDirty = imgui.Bool(true);
        end
    elseif data.EventFlag == imgui.InputTextFlags_CallbackCharFilter and
        data.EventChar == 96 then -- 96 = '`'
        return imgui.Int(1)
    end
    return imgui.Int(0)
end)


local function clearHistory()
    log("I", "clearHistory", "Cleared chat history")
    history = {}
end

local function requestFocus()
    requestInputFocus = true
end
--- Adds a chat message to the chat history and the chat window.
--- @param username string The username of the sender.
--- @param message string The message content.
--- @param id number The ID of the message.
--- @param color string The color of the message.
local function addMessage(username, message, id, color)
    if(username == "Server") then
        message = formatTextWithColor(message, false)
    else
        message = formatTextWithColor(message, true)
    end

    local messageTable = {
        username = username,
        color = color,
        message = message,
        sentTime = os.time(),
        id = #M.chatMessages + 1
    }

    table.insert(M.chatMessages, messageTable)

    if MPUI.settings.window.showOnMessage then
        MPUI.bringToFront()
    end

    if not forceBottom and username ~= MPConfig:getNickname() then
        M.newMessageCount = M.newMessageCount + 1
    end
end

--- Sends a chat message.
--- @param message string The message to send.
local function sendChatMessage(message)
    if message[0] == 0 then return end

    message = ffi.string(message)

    if MPCoreNetwork.isMPSession() then
        local c = 'C:'..MPConfig.getNickname()..": "..message
        MPGameNetwork.send(c)
        TriggerClientEvent("ChatMessageSent", c)
    else
        local color = {[0] = 255, [1] = 0, [2] = 0, [3] = 255}
        addMessage("Daniel-W", " " .. message, 0, color) -- because `MPConfig.getNickname()` returns an empty string (only started happening)
    end

    wasMessageSent = true
    history[#history + 1] = ffi.string(chatMessageBuf)
    historyPos = -1
    ffi.copy(chatMessageBuf, "")
end

local scrollbarVisible = false

local function render()
    local style = imgui.GetStyle()

    local scrollbarSize = style.ScrollbarSize
    local uiScale = MPUI.settings.window.uiScale
    local avail = imgui.GetContentRegionAvail()
    local spaceSize = imgui.CalcTextSize(" ").x

    if imgui.BeginChild1("##ChatArea", imgui.ImVec2(0, avail.y - (30 * uiScale) + 5 * uiScale), false) then
        imgui.SetWindowFontScale(uiScale)
        scrollbarVisible = imgui.GetScrollMaxY() > 0
        local scrollbarPos = imgui.GetScrollY()

        if scrollbarPos >= imgui.GetScrollMaxY() then
            M.newMessageCount = 0
            wasMessageSent = false
            forceBottom = true
        else
            forceBottom = false
        end

        local pos = imgui.GetWindowPos()

        local availX = imgui.GetContentRegionAvail().x
        local availY = imgui.GetContentRegionAvail().y

        local clipMin = imgui.ImVec2(pos.x, pos.y)
        local clipMax = imgui.ImVec2(pos.x + availX + 10, pos.y + availY + 10)
        imgui.PushClipRect(clipMin, clipMax, true)

        -- Debug for viewing the ClipRect
        -- imgui.ImDrawList_AddRectFilled(imgui.GetWindowDrawList(), clipMin, clipMax, imgui.GetColorU322(imgui.ImVec4(255, 0, 0, 20)))

        -- Render Message | Time
        for _, message in ipairs(M.chatMessages) do
            local usernameSizeX = imgui.CalcTextSize(message.username).x
            local timestampStr = os.date("%H:%M", message.sentTime)
            local timestampSize = imgui.CalcTextSize(timestampStr).x
            local columnWidth = availX - timestampSize

            -- Chatbox Column
            imgui.Columns(2, "##ChatColumns", false)
            
            if scrollbarVisible then
                columnWidth = columnWidth - scrollbarSize
            end

            imgui.SetColumnWidth(0, columnWidth)
            
            if message.color then
                local color = imgui.ImVec4(message.color[0]/255, message.color[1]/255, message.color[2]/255, message.color[3]/255)
                imgui.TextColored(color, message.username .. ": ")
            else
                imgui.Text(message.username .. ": ")
            end

            -- Enable word wrapping
            imgui.PushTextWrapPos(imgui.GetContentRegionAvail().x)
            
            local currentWidth = usernameSizeX + spaceSize
            imgui.SameLine(currentWidth + spaceSize)

            for i=2, #message.message do
                local msg = message.message[i]
                local textSize = imgui.CalcTextSize(msg.text).x

                if (currentWidth + textSize <= columnWidth) then
                    imgui.SameLine(currentWidth + spaceSize)
                else
                    currentWidth = 0
                    -- imgui.SameLine(currentWidth + imgui.CalcTextSize(" ").x)
                end

                currentWidth = currentWidth + textSize
                imgui.TextColored(msg.color, msg.text)
            end
        
            -- Disable word wrapping
            imgui.PopTextWrapPos()
        
            if scrollToBottom or forceBottom then
                imgui.SetScrollHereY(1)
            end
        
            -- Time Column
            imgui.NextColumn()
            imgui.SetCursorPosX(imgui.GetCursorPosX() + imgui.GetContentRegionAvail().x / 2 - timestampSize / 2)

            imgui.Text(os.date("%H:%M", message.sentTime))
        
            imgui.Columns(1)
        end

        imgui.PopClipRect()
        imgui.EndChild()
    end

    imgui.PushStyleVar2(imgui.StyleVar_FramePadding, imgui.ImVec2(2, 2))
    imgui.PushStyleVar2(imgui.StyleVar_ItemSpacing, imgui.ImVec2(2, 0))
    imgui.PushStyleVar2(imgui.StyleVar_CellPadding, imgui.ImVec2(0, 0))

    imgui.PushStyleColor2(imgui.Col_FrameBg, imgui.ImVec4(MPUI.settings.colors.primaryColor.x, MPUI.settings.colors.primaryColor.y, MPUI.settings.colors.primaryColor.z, 1))

    local btnSize = 16 * uiScale

    if imgui.BeginChild1("##ChatInput", imgui.ImVec2(0, 30 * uiScale), false, imgui.WindowFlags_AlwaysAutoResize) then
        imgui.SetWindowFontScale(1)

        local spaceFromRight = btnSize + (style.ItemSpacing.x + 4)
        imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x - spaceFromRight)
        
        if imgui.InputText("##ChatInputMessage", chatMessageBuf, 256, imgui.InputTextFlags_EnterReturnsTrue + imgui.InputTextFlags_CallbackHistory, inputCallbackC) then
            sendChatMessage(chatMessageBuf)
            imgui.SetKeyboardFocusHere(-1)
        end

        if requestInputFocus then
            imgui.SetKeyboardFocusHere(-1)
            requestInputFocus = false
        end

        imgui.SameLine()

        if utils.imageButton(MPUI.uiIcons.send.texId, btnSize) then
            sendChatMessage(chatMessageBuf)
            imgui.SetKeyboardFocusHere(1)
        end

        imgui.EndChild()
    end

    imgui.PopStyleColor(1)
    imgui.PopStyleVar(3)


    -- ! Figure out why `imageButton` isn't accepting inputs.
    -- if wasMessageSent then
    --     heightOffset = 40

    --     if not forceBottom then
    --         imgui.SetCursorPos(
    --             imgui.ImVec2(
    --                 imgui.GetWindowWidth() - (scrollbarVisible and scrollbarSize or 0) - 32,
    --                 imgui.GetWindowHeight() - 60
    --             )
    --         )
            
    --         if utils.imageButton(MPUI.uiIcons.down.texId, btnSize) then
    --             scrollToBottom = true
    --             wasMessageSent = false
    --         end
    --     end
    -- else
    --     heightOffset = 20
    -- end
end

M.render = render
M.sendChatMessage = sendChatMessage
M.addMessage = addMessage
M.clearHistory = clearHistory
M.requestFocus = requestFocus

return M
