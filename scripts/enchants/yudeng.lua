-- 小月亮 附魔：余灯照夜明
-- 附近 50 码内有其他玩家时生效：
--   1) 每 5 秒使自身与范围内玩家回复 5-10 点生命与精神
--   2) 范围内每有一名玩家，攻击与防御 +10%（上限 6 人 = 60%）
--   3) 每 5-10 秒为自身与范围内玩家驱散一个负面效果
-- 套装：同时拥有「孑身处处静」时，周围没有玩家也视作 6 名玩家生效
-- 空庭水月定，连山接无垠。孑身处处静，余灯照夜明。

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

-- ---------------------------------------------------------------
-- 参数
-- ---------------------------------------------------------------
local PARTY_RANGE_SQ    = 2500  -- 50 码（判定用平方距离）
local REFRESH_INTERVAL  = 2     -- 生效判定/人数刷新间隔(秒)
local REGEN_INTERVAL    = 5     -- 回复间隔(秒)
local REGEN_MIN         = 5     -- 单次回血/回神下限
local REGEN_MAX         = 10    -- 单次回血/回神上限
local BUFF_PER_PLAYER   = 10    -- 每名玩家 +10% 攻击与防御
local MAX_PLAYERS       = 6     -- 人数上限（= +60%）
local DISPEL_MIN        = 5     -- 驱散间隔下限(秒)
local DISPEL_MAX        = 10    -- 驱散间隔上限(秒)

local EFFECT_ID = "Legend_YUDENG"

-- HH 框架里属于"负面"的 buff（对照 enums/hh_buff.lua 的 id 清单筛出来的）：
-- 中毒/毒雾/减速/炮塔毒与火/怪物增伤/易冷易热/护甲消耗/制裁回血
-- 不含 add_health / add_hunger / add_sanity / suit_* / test_* 这些增益或标记类
local HH_DEBUFFS = {
    "poison",
    "monster_poison",
    "reduce_speed",
    "turret_poison",
    "turret_fire",
    "monster_add_target_damage",
    "add_cold",
    "add_hot",
    "add_armor_consume",
    "player_healthSuppressNum",
}

-- 收集目标身上所有可驱散的负面效果（每次只驱散其中一个）
local function collectDebuffs(target)
    local list = {}

    local hb = target.components.hh_buff
    if hb and hb.HasBuff then
        for _, id in ipairs(HH_DEBUFFS) do
            if hb:HasBuff(id) then
                list[#list + 1] = { kind = "hh", id = id }
            end
        end
    end

    -- 原版状态：着火 / 冰冻 / 潮湿
    if target.components.burnable and target.components.burnable:IsBurning() then
        list[#list + 1] = { kind = "burn" }
    end
    if target.components.freezable and target.components.freezable:IsFrozen() then
        list[#list + 1] = { kind = "freeze" }
    end
    if target.components.moisture and target.components.moisture:GetMoisturePercent() >= 0.2 then
        list[#list + 1] = { kind = "moisture" }
    end

    -- 原版减速：统一挂在 locomotor 的外部速度倍率上（倍率 <1 即减速）
    -- 注意原版字段名是 _externalspeedmultipliers，且结构是嵌套的：
    --   _externalspeedmultipliers[source] = { multipliers = { [key] = m }, onremove = fn }
    -- source 可能是实体（如沙尘暴用 inst 作 source）也可能是字符串，移除时原样传回。
    local loco = target.components.locomotor
    if loco and loco._externalspeedmultipliers then
        for source, src_params in pairs(loco._externalspeedmultipliers) do
            local mults = src_params and src_params.multipliers
            if mults then
                for k, m in pairs(mults) do
                    if type(k) == "string" and type(m) == "number" and m < 1 then
                        list[#list + 1] = { kind = "slow", source = source, key = k }
                        break -- 同一来源最多取一个 key，剩下的留给下一轮
                    end
                end
            end
        end
    end

    return list
end

-- 执行单条驱散
local function applyDispel(target, entry)
    if entry.kind == "hh" then
        local hb = target.components.hh_buff
        if hb and hb.RemoveBuff then
            hb:RemoveBuff(entry.id)
        end
    elseif entry.kind == "burn" then
        local b = target.components.burnable
        if b and b:IsBurning() then
            b:Extinguish()
        end
    elseif entry.kind == "freeze" then
        local f = target.components.freezable
        if f and f:IsFrozen() then
            f:Unfreeze()
        end
    elseif entry.kind == "moisture" then
        if target.components.moisture then
            target.components.moisture:SetMoistureLevel(0)
        end
    elseif entry.kind == "slow" then
        local loco = target.components.locomotor
        if loco then
            loco:RemoveExternalSpeedMultiplier(entry.source, entry.key)
        end
    end
end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect(EFFECT_ID, {
        name = "余灯照夜明",
        client_text = "余灯\n夜明",
        desc = "周围50码内有其他玩家时:\n每5秒使自身与范围内玩家回复5-10生命与精神\n范围内每名玩家使攻击与防御+10％(上限6人)\n每5-10秒为自身与范围内玩家驱散一个负面效果\n与「孑身处处静」齐穿时,周围没有玩家也视作6人",
        check_desc = "孑身处处静，余灯照夜明。",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "yudeng", EFFECT_ID, 1)
            if not owner._yudeng_hooked then
                owner._yudeng_hooked = true
                owner._yudeng_active = false
                owner._yudeng_targets = { owner }
                owner._yudeng_buff_value = 0

                -- ==========================================
                -- 攻防加成：按人数增减，永远与当前人数对齐
                -- 用 buff_value 记录"已经加了多少"，切换时只补差值，
                -- 避免每轮先 Reduce 再 Add 造成的数值抖动/漏减。
                -- 注意 absorbDamage 在 HH 里有 80% 硬上限（6 人 60% 不触顶，
                -- 但与其他附魔叠加时会被截断，这是框架行为，不做额外处理）。
                -- ==========================================
                owner._yudeng_syncBuffs = function(count)
                    local hh = owner.components.hh_player
                    if not hh then return end
                    local target = count * BUFF_PER_PLAYER
                    local cur = owner._yudeng_buff_value or 0
                    if target == cur then return end
                    if target > cur then
                        hh:AddEffectValueByKey("addComDamagePercent", target - cur)
                        hh:AddEffectValueByKey("absorbDamage", target - cur)
                    else
                        hh:ReduceEffectValueByKey("addComDamagePercent", cur - target)
                        hh:ReduceEffectValueByKey("absorbDamage", cur - target)
                    end
                    owner._yudeng_buff_value = target
                end

                -- ==========================================
                -- 生效判定：周围 50 码内的玩家数量
                -- 套装齐穿（同时有「孑身处处静」）时人数下限锁 6 —— 不管身边
                -- 有没有人，都按满编 6 人吃满加成，"视作有 6 名玩家生效"。
                -- ==========================================
                owner._yudeng_refresh = function()
                    if not _G.Moon_HasEffect(owner, "yudeng") then return end

                    local x, y, z = owner.Transform:GetWorldPosition()
                    local targets = { owner }
                    local count = 0
                    for _, v in ipairs(_G.AllPlayers) do
                        if v ~= owner and v:IsValid()
                            and v:GetDistanceSqToPoint(x, y, z) < PARTY_RANGE_SQ
                        then
                            count = count + 1
                            targets[#targets + 1] = v
                        end
                    end

                    if _G.Moon_HasEffect(owner, "jieshen") then
                        count = math.max(count, MAX_PLAYERS)
                    end
                    count = math.min(count, MAX_PLAYERS)

                    owner._yudeng_targets = targets
                    owner._yudeng_count = count
                    owner._yudeng_active = count > 0

                    owner._yudeng_syncBuffs(count)
                end

                -- 每 5 秒的群体回复（自身 + 范围内玩家）
                owner._yudeng_regen = function()
                    if not owner._yudeng_active then return end
                    for _, v in ipairs(owner._yudeng_targets or {}) do
                        if v and v:IsValid() then
                            local health = v.components.health
                            if health and not health:IsDead() then
                                health:DoDelta(math.random(REGEN_MIN, REGEN_MAX), true, "yudeng_regen")
                            end
                            local sanity = v.components.sanity
                            if sanity then
                                sanity:DoDelta(math.random(REGEN_MIN, REGEN_MAX))
                            end
                        end
                    end
                end

                -- 驱散：每个目标每轮随机驱散一个负面效果
                owner._yudeng_dispelOnce = function()
                    if not owner._yudeng_active then return end
                    for _, v in ipairs(owner._yudeng_targets or {}) do
                        if v and v:IsValid() then
                            local list = collectDebuffs(v)
                            if #list > 0 then
                                applyDispel(v, list[math.random(#list)])
                            end
                        end
                    end
                end

                -- 驱散节奏是 5-10 秒随机，用递归 DoTaskInTime 而不是
                -- DoPeriodicTask（后者只能固定间隔）
                owner._yudeng_dispelLoop = function()
                    if not _G.Moon_HasEffect(owner, "yudeng") then return end
                    owner._yudeng_dispelOnce()
                    owner._yudeng_dispel_task = owner:DoTaskInTime(
                        math.random(DISPEL_MIN, DISPEL_MAX), owner._yudeng_dispelLoop)
                end

                -- 初始判定 + 周期任务
                owner._yudeng_refresh()
                owner._yudeng_refresh_task = owner:DoPeriodicTask(REFRESH_INTERVAL, owner._yudeng_refresh)
                owner._yudeng_regen_task = owner:DoPeriodicTask(REGEN_INTERVAL, owner._yudeng_regen)
                owner._yudeng_dispelLoop()

                -- 玩家进出世界时立刻重算
                -- 注意事件源必须显式写 TheWorld：ms_playerjoined/ms_playerleft
                -- 都是由世界推的，不传第三个参数监听不会触发
                owner._yudeng_join_handler = function() owner._yudeng_refresh() end
                owner:ListenForEvent("ms_playerjoined", owner._yudeng_join_handler, _G.TheWorld)
                owner:ListenForEvent("ms_playerleft", owner._yudeng_join_handler, _G.TheWorld)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "yudeng", EFFECT_ID, 1)
            if not _G.Moon_HasEffect(owner, "yudeng") then
                if owner._yudeng_refresh_task then
                    owner._yudeng_refresh_task:Cancel()
                    owner._yudeng_refresh_task = nil
                end
                if owner._yudeng_regen_task then
                    owner._yudeng_regen_task:Cancel()
                    owner._yudeng_regen_task = nil
                end
                if owner._yudeng_dispel_task then
                    owner._yudeng_dispel_task:Cancel()
                    owner._yudeng_dispel_task = nil
                end
                if owner._yudeng_join_handler then
                    owner:RemoveEventCallback("ms_playerjoined", owner._yudeng_join_handler, _G.TheWorld)
                    owner:RemoveEventCallback("ms_playerleft", owner._yudeng_join_handler, _G.TheWorld)
                    owner._yudeng_join_handler = nil
                end

                -- 把已经加上的攻防数值原数撤回，不能漏
                owner._yudeng_syncBuffs(0)

                owner._yudeng_targets = nil
                owner._yudeng_active = nil
                owner._yudeng_count = nil
                owner._yudeng_buff_value = nil
                owner._yudeng_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop(EFFECT_ID, 0.01)
end)
