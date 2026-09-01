-- 小月亮 怪物强化组件
-- 挂在每个被强化的怪物身上，管理防御层、附魔效果和清理
-- PoC: 仅作用于 树精守卫 (leif/leif_sparse)
-- 注意: 组件通过 require 加载，GLOBAL 不可用，全局函数直接使用

local MoonMobEnhance = Class(function(self, inst)
    self.inst = inst
    self.tier = "normal"            -- "normal" | "boss"
    self.enchants = {}              -- { [enchant_id] = { state = {...} } }
    self.difficulty_mult = 1.0      -- 难度倍率
    self.extra_enchant_count = 0    -- 额外附魔数量

    -- 防御层状态
    self.defense_enabled = false    -- 防御层是否启用（配置驱动）
    self._defense_hooked = false
    self._damage_hooked = false
    self._origin_DoDelta = nil
    self._hook_fn = nil             -- 当前安装的 DoDelta hook（用于还原判断）
end)

---------------------------------------------------------------------
-- 初始化：由 init.lua 在 AddPrefabPostInit 中调用
---------------------------------------------------------------------
function MoonMobEnhance:OnStart(tier, diff_mult, enchant_ids, enchants_config, hh_enabled, defense_cfg, letmeseemod)
    self.tier = tier or "normal"
    self.difficulty_mult = diff_mult or 1.0
    self.hh_enabled = hh_enabled or false
    self.defense_cfg = defense_cfg or {}
    self.letmeseemod = letmeseemod or false

    -- 1. 应用防御层（检测到让我瞧瞧则跳过，避免冲突）
    if not self.letmeseemod then
        self:_ApplyDefense()
    end

    -- 2. 应用抽到的附魔
    if enchant_ids and enchants_config then
        for _, eid in ipairs(enchant_ids) do
            local cfg = enchants_config[eid]
            if cfg then
                self:_ApplyEnchant(eid, cfg)
            end
        end
    end

    -- 3. 视觉效果
    self:_ApplyVisuals()

    -- 4. 死亡清理
    self.inst:ListenForEvent("death", function()
        self:OnDeath()
    end)
    self.inst:ListenForEvent("onremove", function()
        self:OnDeath()
    end)
end

---------------------------------------------------------------------
-- 是否处于收纳状态（被打包 / 放入容器 / 捕捉进物品栏）
-- 收纳期间怪物不参与战斗，其附魔效果（尤其光环类范围伤害）必须暂停，
-- 否则蜘蛛等小怪被装进箱子后仍会通过 on_update 周期任务持续伤害附近玩家。
-- 判断依据：实体被作为物品持有（inventoryitem.owner / IsHeld）。
-- 实体被销毁的收纳方式（原实体 RemoveEntity 换 item）天然安全：
-- 周期任务会因 inst:IsValid() 失败而退出，无需处理。
---------------------------------------------------------------------
function MoonMobEnhance:IsStored()
    local inst = self.inst
    if not inst:IsValid() then return true end
    local inv = inst.components.inventoryitem
    if inv and (inv.owner or (inv.IsHeld and inv:IsHeld())) then
        return true
    end
    return false
end

---------------------------------------------------------------------
-- 防御层 + 附魔伤害回调（统一走 DoDelta hook）
-- 防御层从 self.defense_cfg 读取配置：mitigation/dynamic/cap/freq/scope
-- 附魔的 cfg.on_damage 回调可在伤害落地前修改（如格挡归零）
---------------------------------------------------------------------
function MoonMobEnhance:_ApplyDefense()
    if self._defense_hooked then return end
    local d = self.defense_cfg
    local enabled = d and (d.mitigation or d.dynamic or d.cap or d.freq)
    self.defense_enabled = enabled or false
    if enabled then
        self:_EnsureDamageHook()
    end
end

-- 确保 health.DoDelta 被 hook（防御层开启 或 存在需要 on_damage 的附魔时）
function MoonMobEnhance:_EnsureDamageHook()
    if self._damage_hooked then return end
    local health = self.inst.components.health
    if not health then return end

    -- 原函数捕获为闭包 upvalue：不依赖组件字段。OnDeath 会清空组件状态，
    -- 但其他 mod（如更多附魔石）保存的 wrapper 引用在死后仍可能被调用，
    -- 此时透传必须依旧可用，否则会 nil 崩溃（修复 _origin_DoDelta 为 nil 的 bug）
    local orig_DoDelta = health.DoDelta
    if not orig_DoDelta then return end
    self._origin_DoDelta = orig_DoDelta

    local hook_fn = function(hself, delta, overtime, cause, ignore_invincible, afflicter, ignore_absorb, ...)
        if not hself.inst or not hself.inst:IsValid() then
            return orig_DoDelta(hself, delta, overtime, cause, ignore_invincible, afflicter, ignore_absorb, ...)
        end
        if hself:IsDead() then
            return orig_DoDelta(hself, delta, overtime, cause, ignore_invincible, afflicter, ignore_absorb, ...)
        end
        local comp = hself.inst.components.moon_mob_enhance
        if not comp then
            return orig_DoDelta(hself, delta, overtime, cause, ignore_invincible, afflicter, ignore_absorb, ...)
        end

        -- 治疗/正 delta 不处理
        if not delta or delta >= 0 then
            return orig_DoDelta(hself, delta, overtime, cause, ignore_invincible, afflicter, ignore_absorb, ...)
        end

        local damage = -delta

        -- 1. 防御层
        if comp.defense_enabled and comp.defense_cfg then
            damage = comp:_ApplyDefenseDamage(damage, hself, afflicter)
        end

        -- 2. 附魔 on_damage 回调（按获得顺序）
        for _, eid in ipairs(comp._enchant_order or {}) do
            local data = comp.enchants[eid]
            if data and data.cfg and data.cfg.on_damage then
                local res = data.cfg.on_damage(comp.inst, damage, afflicter, comp.tier, comp.difficulty_mult, data.state)
                if type(res) == "number" then
                    damage = res
                end
            end
        end

        if damage <= 0 then
            return orig_DoDelta(hself, 0, overtime, cause, ignore_invincible, afflicter, ignore_absorb, ...)
        end
        return orig_DoDelta(hself, -damage, overtime, cause, ignore_invincible, afflicter, ignore_absorb, ...)
    end

    self._hook_fn = hook_fn
    health.DoDelta = hook_fn
    self._damage_hooked = true
    self._defense_hooked = true
end

-- 防御层伤害计算（hook 内调用），返回处理后的 damage
function MoonMobEnhance:_ApplyDefenseDamage(damage, health, afflicter)
    local d = self.defense_cfg
    local is_boss = self.tier == "boss"
    local mult = self.difficulty_mult

    -- 防御范围：仅Boss时跳过普通怪
    if d.scope == "boss" and not is_boss then
        return damage
    end

    -- 1. 基础减伤
    if d.mitigation and d.mitigation > 0 then
        damage = damage * (1 - d.mitigation * mult)
    end

    -- 2. 动态减伤
    if d.dynamic then
        local hp_pct = health:GetPercent()
        local reduction = 0
        if d.dynamic == 1 then  -- 线性
            local base = is_boss and 0.3 or 0.1
            reduction = base + (1 - hp_pct) * 0.6
        elseif d.dynamic == 3 then  -- 阶梯式
            if hp_pct > 0.75 then
                reduction = 0.3
            elseif hp_pct > 0.5 then
                reduction = 0.5
            elseif hp_pct > 0.25 then
                reduction = 0.7
            else
                reduction = 0.9
            end
        end
        damage = damage * (1 - reduction)
    end

    -- 3. 单次限伤
    local max_hp = health.maxhealth or 1
    if d.cap then
        local cap_val = max_hp * (d.cap / 100) * mult
        if damage > cap_val then
            damage = cap_val
        end
    end

    -- 4. 频率限制
    if d.freq and afflicter and afflicter.GUID then
        local now = GetTime()
        local src_key = "mob_defense_freq_" .. afflicter.GUID
        local last_time = self[src_key] or 0
        if now - last_time < d.freq then
            return 0
        end
        self[src_key] = now
    end

    return damage
end

---------------------------------------------------------------------
-- 应用单个附魔
---------------------------------------------------------------------
function MoonMobEnhance:_ApplyEnchant(eid, cfg)
    if self.enchants[eid] then return end  -- 防重复

    self._enchant_order = self._enchant_order or {}
    table.insert(self._enchant_order, eid)
    self.enchants[eid] = { state = {}, cfg = cfg }
    local state = self.enchants[eid].state

    -- 调用附魔的 on_apply（附魔的初始化逻辑）
    if cfg.on_apply then
        cfg.on_apply(self.inst, self.tier, self.difficulty_mult, state)
    end

    -- 注册攻击事件（data 透传给词缀，供吸血等按实际伤害计算）
    if cfg.on_attack then
        local fn = function(attacker, data)
            if not self.inst:IsValid() then return end
            if not self.enchants[eid] then return end
            if self:IsStored() then return end  -- 收纳中不生效
            cfg.on_attack(self.inst, data and data.target, self.tier, self.difficulty_mult, state, data)
        end
        state._attack_handler = fn
        self.inst:ListenForEvent("onhitother", fn)
    end

    -- 注册伤害拦截回调（在 health.DoDelta 落地前修改伤害，如格挡）
    if cfg.on_damage then
        self:_EnsureDamageHook()
    end

    -- 注册受击事件
    if cfg.on_attacked then
        local fn = function(victim, data)
            if not self.inst:IsValid() then return end
            if not self.enchants[eid] then return end
            if self:IsStored() then return end  -- 收纳中不生效
            local attacker = data and data.attacker
            local damage = data and data.damage or 0
            cfg.on_attacked(self.inst, attacker, damage, self.tier, self.difficulty_mult, state)
        end
        state._attacked_handler = fn
        self.inst:ListenForEvent("attacked", fn)
    end

    -- 注册击杀事件
    if cfg.on_kill then
        local fn = function(attacker, data)
            if not self.inst:IsValid() then return end
            if not self.enchants[eid] then return end
            if self:IsStored() then return end  -- 收纳中不生效
            cfg.on_kill(self.inst, data and data.victim, self.tier, self.difficulty_mult, state)
        end
        state._kill_handler = fn
        self.inst:ListenForEvent("onkillother", fn)
    end

    -- 周期更新
    if cfg.on_update then
        local period = cfg.update_period or 3
        state._update_task = self.inst:DoPeriodicTask(period, function()
            if not self.inst:IsValid() then
                if state._update_task then
                    state._update_task:Cancel()
                end
                return
            end
            if not self.enchants[eid] then
                if state._update_task then
                    state._update_task:Cancel()
                end
                return
            end
            if self:IsStored() then return end  -- 收纳中暂停附魔效果（尤其光环类范围伤害）
            cfg.on_update(self.inst, self.tier, self.difficulty_mult, state)
        end)
    end
end

---------------------------------------------------------------------
-- 视觉效果
---------------------------------------------------------------------
function MoonMobEnhance:_ApplyVisuals()
    local inst = self.inst

    -- 构建附魔描述行: "名字：详情"（按获得顺序）
    local function BuildDescLines(enchants, order)
        local lines = {}
        for _, eid in ipairs(order or {}) do
            local data = enchants[eid]
            if data and data.cfg and data.cfg.name then
                local line = data.cfg.name
                if data.cfg.desc then
                    line = line .. "：" .. data.cfg.desc
                end
                table.insert(lines, line)
            end
        end
        return lines
    end

    if self.hh_enabled then
        -- HH 面板激活时：通过 GetHHSpDesc01 扩展点注入
        inst.GetHHSpDesc01 = function(ent, player)
            local comp = ent.components.moon_mob_enhance
            if not comp then return nil end
            local lines = BuildDescLines(comp.enchants, comp._enchant_order)
            if #lines == 0 then return nil end
            local title = "月化"
            local color = comp.tier == "boss" and {255, 200, 100, 255} or {180, 120, 255, 255}
            return {
                desc = table.concat(lines, "\n"),
                title = title,
                color = color,
            }
        end
    else
        -- HH 未启用：覆盖检查文本
        if inst.components.inspectable then
            local old_desc = inst.components.inspectable.getdescriptionfn
            local tier_label = "月化"
            inst.components.inspectable.getdescriptionfn = function(inst, viewer)
                local base = (old_desc and old_desc(inst, viewer)) or ""
                local lines = { "[月]" .. base, tier_label }
                for _, line in ipairs(BuildDescLines(self.enchants, self._enchant_order)) do
                    table.insert(lines, line)
                end
                return table.concat(lines, "\n")
            end
        end
    end

end

---------------------------------------------------------------------
-- 清理
---------------------------------------------------------------------
function MoonMobEnhance:OnDeath()
    -- 清理各附魔的 handler 和 task
    for eid, data in pairs(self.enchants) do
        local st = data.state
        if st._attack_handler then
            self.inst:RemoveEventCallback("onhitother", st._attack_handler)
        end
        if st._attacked_handler then
            self.inst:RemoveEventCallback("attacked", st._attacked_handler)
        end
        if st._kill_handler then
            self.inst:RemoveEventCallback("onkillother", st._kill_handler)
        end
        if st._update_task then
            st._update_task:Cancel()
        end

        -- 调用附魔的 on_remove 清理
        if data.cfg and data.cfg.on_remove then
            data.cfg.on_remove(self.inst, st)
        end
    end
    self.enchants = {}
    self._enchant_order = nil

    -- 还原 DoDelta（仅当 DoDelta 仍是自己的 hook 时才还原，
    -- 避免覆盖其他 mod 叠在上面的 hook，导致死后仍被调用的旧链崩溃）
    if self._damage_hooked and self._origin_DoDelta then
        local health = self.inst.components.health
        if health and health.DoDelta == self._hook_fn then
            health.DoDelta = self._origin_DoDelta
        end
    end
    self._hook_fn = nil
    self._damage_hooked = false
    self._defense_hooked = false
    self.defense_enabled = false
    self._origin_DoDelta = nil
end

---------------------------------------------------------------------
-- 注册组件
---------------------------------------------------------------------
return MoonMobEnhance
