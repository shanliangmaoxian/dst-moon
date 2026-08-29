-- 小月亮 附魔：怀民
-- 你睡没睡，起来重睡
-- 每天晚上发消息「怀民：你睡没睡，起来重睡」然后给一个随机夜间buff

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_HUAIMIN", {
        name = "怀民",
        client_text = "怀\n民",
        desc = "夜晚随机buff：+50%伤害/移速或+30%减伤",
        check_desc = "你睡没睡，起来重睡！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "huaimin", "Legend_HUAIMIN", 1)
            if not owner._huaimin_hooked then
                owner._huaimin_hooked = true
                owner._huaimin_current_buff = nil
                owner._huaimin_buff_keys = {}

                -- 移除所有已激活的buff
                local function removeAllBuffs()
                    local hh = owner.components.hh_player
                    if not hh then return end
                    for _, key in ipairs(owner._huaimin_buff_keys or {}) do
                        hh:ReduceEffectValueByKey(key.key, key.value)
                    end
                    owner._huaimin_buff_keys = {}
                    owner._huaimin_current_buff = nil
                end

                -- 应用随机buff
                local function applyNightBuff()
                    if not _G.Moon_HasEffect(owner, "huaimin") then return end
                    removeAllBuffs()

                    local hh = owner.components.hh_player
                    if not hh then return end

                    local buffs = {
                        { key = "addComDamagePercent", value = 50, msg = "怀民叫你起来打架！伤害+50%！" },
                        { key = "addSpeedPercent", value = 50, msg = "怀民叫你起来散步！移速+50%！" },
                        { key = "addComDamagePercent", value = 25, msg = "怀民叫你起来赏月！伤害+25%，一起走走！" },
                    }

                    local chosen = buffs[math.random(#buffs)]
                    hh:AddEffectValueByKey(chosen.key, chosen.value)
                    table.insert(owner._huaimin_buff_keys, { key = chosen.key, value = chosen.value })
                    owner._huaimin_current_buff = chosen

                    if owner.components.talker then
                        owner.components.talker:Say("怀民：你睡没睡，起来重睡！" .. chosen.msg)
                    end
                end

                -- 每30秒检测昼夜变化（比每1秒省性能）
                owner._huaimin_check_task = owner:DoPeriodicTask(30, function()
                    if not _G.Moon_HasEffect(owner, "huaimin") then return end
                    local is_night = _G.TheWorld.state.isnight
                    local was_night = owner._huaimin_was_night

                    if is_night and not was_night then
                        -- 刚刚入夜，给buff
                        applyNightBuff()
                    elseif not is_night and was_night then
                        -- 天亮了，清除buff
                        removeAllBuffs()
                        if owner.components.talker then
                            owner.components.talker:Say("怀民：天亮了，我先睡了…")
                        end
                    end

                    owner._huaimin_was_night = is_night
                end)

                -- 如果装备时已经入夜，立即触发
                owner:DoTaskInTime(1, function()
                    if owner:IsValid() and _G.TheWorld.state.isnight then
                        owner._huaimin_was_night = true
                        applyNightBuff()
                    end
                end)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "huaimin", "Legend_HUAIMIN", 1)
            if not _G.Moon_HasEffect(owner, "huaimin") then
                -- 移除所有buff
                local hh = owner.components.hh_player
                if hh then
                    for _, b in ipairs(owner._huaimin_buff_keys or {}) do
                        hh:ReduceEffectValueByKey(b.key, b.value)
                    end
                end

                if owner._huaimin_check_task then
                    owner._huaimin_check_task:Cancel()
                    owner._huaimin_check_task = nil
                end

                owner._huaimin_buff_keys = {}
                owner._huaimin_current_buff = nil
                owner._huaimin_was_night = nil
                owner._huaimin_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_HUAIMIN", 0.008)
end)
