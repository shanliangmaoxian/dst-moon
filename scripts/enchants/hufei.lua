-- 小月亮 附魔：蝴蝶的小阿飞
-- 5只光翼蝴蝶护体：受击消耗1只减免60%伤害
-- 每6秒恢复1只；击杀回复25生命+15精神并恢复2只
-- 每只蝴蝶+4%伤害(满5只+20%)，移速+20%
-- 套装「双飞伴生蝶」：与小蝴蝶齐穿，濒死时立即回满血，共两次
--   第 1 次「蝶的献祭」、第 2 次「飞的守护」
--   两次尽数用尽(双飞伴生蝶都死亡)后触发「蝶之泯灭的哀伤」，套装效果失效 90 秒

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

-- 套装「双飞伴生蝶」参数
local SUIT_CHARGES = 2            -- 濒死回满血的次数（两次献祭）
local SUIT_LOST_DURATION = 90     -- 两次用尽后套装失效时长(秒)
-- 按消耗顺序命名：第 1 次 / 第 2 次
local SUIT_SAVE_NAMES = { "蝶的献祭", "飞的守护" }
local SUIT_LOST_NAME = "蝶之泯灭的哀伤"

-- 套装判定：小蝴蝶 + 小阿飞 同时装备，且不处于「蝶之泯灭的哀伤」失效期
local function isSuitActive(owner)
    return _G.Moon_HasEffect(owner, "hufei")
        and _G.Moon_HasEffect(owner, "xiaohudie")
        and not owner._shuangfei_lost
end

-- 同步护体蝴蝶的可见实体（数量与 _hufei_butterflies 一致，紫色光翼环绕）
local function sync_butterfly_visuals(owner)
    if not owner._hufei_visual_butterflies then
        owner._hufei_visual_butterflies = {}
    end
    local count = owner._hufei_butterflies or 0
    local list = owner._hufei_visual_butterflies
    while #list < count do
        local bf = _G.SpawnPrefab("butterfly")
        if not bf then break end
        bf:AddTag("NOCLICK")     -- 玩家点不到
        bf:AddTag("notarget")    -- 不被怪物选为目标
        if bf.components.health then
            bf.components.health:SetInvincible(true)
        end
        bf:SetBrain(nil)         -- 停止自主飞行，位置由环绕任务控制
        if bf.AnimState then
            bf.AnimState:SetMultColour(0.8, 0.3, 1, 0.9) -- 紫色光翼
        end
        table.insert(list, bf)
    end
    while #list > count do
        local bf = table.remove(list)
        if bf and bf:IsValid() then bf:Remove() end
    end
end

-- 更新蝴蝶增伤（每只蝴蝶 +4% 伤害）
local function update_damage_bonus(owner)
    local hh = owner.components.hh_player
    if not hh then return end
    local n = owner._hufei_butterflies or 0
    local target = n * 4
    local cur = owner._hufei_damage_bonus or 0
    if target > cur then
        hh:AddEffectValueByKey("addComDamagePercent", target - cur)
    elseif target < cur then
        hh:ReduceEffectValueByKey("addComDamagePercent", cur - target)
    end
    owner._hufei_damage_bonus = target
    sync_butterfly_visuals(owner)
end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_HUFEI", {
        name = "蝴蝶的小阿飞",
        client_text = "蝶\n飞",
        desc = "5只光翼蝴蝶护体,受击耗1只减免60%\n每6秒回1只;击杀回25血+15精神+2只\n每只蝴蝶+4%伤害,移速+20%\n套装「双飞伴生蝶」:与小蝴蝶齐穿\n濒死立即回满血2次(蝶的献祭/飞的守护)\n两次用尽触发蝶之泯灭的哀伤,套装失效90秒",
        check_desc = "蝶翼护体，攻守兼备！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "hufei", "Legend_HUFEI", 1)
            if not owner._hufei_hooked then
                owner._hufei_hooked = true
                owner._hufei_butterflies = 5      -- 初始5只

                -- ==============================================
                -- 套装「双飞伴生蝶」：与小蝴蝶齐穿，濒死立即回满血（共两次）
                -- 原理：health 组件在生命触底(≤0)瞬间先推 "minhealth" 事件、
                -- 之后才在同一函数内推 "death"；在 minhealth 回调里把血拉满，
                -- SetVal 后续的死亡判定读到的 currenthealth 已 > 0，死亡被跳过。
                -- 两次献祭（第1次「蝶的献祭」→ 第2次「飞的守护」）尽数用尽，
                -- 即双飞伴生蝶都死亡，触发「蝶之泯灭的哀伤」，套装效果失效一段时间。
                -- ==============================================
                -- 充能只在本次会话首次装备时初始化：同一次游戏内脱下再穿不刷新次数，
                -- 避免靠反复穿脱白嫖献祭。不做存档持久化——重载后从头开始，
                -- 这样既宽松又不会出现"哀伤计时丢失导致永久失效"的死锁。
                if owner._shuangfei_charges == nil then
                    owner._shuangfei_charges = SUIT_CHARGES
                end

                owner._shuangfei_death_handler = function()
                    owner._shuangfei_dead = true  -- 真死过就不再触发（防尸体重复触发）
                end
                owner:ListenForEvent("death", owner._shuangfei_death_handler)

                -- 复活回来必须清掉"真死过"标记，否则复活后套装永久哑火
                owner._shuangfei_respawn_handler = function()
                    owner._shuangfei_dead = nil
                end
                owner:ListenForEvent("respawnfromghost", owner._shuangfei_respawn_handler)

                owner._shuangfei_minhealth_handler = function(inst, data)
                    if owner._shuangfei_dead then return end
                    if not isSuitActive(owner) then return end
                    local charges = owner._shuangfei_charges or 0
                    if charges <= 0 then return end

                    -- 立即回满血，无概率判定
                    local health = owner.components.health
                    if health then
                        health:DoDelta(health.maxhealth, true, "shuangfei_save")
                    end

                    owner._shuangfei_charges = charges - 1
                    -- SUIT_SAVE_NAMES 按消耗顺序排列：第1次蝶的献祭、第2次飞的守护
                    local save_name = SUIT_SAVE_NAMES[SUIT_CHARGES - charges + 1]

                    if owner.components.talker then
                        owner.components.talker:Say("双飞伴生蝶！" .. (save_name or "") .. "！")
                    end

                    if owner._shuangfei_charges > 0 then return end

                    -- 两次献祭尽数用尽：双飞伴生蝶都死亡 → 蝶之泯灭的哀伤
                    owner._shuangfei_lost = true
                    owner:DoTaskInTime(1.5, function()
                        if owner:IsValid() and owner.components.talker then
                            owner.components.talker:Say(SUIT_LOST_NAME .. "…双飞伴生蝶已尽数凋零")
                        end
                    end)

                    if owner._shuangfei_recover_task then
                        owner._shuangfei_recover_task:Cancel()
                    end
                    owner._shuangfei_recover_task = owner:DoTaskInTime(SUIT_LOST_DURATION, function()
                        owner._shuangfei_recover_task = nil
                        if not owner:IsValid() then return end
                        owner._shuangfei_lost = nil
                        owner._shuangfei_charges = SUIT_CHARGES
                        if isSuitActive(owner) and owner.components.talker then
                            owner.components.talker:Say("哀伤散尽，双飞伴生蝶再度振翅")
                        end
                    end)
                end
                owner:ListenForEvent("minhealth", owner._shuangfei_minhealth_handler)

                -- 永久移速+20%
                local hh = owner.components.hh_player
                if hh then
                    hh:AddEffectValueByKey("addSpeedPercent", 20)
                end
                update_damage_bonus(owner)

                -- 勾住 health:DoDelta 拦截伤害（蝴蝶抗伤：消耗1只，减免60%）
                local health = owner.components.health
                if health and not health._hufei_hooked_dodelta then
                    local oldDoDelta = health.DoDelta
                    health._hufei_old_dodelta = oldDoDelta
                    health.DoDelta = function(self, delta, overtime, cause, ...)
                        -- 拦截伤害(负值)：消耗1只蝴蝶，减免60%（仅战斗打击，持续伤害不消耗）
                        if delta < 0 and not overtime and _G.Moon_HasEffect(owner, "hufei") then
                            local butterflies = owner._hufei_butterflies or 0
                            if butterflies > 0 then
                                owner._hufei_butterflies = butterflies - 1
                                update_damage_bonus(owner)
                                -- 剩余40%伤害照常结算
                                delta = delta * 0.4
                            end
                        end
                        return oldDoDelta(self, delta, overtime, cause, ...)
                    end
                end

                -- 蝴蝶自动恢复：每6秒恢复1只
                owner._hufei_regen_task = owner:DoPeriodicTask(6, function()
                    if not _G.Moon_HasEffect(owner, "hufei") then return end
                    local current = owner._hufei_butterflies or 0
                    if current < 5 then
                        owner._hufei_butterflies = current + 1
                        update_damage_bonus(owner)
                    end
                end)

                -- 击杀回复
                owner._hufei_kill_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "hufei") then return end
                    if owner.components.health then
                        owner.components.health:DoDelta(25, false, nil)
                    end
                    if owner.components.sanity then
                        owner.components.sanity:DoDelta(15)
                    end
                    -- 击杀恢复2只蝴蝶（上限5只）
                    local current = owner._hufei_butterflies or 0
                    if current < 5 then
                        owner._hufei_butterflies = math.min(5, current + 2)
                        update_damage_bonus(owner)
                    end
                end
                owner:ListenForEvent("killed", owner._hufei_kill_handler)

                -- 蝴蝶环绕动画（可见的紫色光翼蝴蝶绕身飞行）
                owner._hufei_visual_task = owner:DoPeriodicTask(0.1, function()
                    if not _G.Moon_HasEffect(owner, "hufei") then return end
                    if not owner:IsValid() then return end
                    local list = owner._hufei_visual_butterflies or {}
                    local n = #list
                    if n == 0 then return end
                    local x, y, z = owner.Transform:GetWorldPosition()
                    local t = _G.GetTime and _G.GetTime() or 0
                    for i, bf in ipairs(list) do
                        if bf and bf:IsValid() then
                            local angle = t * 1.5 + (i - 1) / n * 2 * math.pi
                            local by = y + 1.2 + math.sin(t * 0.6 + i * 1.7) * 0.25
                            bf.Transform:SetPosition(x + math.cos(angle) * 2.2, by, z + math.sin(angle) * 2.2)
                        end
                    end
                end)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "hufei", "Legend_HUFEI", 1)
            if not _G.Moon_HasEffect(owner, "hufei") then
                -- 还原移速与蝴蝶增伤
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("addSpeedPercent", 20)
                    hh:ReduceEffectValueByKey("addComDamagePercent", owner._hufei_damage_bonus or 0)
                end
                owner._hufei_damage_bonus = nil
                -- 还原 DoDelta
                local health = owner.components.health
                if health and health._hufei_old_dodelta then
                    health.DoDelta = health._hufei_old_dodelta
                    health._hufei_old_dodelta = nil
                end
                -- 停止恢复任务
                if owner._hufei_regen_task then
                    owner._hufei_regen_task:Cancel()
                    owner._hufei_regen_task = nil
                end
                -- 移除击杀回调
                if owner._hufei_kill_handler then
                    owner:RemoveEventCallback("killed", owner._hufei_kill_handler)
                    owner._hufei_kill_handler = nil
                end
                -- 移除可见蝴蝶
                if owner._hufei_visual_task then
                    owner._hufei_visual_task:Cancel()
                    owner._hufei_visual_task = nil
                end
                for _, bf in ipairs(owner._hufei_visual_butterflies or {}) do
                    if bf and bf:IsValid() then
                        bf:Remove()
                    end
                end
                owner._hufei_visual_butterflies = nil
                -- 清除蝴蝶计数
                owner._hufei_butterflies = nil
                -- 清除套装「双飞伴生蝶」状态
                if owner._shuangfei_minhealth_handler then
                    owner:RemoveEventCallback("minhealth", owner._shuangfei_minhealth_handler)
                    owner._shuangfei_minhealth_handler = nil
                end
                if owner._shuangfei_death_handler then
                    owner:RemoveEventCallback("death", owner._shuangfei_death_handler)
                    owner._shuangfei_death_handler = nil
                end
                if owner._shuangfei_respawn_handler then
                    owner:RemoveEventCallback("respawnfromghost", owner._shuangfei_respawn_handler)
                    owner._shuangfei_respawn_handler = nil
                end
                owner._shuangfei_dead = nil
                -- 注意：_shuangfei_charges / _shuangfei_lost / _shuangfei_recover_task
                -- 故意不在这里清理——清了的话脱下再穿上就能把两次献祭刷满；
                -- 哀伤的恢复计时是时间制，与当前是否穿着套装无关，让它自然走完
                owner._hufei_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_HUFEI", 0.01)
end)
