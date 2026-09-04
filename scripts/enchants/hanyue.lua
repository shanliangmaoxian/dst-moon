-- 小月亮 附魔：寒月公主
-- 攻击冻结目标(永冻)：每秒扣2%最大生命(有托托莉则2%噩梦真伤)
-- 每次攻击附带666真伤 | 暴击率+66% 爆伤+666% | 雪花特效
-- 托托莉检测参考一枝独秀(yzdx)

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

local equip_util = require("moon_utils/asserts")

local FROST_DURATION = 8    -- 永冻持续时间(秒)，攻击会刷新
local FROST_PERCENT = 0.02  -- 每秒扣血百分比(2%最大生命)
local TRUE_DMG = 666        -- 每次攻击附带的真伤
local CRIT_RATE = 66        -- 暴击率(暴击率+66%)
local CRIT_EFFECT = 666     -- 爆伤(额外+666%)

local MEMORY_KEY = "LMOON_STONE_HANYUE_TEST_MEMORY"
local PROGRESS_KEY = "LMOON_STONE_HANYUE_TEST_PROGRESS"

local EFFECT_NAME = "Legend_HANYUE"
local EFFECT_TEST_NAME = "Legend_HANYUE_TEST"

local EFFECT_TEST_MEMORY_CAP = 5
local EFFECT_TEST_SCORE = 40

local function slice(arr, start, stop)
    local result = {}
    stop = stop or #arr

    stop = stop <= 0 and math.max(1, #arr + stop + 1) or stop
    start = start <= 0 and math.max(1, #arr + start + 1) or start

    for i = start, stop do table.insert(result, arr[i]) end

    return result
end

local function upgrade_effect(weapon)
    if not weapon.components or not weapon.components.hh_equip then return end
    local cp_hh_equip = weapon.components.hh_equip
    cp_hh_equip:ReplaceEffectByName(EFFECT_TEST_NAME, EFFECT_NAME)
end

local function do_delta_score(weapon, killer, data)
    if not weapon.components then return end
    if not killer.components and not killer.components.health then return end
    if not killer.components and not killer.components.hh_equip then return end

    local cp_counter = weapon.components.counter;
    local cp_custom_data = weapon.components.custom_data;
    local cp_hh_equip = weapon.components.hh_equip

    -- 记忆中杀过的 boss
    local memory = cp_custom_data:Get(MEMORY_KEY) or {}
    local progress = cp_counter:GetCount(PROGRESS_KEY)

    local victim = data.victim
    if victim:IsValid() and not victim:HasTag("player") and
        victim:HasTag("epic") and not killer.components.health:IsDead() then

        if table.contains(memory, victim.prefab) then -- 已在记忆中就忽略
            return
        end

        -- 更新记忆
        table.insert(memory, victim.prefab)
        memory = slice(memory, -5, 0) -- 仅保留最新的 5 个，越靠后越新

        cp_counter:DoDelta(PROGRESS_KEY, 1)
        cp_custom_data:Set(MEMORY_KEY, memory)

        -- 更新试炼进度，展示在武器详情页的信息
        cp_hh_equip:UpdateEffectValueByName(EFFECT_TEST_NAME,
                                            cp_counter:GetCount(PROGRESS_KEY))

        -- 如果达到分数就升级效果
        if cp_counter:GetCount(PROGRESS_KEY) >= EFFECT_TEST_SCORE then
            upgrade_effect(weapon)
        end
    end
end

local function get_prefab_readable_name(prefab)
    return STRINGS.NAMES[string.upper(prefab)] or "??"
end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_HANYUE", {
        name = "寒月公主",
        client_text = "寒月\n公主",
        desc = "攻击冻结目标(永冻)每秒扣2%最大生命\n有托托莉则2%噩梦伤害 | 暴击+66% 爆伤+666%\n每次攻击附带666真伤",
        check_desc = "寒月照，万物霜！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(equip)
            if not equip_util.is_equipslot(equip, "HANDS") then
                return false, "仅能附魔在武器栏"
            end
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "hanyue", "Legend_HANYUE", 1)
            if not owner._hanyue_inited then
                owner._hanyue_inited = true
                owner._hanyue_marks = {}
                owner._hanyue_has_totori = false

                -- 确保 ttl_wanly_damage 组件存在（托托莉噩梦伤害组件，由托托莉mod提供）
                if not owner.components.ttl_wanly_damage then
                    _G.pcall(function() owner:AddComponent("ttl_wanly_damage") end)
                end

                -- 暴击爆伤(HH框架属性)
                local hh = owner.components.hh_player
                if hh then
                    hh:AddEffectValueByKey("criticalHitRate", CRIT_RATE)
                    hh:AddEffectValueByKey("criticalHitEffect", CRIT_EFFECT)
                end

                -- 雪花特效：目标头顶飘雪(优先 snow_fx，不存在则用冰刺特效兜底)
                -- local function spawnSnowFx(target)
                --     if not target or not target.Transform then return end
                --     local fx = _G.SpawnPrefab("snow_fx")
                --     if not fx then
                --         fx = _G.SpawnPrefab("deerclops_icespike_fx")
                --     end
                --     if fx and fx.Transform then
                --         local x, y, z = target.Transform:GetWorldPosition()
                --         fx.Transform:SetPosition(x, y + 1.5, z)
                --         fx:DoTaskInTime(1.5, function()
                --             if fx:IsValid() then
                --                 fx:Remove()
                --             end
                --         end)
                --     end
                -- end

                -- 永冻排除名单：这些生物不吃冰冻(仍会吃到真伤和每秒扣血)
                local FROST_EXCLUDE_PREFABS = {
                    lunarthrall_plant = true, -- 亮茄
                }

                -- 冻结目标
                local function freezeTarget(target)
                    if FROST_EXCLUDE_PREFABS[target.prefab] then return end
                    local fz = target.components.freezable
                    if fz then
                        fz:AddColdness(1)
                        fz:Freeze(FROST_DURATION)
                    end
                end

                -- 攻击触发：666真伤 + 永冻标记 + 雪花特效
                owner._hanyue_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "hanyue") then return end
                    local target = data and data.target
                    if not target or not target:IsValid() then return end
                    if target:HasTag("player") then return end -- 只对怪物生效
                    local health = target.components.health
                    if not health or health:IsDead() then return end

                    -- 托托莉检测(参考一枝独秀)：有托托莉则每秒2%伤害变为噩梦真伤
                    local has_totori = false
                    for _, v in ipairs(_G.AllPlayers) do
                        if v:IsValid() then
                            local prefab = (v.prefab or ""):lower()
                            if prefab:find("totooria") or prefab:find("tutuoli") or prefab:find("totori") or prefab:find("torori") then
                                has_totori = true
                                break
                            end
                        end
                    end
                    owner._hanyue_has_totori = has_totori

                    -- 每次攻击附带666真伤(无视护甲)
                    if health.DoHHDelta then
                        health:DoHHDelta(-TRUE_DMG, owner, nil)
                    else
                        health:DoDelta(-TRUE_DMG, false, "hanyue_true")
                    end

                    -- 永冻标记(攻击刷新持续时长)
                    owner._hanyue_marks[target] = _G.GetTime() + FROST_DURATION
                    freezeTarget(target)
                end
                owner:ListenForEvent("onattackother", owner._hanyue_attack_handler)

                -- 每秒一跳：保持冻结 + 2%最大生命伤害 + 雪花特效
                owner._hanyue_tick_task = owner:DoPeriodicTask(1, function()
                    if not _G.Moon_HasEffect(owner, "hanyue") then return end
                    local now = _G.GetTime()
                    local remove_list = {}
                    for target, till in pairs(owner._hanyue_marks) do
                        local valid = target and target:IsValid()
                        local health = valid and target.components.health
                        if not valid or not health or health:IsDead() or now >= till then
                            remove_list[#remove_list + 1] = target
                        else
                            freezeTarget(target)
                            local max_hp = health.maxhealth or 100
                            local dmg = max_hp * FROST_PERCENT
                            if owner._hanyue_has_totori then
                                -- 托托莉噩梦伤害（ttl_wanly_damage 伤害模式）
                                local ttl = owner.components.ttl_wanly_damage
                                if ttl then
                                    ttl:ApplyTTL_wanly_damage(target, dmg)
                                else
                                    health:DoDelta(-dmg, false, "hanyue_frost")
                                end
                            else
                                health:DoDelta(-dmg, false, "hanyue_frost")
                            end
                        end
                    end
                    for _, t in ipairs(remove_list) do
                        owner._hanyue_marks[t] = nil
                    end
                end)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "hanyue", "Legend_HANYUE", 1)
            if not _G.Moon_HasEffect(owner, "hanyue") then
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("criticalHitRate", CRIT_RATE)
                    hh:ReduceEffectValueByKey("criticalHitEffect", CRIT_EFFECT)
                end

                if owner._hanyue_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._hanyue_attack_handler)
                    owner._hanyue_attack_handler = nil
                end
                if owner._hanyue_tick_task then
                    owner._hanyue_tick_task:Cancel()
                    owner._hanyue_tick_task = nil
                end

                owner._hanyue_marks = nil
                owner._hanyue_has_totori = nil
                owner._hanyue_inited = nil
            end
        end,
    })

    GLOBAL.AddSpecialEquipEffect(EFFECT_TEST_NAME, {
        name = "寒月试炼",
        client_text = "寒月\n试炼",
        desc = string.format("完成试炼此效果变为【寒月公主】\n试炼: 使用该武器交替击杀 5 种不同名 BOSS %s 次", EFFECT_TEST_SCORE),
        recipes = {"moon_effect_stone_hanyue_test"},
        desc_dync = function(equip, effect_value)
            local cp_custom_data = equip.components.custom_data
            local memory_list = table.map(cp_custom_data:Get(MEMORY_KEY) or {}, get_prefab_readable_name)
            local memory_list_str = table.concat(memory_list, ", ")
            return string.format(
                       "完成试炼此效果变为【寒月公主】。\n=============寒月试炼=============\n试炼: 使用该武器交替击杀 5 种不同名 BOSS：%s/%s\n最近击杀：%s\n================================",
                       effect_value, EFFECT_TEST_SCORE, memory_list_str)
        end,
        check_desc = "武器栏",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = {0.8, 0, 0.8, 1},
        check_equip_can_add = function(equip)
            if not equip_util.is_equipslot(equip, "HANDS") then
                return false, "仅能附魔在武器栏"
            end
            return true, "满足条件"
        end,
        start_fn = function(inst, value)
            if inst.components and not inst.components.custom_data then
                inst:AddComponentDynamic("custom_data")
                inst.components.custom_data:Set(MEMORY_KEY, {})
            end
            if inst.components and not inst.components.counter then
                inst:AddComponentDynamic("counter")
            end
            if inst.components and inst.components.hh_equip then
                -- 更新初值
                inst.components.hh_equip:UpdateEffectValueByName(
                    EFFECT_TEST_NAME, value or 0)
            end
        end,
        end_fn = function(inst, value)
            inst.components.custom_data:Clear(MEMORY_KEY)
            inst.components.counter:Clear(PROGRESS_KEY)
        end,
        on_equip_fn = function(inst, owner, value)
            local weapon = inst
            inst.__lmoon_stone_hanyue_on_killed =
                function(inst, data)
                    do_delta_score(weapon, inst, data)
                end
            owner:ListenForEvent("killed", inst.__lmoon_stone_hanyue_on_killed)
        end,
        un_equip_fn = function(inst, owner, value)
            if inst.__lmoon_stone_hanyue_on_killed then
                owner:RemoveEventCallback("killed",
                                          inst.__lmoon_stone_hanyue_on_killed)
            end
        end
    })

    _G.Moon_RegisterEnchantDrop(EFFECT_NAME, 0) -- 掉落率0
    _G.Moon_RegisterEnchantDrop(EFFECT_TEST_NAME, 0) -- 掉落率0
end)
