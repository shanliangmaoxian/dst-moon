-- 小月亮 附魔：寒月公主
-- 攻击冻结目标(永冻)：每次攻击扣2%最大生命(有托托莉则2%噩梦真伤)
-- 每次攻击附带666真伤 | 暴击率+66% 爆伤+666% | 雪花特效
-- 偷取：每次攻击1%概率偷取目标战利品

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end
local is_hanyue_level_simple = CFG.HANYUE_TEST_LEVEL == 0
local BORING_SCORE = is_hanyue_level_simple and 1 or 0
local NOVEL_SCORE = 3

local equip_util = require("moon_utils/asserts")

local FROST_DURATION = 8    -- 永冻持续时间(秒)，攻击会刷新
local FROST_PERCENT = 0.02  -- 每次攻击扣血百分比(2%最大生命)
local TRUE_DMG = 666        -- 每次攻击附带的真伤
local CRIT_RATE = 66        -- 暴击率(暴击率+66%)
local CRIT_EFFECT = 666     -- 爆伤(额外+666%)

-- 偷取参数
local GREED_STEAL_CHANCE = 0.01     -- 每次攻击 1% 概率偷取目标战利品
local GREED_STEAL_COOLDOWN = 1      -- 偷取冷却 1 秒

local MEMORY_KEY = "LMOON_STONE_HANYUE_TEST_MEMORY"
local PROGRESS_KEY = "LMOON_STONE_HANYUE_TEST_PROGRESS"

local EFFECT_NAME = "Legend_HANYUE"
local EFFECT_TEST_NAME = "Legend_HANYUE_TEST"

local EFFECT_TEST_MEMORY_CAP = 5
local EFFECT_TEST_SCORE = 120

local function memory_display_str(memory)
    local readable_name = STRINGS.NAMES[string.upper(memory.prefab)] or "??"
    if memory.count > 1 then
        return string.format("%s*%s", readable_name, memory.count or 1)
    end
    return string.format("%s", readable_name)
end

local function get_memory_readable_name(memory)
    return STRINGS.NAMES[string.upper(memory.prefab)] or "??"
end

local function is_memory_same_by(prefab)
    return function (current_memory)
        return prefab == current_memory.prefab
    end
end

-- 查找试炼词条(兼容旧存档): 精确匹配失败时, 按"配置同一性"(别名键 __recipe__*
-- 与真名共享同一份配置表)或名字前缀(改版前旧 id 已无配置)兜底识别
local function find_test_effect(hh_equip)
    local info = hh_equip:FindEffect(EFFECT_TEST_NAME)
    if info then return info end

    for slot_index, effect in ipairs(hh_equip.equip_buff_list) do
        local name = effect and effect.name
        if name and name ~= EFFECT_NAME then
            local cfg = HH_EQUIP_BUFF_LIST and HH_EQUIP_BUFF_LIST[name]
            if (cfg and cfg == HH_EQUIP_BUFF_LIST[EFFECT_TEST_NAME])
                or (not cfg and name:find("HANYUE", 1, true)) then
                return {slot_index = slot_index, effect = effect}
            end
        end
    end
end

local function upgrade_effect(weapon)
    if not weapon.components or not weapon.components.hh_equip then return end
    local hh_equip = weapon.components.hh_equip
    local info = find_test_effect(hh_equip)
    if not info then
        print("[寒月试炼] upgrade_effect: 未找到试炼词条, 跳过升级")
        return
    end

    local old_name = info.effect.name
    if old_name ~= EFFECT_TEST_NAME then
        print("[寒月试炼] 旧存档词条名: " .. tostring(old_name) .. " -> 兼容升级")
    end

    if HH_EQUIP_BUFF_LIST and HH_EQUIP_BUFF_LIST[old_name] then
        -- 别名键与真名共享同一份配置, 按实际存的名字替换即可正确执行 end_fn
        hh_equip:ReplaceEffectByName(old_name, EFFECT_NAME)
    else
        -- 改版前旧 id 已无配置: 手动替换词条并手动执行试炼的 end_fn
        hh_equip:ReplaceEffect(info.slot_index, EFFECT_NAME)
        local test_cfg = HH_EQUIP_BUFF_LIST and HH_EQUIP_BUFF_LIST[EFFECT_TEST_NAME]
        if test_cfg and test_cfg.end_fn then
            test_cfg.end_fn(hh_equip.inst, info.effect.value)
        end
    end
end

local function do_delta_score(weapon, killer, data)
    if not weapon.components then return end
    if not killer.components and not killer.components.health then return end
    if not killer.components and not killer.components.hh_equip then return end

    local cp_counter = weapon.components.counter;
    local cp_custom_data = weapon.components.custom_data;
    local cp_hh_equip = weapon.components.hh_equip

    -- 记忆中杀过的 boss
    local memories = cp_custom_data:Get(MEMORY_KEY) or {}
    local progress = cp_counter:GetCount(PROGRESS_KEY)

    local victim = data.victim
    if victim:IsValid() and not victim:HasTag("player") and
        victim:HasTag("epic") and not killer.components.health:IsDead() then

        local delta_score = NOVEL_SCORE
        local matched_memories = LMOON.filter(memories, is_memory_same_by(victim.prefab))

        -- 更新记忆
        if #matched_memories > 0 then
            -- 已在记忆中就忽略或降低分数，简单难度下增加 1 分，一般难度不加
            delta_score = BORING_SCORE
             -- 一般只有1个或0个匹配，但是为了更加健壮需要全部替换
            for _, matched_memory in ipairs(matched_memories) do
                matched_memory.count = matched_memory.count + 1
            end
        else
            table.insert(memories, { prefab = victim.prefab, count = 1 })
            memories = LMOON.slice(memories, -5, 0) -- 仅保留最新的 5 个，越靠后越新
        end

        cp_counter:DoDelta(PROGRESS_KEY, delta_score)
        cp_custom_data:Set(MEMORY_KEY, memories)

        -- 更新试炼进度，展示在武器详情页的信息
        cp_hh_equip:UpdateEffectValueByName(EFFECT_TEST_NAME,
                                            cp_counter:GetCount(PROGRESS_KEY))

        -- 如果达到分数就升级效果
        if cp_counter:GetCount(PROGRESS_KEY) >= EFFECT_TEST_SCORE then
            upgrade_effect(weapon)
        end
    end
end

local function format_display(score, memory_list)
    local memory_list_str = table.concat(LMOON.map(memory_list, memory_display_str), ", ")

    local title_str = string.format("完成试炼此效果变为【寒月公主】")
    local separator_header_str = string.format("=============寒月试炼=============")
    local separator_footer_str = string.format("================================")
    local progress_str = string.format("试炼进度：%s/%s (记忆外 +%s，记忆中 +%s)", score, EFFECT_TEST_SCORE, NOVEL_SCORE, BORING_SCORE)
    local memories_str = #memory_list > 0
        and string.format("击杀记忆(%s)：%s", EFFECT_TEST_MEMORY_CAP, memory_list_str)
        or nil
    return table.concat(LMOON.filter({title_str, separator_header_str, progress_str, memories_str, separator_footer_str}, truly), "\n")
end

-- ---- 偷取辅助 ----
-- 偷取战利品：按目标掉落表生成一批并直接吐到地上
-- 注意：GenerateLoot 不消耗原掉落表，怪物死亡时照常掉落
local function StealLootFromTarget(target)
    local dropper = target ~= nil and target.components and target.components.lootdropper
    if dropper == nil then return false end
    local loot = dropper:GenerateLoot()
    if loot == nil or #loot == 0 then return false end
    local pt = target:GetPosition()
    for _, item_prefab in ipairs(loot) do
        if item_prefab ~= nil then
            dropper:SpawnLootPrefab(item_prefab, pt)
        end
    end
    return true
end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_HANYUE", {
        name = "寒月公主",
        client_text = "寒月\n公主",
        desc = "攻击冻结目标(永冻)每次攻击扣2%最大生命\n有托托莉则2%噩梦伤害 | 暴击+66% 爆伤+666%\n每次攻击附带666真伤\n偷取：1%概率偷取目标战利品",
        check_desc = "寒月照，万物霜！",
        obtain_desc = "由【寒月试炼】获得",
        obtains = {}, -- 空表表示无法随机掉落、附魔卷轴以及合成出来
        can_add = false,
        only_one = true,
        is_special = true, -- 专属获取：从 HH 掉落池(普通/优质/稀有)中排除，打宝藏怪也不掉
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
                -- 偷取：偷取战利品冷却时间戳
                owner._hanyue_greed_last_steal = 0

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

                -- 攻击触发：666真伤 + 2%最大生命伤害 + 永冻标记 + 偷取
                owner._hanyue_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "hanyue") then return end
                    local target = data and data.target
                    if not target or not target:IsValid() then return end
                    if target:HasTag("player") then return end -- 只对怪物生效
                    local health = target.components.health
                    if not health or health:IsDead() then return end

                    -- 托托莉检测：有托托莉则2%伤害变为噩梦真伤
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

                    -- 每次攻击附带2%最大生命伤害(有托托莉则走噩梦真伤通道)
                    -- 666 已击杀则跳过，避免对尸体重复扣血/重复推送事件
                    if not health:IsDead() then
                        local frost_dmg = (health.maxhealth or 100) * FROST_PERCENT
                        if owner._hanyue_has_totori then
                            local ttl = owner.components.ttl_wanly_damage
                            if ttl then
                                ttl:ApplyTTL_wanly_damage(target, frost_dmg)
                            else
                                health:DoDelta(-frost_dmg, false, "hanyue_frost")
                            end
                        else
                            health:DoDelta(-frost_dmg, false, "hanyue_frost")
                        end
                    end

                    -- 永冻标记(攻击刷新持续时长)
                    owner._hanyue_marks[target] = _G.GetTime() + FROST_DURATION
                    freezeTarget(target)

                    -- 偷取：1% 概率偷取目标战利品（冷却 1 秒）
                    local steal_now = _G.GetTime()
                    if steal_now - owner._hanyue_greed_last_steal >= GREED_STEAL_COOLDOWN
                        and math.random() < GREED_STEAL_CHANCE then
                        owner._hanyue_greed_last_steal = steal_now
                        StealLootFromTarget(target)
                    end
                end
                owner:ListenForEvent("onattackother", owner._hanyue_attack_handler)

                -- 每秒一跳：仅维持永冻（2%最大生命伤害已改为每次攻击附带）
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

                owner._hanyue_greed_last_steal = nil

                owner._hanyue_marks = nil
                owner._hanyue_has_totori = nil
                owner._hanyue_inited = nil
            end
        end,
    })

    GLOBAL.AddSpecialEquipEffect(EFFECT_TEST_NAME, {
        name = "寒月试炼",
        client_text = "寒月\n试炼",
        desc = string.format("完成试炼此效果变为【寒月公主】\n试炼: 使用该武器击杀 BOSS 达到 %s 分", EFFECT_TEST_SCORE),
        recipes = {"moon_effect_stone_hanyue_test"},
        desc_dync = function(equip, effect_value)
            -- 计数直接读 counter 组件，不依赖 UpdateEffectValueByName 回写的 value
            -- (词条实例名与效果 id 不一致时回写会失效，导致计数永远停在 0)
            local score = effect_value or 0
            if equip.components and equip.components.counter then
                local live_count = equip.components.counter:GetCount(PROGRESS_KEY)
                if live_count and live_count > (tonumber(score) or 0) then
                    score = live_count
                end
            end
            local cp_custom_data = equip.components and equip.components.custom_data
            local memory_list = cp_custom_data and cp_custom_data:Get(MEMORY_KEY) or {}
            return format_display(score, memory_list)
        end,
        check_desc = "武器栏",
        obtain_desc = "合成",
        obtains = {}, -- 空表表示无法随机掉落、附魔卷轴以及合成出来
        can_add = false,
        only_one = true,
        is_special = true, -- 专属获取：从 HH 掉落池(普通/优质/稀有)中排除，打宝藏怪也不掉
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
            -- 诊断: 打印该武器实际存的词条名(排查旧存档别名/旧 id 脏数据)
            if inst.components and inst.components.hh_equip then
                for i, v in ipairs(inst.components.hh_equip.equip_buff_list) do
                    print("[寒月试炼] 词条", i, tostring(v.name),
                          tostring(v.value))
                end
            end
            -- 补判: 阈值调小或判定漏跑后, 装备时计数已达标则立即升级
            -- (升级成功就不再登记击杀监听, 避免升级后继续累计)
            if inst.components and inst.components.counter
                and inst.components.counter:GetCount(PROGRESS_KEY)
                    >= EFFECT_TEST_SCORE then
                upgrade_effect(inst)
                return
            end
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
