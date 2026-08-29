-- 小月亮 附魔：番茄炒蛋
-- san值恢复8倍，san消耗减半，每5秒回复20点san

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_FQCD_SANITY", {
        name = "番茄炒蛋",
        client_text = "番\n茄",
        desc = "一盘热腾腾的番茄炒蛋\n酸甜咸香，最抚凡人心\nsan恢复8倍 消耗减半 每5秒+20san",
        check_desc = "家的味道，最治愈～",
        can_add = false,
        only_one = true,                -- 唯一
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "fqcd_sanity", "Legend_FQCD_SANITY", 1)
            if not owner._fqcd_sanity_hooked then
                owner._fqcd_sanity_hooked = true
                local sanity = owner.components.sanity
                if sanity then
                    -- san恢复 8倍速
                    sanity.externalmodifiers:SetModifier("番茄炒蛋", 8)
                    -- san消耗减半
                    if not sanity._fqcd_DoDelta then
                        local original_do_delta = sanity.DoDelta
                        sanity._fqcd_DoDelta = original_do_delta
                        sanity.DoDelta = function(self, delta, overtime, ...)
                            if delta < 0 then
                                delta = delta * 0.5
                            end
                            return original_do_delta(self, delta, overtime, ...)
                        end
                    end
                    -- 每5秒回20san
                    if not owner._fqcd_regen_task then
                        owner._fqcd_regen_task = owner:DoPeriodicTask(5, function()
                            if _G.Moon_HasEffect(owner, "fqcd_sanity") and owner.components.sanity then
                                owner.components.sanity:DoDelta(20)
                            end
                        end)
                    end
                end
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "fqcd_sanity", "Legend_FQCD_SANITY", 1)
            if not _G.Moon_HasEffect(owner, "fqcd_sanity") then
                local sanity = owner.components.sanity
                if sanity then
                    sanity.externalmodifiers:RemoveModifier("番茄炒蛋")
                    if sanity._fqcd_DoDelta then
                        sanity.DoDelta = sanity._fqcd_DoDelta
                        sanity._fqcd_DoDelta = nil
                    end
                end
                if owner._fqcd_regen_task then
                    owner._fqcd_regen_task:Cancel()
                    owner._fqcd_regen_task = nil
                end
                owner._fqcd_sanity_hooked = nil
            end
        end,
    })

    -- 精英/Boss 掉落 (3%)
    _G.Moon_RegisterEnchantDrop("Legend_FQCD_SANITY", 0.01)
end)
