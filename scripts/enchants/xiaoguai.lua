-- 小月亮 附魔：七步之内（小乖）
-- 攻击速度+100%（HH框架上限2倍），仅小樱(ccs)可用，仅能附魔在 ccs_magic_wand3 上
-- 获取：击败Boss 1%概率掉落

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_XIAOGUAI", {
        name = "七步之内",
        client_text = "小\n乖",
        desc = "攻击速度+100%%！\n仅小樱可用，仅限魔杖附魔\n七步之内，又快又准！",
        check_desc = "七步之内又快又准！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            if inst.prefab == "ccs_magic_wand3" then
                return true, "满足条件"
            end
            return false, "只能附魔在小樱的魔杖上"
        end,
        on_equip_fn = function(inst, owner, value)
            if owner.prefab ~= "ccs" then
                if owner.components.talker then
                    owner.components.talker:Say("只有小樱才能驾驭小乖的力量！")
                end
                return
            end
            _G.Moon_AddEffect(owner, "xiaoguai", "Legend_XIAOGUAI", 1)

            -- HH 框架 atk_speed：100 = +100% = 2倍攻速（框架上限）
            local hh = owner.components.hh_player
            if hh then
                hh:AddEffectValueByKey("atk_speed", 100)
            end

            if not owner._xiaoguai_hooked then
                owner._xiaoguai_hooked = true
                if owner.components.talker then
                    owner.components.talker:Say("小乖来啦！七步之内，唯快不破！")
                end
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "xiaoguai", "Legend_XIAOGUAI", 1)
            if not _G.Moon_HasEffect(owner, "xiaoguai") then
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("atk_speed", 100)
                end
                owner._xiaoguai_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_XIAOGUAI", 0.01)
end)
