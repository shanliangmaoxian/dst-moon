-- 小月亮 快捷自杀
-- RPC + 聊天指令 (#zs, #kill, #自杀)

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_SUICIDE then return end

local function DoSuicide(player)
    if player and not player:HasTag("playerghost") and player.components.health then
        if player.components.talker then
            player.components.talker:Say("我杀死了我", 2)
        end
        player:PushEvent("death")
    elseif player and player:HasTag("playerghost") then
        if player.components.talker then
            player.components.talker:Say("死的不能再死了", 2)
        end
    end
end

-- RPC
AddModRPCHandler("LittleMoon", "Suicide", function(player)
    DoSuicide(player)
end)

-- 聊天指令监听 (已关闭：消息会泄露到公屏)
-- local Old_Networking_Say = _G.Networking_Say
-- _G.Networking_Say = function(guid, userid, name, prefab, message, colour, whisper, is_repeat, ...)
--     if Old_Networking_Say then
--         Old_Networking_Say(guid, userid, name, prefab, message, colour, whisper, is_repeat, ...)
--     end
--
--     if _G.TheWorld and _G.TheWorld.ismastersim and message and message:sub(1, 1) == "#" then
--         local cmd = message:sub(2):lower()
--         if cmd == "zs" or cmd == "kill" or cmd == "自杀" then
--             local player = _G.UserToPlayer(userid)
--             if player then
--                 DoSuicide(player)
--             end
--         end
--     end
-- end
