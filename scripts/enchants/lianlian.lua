-- 小月亮 附魔：无意识的恋恋
-- 免疫生物仇恨，主动攻击解除，恢复cd10s；玩家移速+100%，快速交互
-- 获取：投骰子 roll 出数字 5 和 14 后，公屏打字"哈德曼的妖怪少女"或"5.14"
-- "有注意到恋恋了嘛～"
-- 注：骰子系统由 幸运橙汁(xingyunchengzhi.lua) 的 Moon_DoDiceRoll 提供，
--     本文件监听其广播的 moon_dice_roll 事件；公屏聊天检测 hook Networking_Say。

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

local STEALTH_CD = 10 -- 免疫仇恨被主动攻击解除后的恢复cd（秒）

-- =========================================================
-- Part 1: 骰子事件监听（记录 roll 出 5 和 14）
-- =========================================================
AddPlayerPostInit(function(inst)
    if not _G.TheWorld.ismastersim then return end
    inst._lianlian_roll5 = false
    inst._lianlian_roll14 = false
    inst:ListenForEvent("moon_dice_roll", function(_, data)
        local value = data and data.value
        if value == 5 then
            inst._lianlian_roll5 = true
            if inst.components.talker then
                inst.components.talker:Say("roll出5！再roll出14，公屏打出'哈德曼的妖怪少女'或'5.14'获取恋恋～")
            end
        elseif value == 14 then
            inst._lianlian_roll14 = true
            if inst.components.talker then
                inst.components.talker:Say("roll出14！公屏打出'哈德曼的妖怪少女'或'5.14'获取恋恋～")
            end
        end
    end)
end)

-- =========================================================
-- Part 2: 公屏打字检测（满足条件后给予附魔石）
-- =========================================================
local _Old_Networking_Say_LIANLIAN = _G.Networking_Say
_G.Networking_Say = function(guid, userid, name, prefab, message, colour, whisper, is_repeat, ...)
    if _G.TheWorld and _G.TheWorld.ismastersim
            and type(message) == "string"
            and (message == "哈德曼的妖怪少女" or message == "5.14")
    then
        local player = _G.UserToPlayer(userid)
        if player and player:IsValid() then
            if player._lianlian_roll5 and player._lianlian_roll14 then
                local success, stone = _G.pcall(_G.HHSpawnStoneById, "Legend_LIANLIAN")
                if success and stone and player.components.inventory then
                    player.components.inventory:GiveItem(stone, nil, player:GetPosition())
                    if player.components.talker then
                        player.components.talker:Say("有注意到恋恋了嘛～")
                    end
                end
                player._lianlian_roll5 = false
                player._lianlian_roll14 = false
            elseif player.components.talker then
                player.components.talker:Say("还需要roll出5和14才能注意到恋恋哦～")
            end
        end
    end
    if _Old_Networking_Say_LIANLIAN then
        _Old_Networking_Say_LIANLIAN(guid, userid, name, prefab, message, colour, whisper, is_repeat, ...)
    end
end

-- =========================================================
-- Part 3: 附魔注册
-- =========================================================
AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_LIANLIAN", {
        name = "无意识的恋恋",
        client_text = "恋恋",
        desc = "免疫生物仇恨(主动攻击解除,10秒后恢复)\n玩家移速+100% 快速交互",
        check_desc = "有注意到恋恋了嘛～",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.6, 0.9, 0.6, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "lianlian", "Legend_LIANLIAN", 1)
            if not owner._lianlian_inited then
                owner._lianlian_inited = true
                owner._lianlian_stealth_on = false
                owner._lianlian_stealth_until = 0

                -- 玩家移速+100%
                if owner.components.locomotor then
                    owner.components.locomotor:SetExternalSpeedMultiplier(owner, "lianlian_speed", 2.0)
                end

                -- 快速交互（HH fast_act，参考 3096210166 / laodong）
                local hh = owner.components.hh_player
                if hh then
                    hh:AddEffectValueByKey("fast_act", 1)
                end
                _G.pcall(function()
                    if owner.userid then
                        _G.SendModRPCToClient(_G.CLIENT_MOD_RPC["hh_rpc"]["hh_client_value"], owner.userid, "hh_fast_act", true)
                    end
                end)

                -- 免疫生物仇恨（原版：stealth tag + combat.shouldavoidaggrofn）
                local function stealthOn()
                    if owner._lianlian_stealth_on then return end
                    if not owner:HasTag("stealth") then
                        owner:AddTag("stealth")
                        owner._lianlian_own_stealth = true
                    end
                    if owner.components.combat then
                        owner.components.combat.shouldavoidaggrofn = function() return true end
                    end
                    owner._lianlian_stealth_on = true
                end
                local function stealthOff()
                    if not owner._lianlian_stealth_on then return end
                    if owner._lianlian_own_stealth then
                        owner:RemoveTag("stealth")
                        owner._lianlian_own_stealth = nil
                    end
                    if owner.components.combat then
                        owner.components.combat.shouldavoidaggrofn = nil
                    end
                    owner._lianlian_stealth_on = false
                end

                -- 主动攻击 → 解除免疫仇恨，10秒后自动恢复
                owner._lianlian_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "lianlian") then return end
                    if owner._lianlian_stealth_on then
                        stealthOff()
                        owner._lianlian_stealth_until = _G.GetTime() + STEALTH_CD
                        if owner.components.talker then
                            owner.components.talker:Say("被发现了！10秒后重新隐身...")
                        end
                    end
                end
                owner:ListenForEvent("onattackother", owner._lianlian_attack_handler)

                -- 周期检测：cd 结束后恢复隐身
                owner._lianlian_stealth_task = owner:DoPeriodicTask(0.5, function()
                    if not _G.Moon_HasEffect(owner, "lianlian") then return end
                    if not owner._lianlian_stealth_on and _G.GetTime() >= owner._lianlian_stealth_until then
                        stealthOn()
                    end
                end)

                stealthOn()
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "lianlian", "Legend_LIANLIAN", 1)
            if not _G.Moon_HasEffect(owner, "lianlian") then
                -- 移速恢复
                if owner.components.locomotor then
                    owner.components.locomotor:RemoveExternalSpeedMultiplier(owner, "lianlian_speed")
                end

                -- 快速交互恢复
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("fast_act", 1)
                end
                _G.pcall(function()
                    if owner.userid then
                        local still_fast = hh and hh.HasSpecialEffect and hh:HasSpecialEffect("fast_act")
                        _G.SendModRPCToClient(_G.CLIENT_MOD_RPC["hh_rpc"]["hh_client_value"], owner.userid, "hh_fast_act", still_fast or false)
                    end
                end)

                -- 免疫仇恨恢复
                if owner._lianlian_own_stealth then
                    owner:RemoveTag("stealth")
                    owner._lianlian_own_stealth = nil
                end
                if owner.components.combat then
                    owner.components.combat.shouldavoidaggrofn = nil
                end

                if owner._lianlian_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._lianlian_attack_handler)
                    owner._lianlian_attack_handler = nil
                end
                if owner._lianlian_stealth_task then
                    owner._lianlian_stealth_task:Cancel()
                    owner._lianlian_stealth_task = nil
                end

                owner._lianlian_stealth_on = nil
                owner._lianlian_stealth_until = nil
                owner._lianlian_inited = nil
            end
        end,
    })

    -- 不通过 Boss 掉落获取（仅骰子+公屏打字）
    _G.Moon_RegisterEnchantDrop("Legend_LIANLIAN", 0)
end)
