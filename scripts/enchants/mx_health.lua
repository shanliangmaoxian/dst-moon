-- 小月亮 附魔：毛旭
-- 血量上限+200 (可叠加)
--
-- 【修复说明】
-- 旧实现: 所有装备共用 source key "Legend_MX_HEALTH"，
--         un_equip_fn 中 maxhealth -= 200 是无条件的，
--         当 effect 计数丢失时(跨会话/事件重复)会导致血量异常叠加。
-- 修复后: 每件装备用独立 key (inst GUID)，用效果总量的差值来调整 maxhealth，
--         未实际减少计数时不移除血量，杜绝了血量叠加的可能。

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_MX_HEALTH", {
        name = "毛旭",
        client_text = "毛\n旭",
        desc = "geigei,带我吃鸭蛋",
        check_desc = "人物血量上限+200",
        can_add = false,
        only_one = false,           -- 可叠加 (多件装备各自生效)
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        -- 穿戴: 每件装备用 inst.GUID 作独立 source key
        --        用效果总量差值调整 maxhealth，防止重复触发叠加
        on_equip_fn = function(inst, owner, value)
            if not owner:IsValid() or not owner.components.health then return end
            local key = "MX_HEALTH_" .. inst.GUID
            -- 幂等检查: 同一装备实例重复触发时不重复加血
            local mx_table = "mx_health_sources"
            if owner[mx_table] and owner[mx_table][key] then return end
            _G.Moon_AddEffect(owner, "mx_health", key, 200)
            local old_percent = owner.components.health:GetPercent()
            owner.components.health.maxhealth = math.min(owner.components.health.maxhealth + 200, 60000)
            owner.components.health:SetPercent(old_percent)
        end,
        -- 脱下: 只在实际减少了 effect 计数时才扣减 maxhealth
        un_equip_fn = function(inst, owner, value)
            if not owner:IsValid() or not owner.components.health then return end
            local key = "MX_HEALTH_" .. inst.GUID
            local old_total = _G.Moon_GetTotalEffectValue(owner, "mx_health")
            _G.Moon_ReduceEffect(owner, "mx_health", key, 200)
            local new_total = _G.Moon_GetTotalEffectValue(owner, "mx_health")
            local delta = old_total - new_total
            if delta > 0 then
                local old_percent = owner.components.health:GetPercent()
                owner.components.health.maxhealth = math.max(owner.components.health.maxhealth - delta, 1)
                owner.components.health:SetPercent(old_percent)
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_MX_HEALTH", 0.01)
end)
