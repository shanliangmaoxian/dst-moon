-- 小月亮 附魔：等等秋零
-- 我是浅笑我怕谁！
-- 暴击率+30%，暴击效果+100%(暴击3倍)
-- 每次攻击附带50点真实伤害(无视防御穿刺)
-- 真伤可被"破虚"附魔转换(每50点→+5%暴击率+10%暴击效果)

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_DENGDENGQIULING", {
        name = "等等秋零",
        client_text = "等等\n秋零",
        desc = "我是浅笑我怕谁！\n浅笑一怒:暴击率+30%,暴击效果+100%(暴击3倍)\n穿刺之刃:每次攻击附带50点真实伤害(无视防御)\n真伤可被破虚转换(每50点→+5%暴击率+10%暴击效果)",
        check_desc = "我是浅笑我怕谁！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "dengdengqiuling", "Legend_DENGDENGQIULING", 1)
            if not owner._dengdengqiuling_hooked then
                owner._dengdengqiuling_hooked = true
                local hh = owner.components.hh_player
                if hh then
                    hh:AddEffectValueByKey("criticalHitRate", 30)
                    hh:AddEffectValueByKey("criticalHitEffect", 100)
                    hh:AddEffectValueByKey("trueDamageNum", 50)
                end
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "dengdengqiuling", "Legend_DENGDENGQIULING", 1)
            if not _G.Moon_HasEffect(owner, "dengdengqiuling") then
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("criticalHitRate", 30)
                    hh:ReduceEffectValueByKey("criticalHitEffect", 100)
                    hh:ReduceEffectValueByKey("trueDamageNum", 50)
                end
                owner._dengdengqiuling_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_DENGDENGQIULING", 0.01)
end)
