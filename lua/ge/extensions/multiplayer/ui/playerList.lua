-- Copyright (C) 2024 BeamMP Ltd., BeamMP team and contributors.
-- Licensed under AGPL-3.0 (or later), see <https://www.gnu.org/licenses/>.
-- SPDX-License-Identifier: AGPL-3.0-or-later

--- multiplayer_ui_playerList API.
--- Author of this documentation is Titch
--- @module multiplayer_ui_playerList
--- @usage updatePlayerList(jsonData) -- internal access
--- @usage multiplayer_ui_playerList.updatePlayerList(jsonData) -- external access

local M = {}

local imgui = ui_imgui
local players = {} -- contains name and ping for each entry

--- Updates the player list based on the provided JSON data.
--- @param jsonData table The JSON data containing player information.
local function updatePlayerList(jsonData)
    local playerList = {}
    for name, ping in pairs(jsonData) do
        playerList[#playerList + 1] = { name, ping }
    end

    table.sort(playerList, function(a, b)
        return a[1] < b[1] -- 1 is the name
    end)
    
    players = playerList
end

local function render()
    local hw = imgui.GetWindowWidth() / 2

    imgui.SetCursorPosX((imgui.GetWindowWidth() - imgui.CalcTextSize("Name").x) / 4)
    imgui.Text("Name")
    imgui.SameLine()

    imgui.SetCursorPosX((hw + hw / 2) - imgui.CalcTextSize("Ping").x)
    imgui.Text("Ping")

    imgui.Separator()

    if imgui.BeginChild1("PlayerList", imgui.ImVec2(0, 0), false) then
        for _, player in ipairs(players) do
            local name = player[1]
            local ping = tostring(player[2])

            imgui.SetCursorPosX((imgui.GetWindowWidth() - imgui.CalcTextSize(name).x) / 4)
            imgui.Text(name)
            imgui.SameLine()
            imgui.SetCursorPosX((imgui.GetWindowWidth() - imgui.CalcTextSize(ffi.string(ping)).x - hw / 2))
            imgui.Text(ping)
        end
    end
end

M.render = render
M.updatePlayerList = updatePlayerList

return M
