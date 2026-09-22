-- 小月亮 附魔：蔷薇偶像恋恋酱
-- 基础数值：暴击+13%，爆伤+14%，移速+52%
-- 获取（v1简化版）：已附魔「无意识的恋恋」时掷骰子，roll 出 5 或 14 直接获得
--   （fumo.txt 原案还要求消耗5个恋恋石+世界30天，v2 再补）
-- 彩蛋：roll5/roll14 文本提示；获得成功时公屏公告
-- TODO：与"无意识"状态的联动效果（攻击距离20码/突进背刺/斩杀）v2 实装
-- "我要推一辈子的蔷薇偶像！"

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

local EFFECT_ID = "Legend_LLJ"
local EFFECT_KEY = "llj"

-- =========================================================
-- 骰子事件监听：有恋恋时 roll 出 5/14 → 获得恋恋酱
-- =========================================================
AddPlayerPostInit(function(inst)
    if not _G.TheWorld.ismastersim then return end
    inst:ListenForEvent("moon_dice_roll", function(player, data)
        local value = data and data.value
        if value ~= 5 and value ~= 14 then return end
        if not player:IsValid() then return end
        -- 已拥有恋恋酱的不再发
        if _G.Moon_HasEffect(player, EFFECT_KEY) then return end
        -- 需要处于"无意识"（已附魔无意识的恋恋）状态
        if not _G.Moon_HasEffect(player, "lianlian") then return end

        if value == 5 and player.components.talker then
            player.components.talker:Say("哒哒哒哒哒哒哒，所以说是恋恋胜利啦！")
        elseif value == 14 and player.components.talker then
            player.components.talker:Say("哒哒哒哒哒哒哒，就好像是陷入恋爱啦！")
        end

        local success, stone = _G.pcall(_G.HHSpawnStoneById, EFFECT_ID)
        if success and stone and player.components.inventory then
            player.components.inventory:GiveItem(stone, nil, player:GetPosition())
            -- 公屏公告
            _G.pcall(function()
                _G.TheNet:Announce("爱 love heart 恋 魔法 wink chuu")
            end)
        end
    end)
end)

-- =========================================================
-- 附魔注册
-- =========================================================
AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect(EFFECT_ID, {
        name = "蔷薇偶像恋恋酱",
        client_text = "恋恋\n酱",
        desc = "暴击+13%，爆伤+14%，移速+52%\n与「无意识的恋恋」联动效果开发中",
        check_desc = "有「无意识的恋恋」时掷骰子，roll出5或14获得\n我要推一辈子的蔷薇偶像！",
        can_add = false,
        only_one = true,
        is_special = true, -- 专属获取：骰子 roll 5/14（需恋恋在场），不进掉落池
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, EFFECT_KEY, EFFECT_ID, 1)
            if not owner._llj_inited then
                owner._llj_inited = true
                local hh = owner.components.hh_player
                if hh then
                    hh:AddEffectValueByKey("criticalHitRate", 13)
                    hh:AddEffectValueByKey("criticalHitEffect", 14)
                    hh:AddEffectValueByKey("addSpeedPercent", 52)
                end
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, EFFECT_KEY, EFFECT_ID, 1)
            if not _G.Moon_HasEffect(owner, EFFECT_KEY) then
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("criticalHitRate", 13)
                    hh:ReduceEffectValueByKey("criticalHitEffect", 14)
                    hh:ReduceEffectValueByKey("addSpeedPercent", 52)
                end
                owner._llj_inited = nil
            end
        end,
    })

    -- 专属获取，不进掉落池
    _G.Moon_RegisterEnchantDrop(EFFECT_ID, 0)
end)
