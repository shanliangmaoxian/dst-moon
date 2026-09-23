-- 小月亮 附魔：四季系列（季·春 / 季·夏 / 季·秋 / 季·冬）
-- 获取：对应季节击杀 boss(epic) 5‰ 掉落对应石头（不入 HH 掉落池，T0 专属档）
-- 四时一隅印记：按各自触发条件消耗 24% 总生命获得，最多 2 层，持续 60 秒
--   春：连续攻击 20 次 → 印记期间自身及周围友方每秒回 5%/10%，且无法获得其他回血；
--       受非致命伤回滚到上一血线（冷却 90 秒）
--   夏：被攻击累计失去 24% 总生命 → 移速 30%/60%，攻击 15%/30% 几率驱散目标全部 buff，
--       每失去 1% 生命获得 1% 免伤（最多 99%，自建乘法层，不走 HH absorbDamage 80% 上限）
--   秋：吃食物单次回精神 > 50 → 攻击力 40%/80%，每失去 1% 生命额外 1% 攻击力
--   冬：饱食度降至 50 以下 → 免疫冰冻 50%/100%，暴伤 100%/200%，每失去 1% 生命额外 1% 暴伤
-- 联动：获得任一季印记时，若已有其他季印记 → 声生不息 +2 层（二期套装联动标记）；
--       每获得一季印记 → 四季流转 +1 层（最多 2），免死一次，全部印记消失后消失
-- 共通：佩戴任一季附魔无法暴击（强制 criticalHitRate=0）
-- 二期待做：套装（四季齐全 → 真伤+必暴）、声生不息具体效果
-- 生命消耗保护：当前生命不足以扣 24% 时按「扣到剩 1 点」截断，永不致死

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

local LAYER_TIME   = 60      -- 印记持续时间（秒）
local HEALTH_COST  = 0.24    -- 触发消耗的总生命比例
local MAX_STACKS   = 2       -- 印记最大层数
local HEAL_RADIUS  = 10      -- 春治疗范围
local ROLLBACK_CD  = 90      -- 春血线回滚冷却
local SEASON_CHANCE = 0.005  -- 对应季节 boss 5‰ 掉落

local SEASONS = {
    jichun = {
        id = "Legend_JI_CHUN", name = "季·春", short = "春", season = "spring",
        text = "季\n春", color = { 0.30, 0.80, 0.35, 1 },
    },
    jixia = {
        id = "Legend_JI_XIA", name = "季·夏", short = "夏", season = "summer",
        text = "季\n夏", color = { 0.90, 0.45, 0.10, 1 },
    },
    jiqiu = {
        id = "Legend_JI_QIU", name = "季·秋", short = "秋", season = "autumn",
        text = "季\n秋", color = { 0.85, 0.65, 0.15, 1 },
    },
    jidong = {
        id = "Legend_JI_DONG", name = "季·冬", short = "冬", season = "winter",
        text = "季\n冬", color = { 0.35, 0.60, 0.90, 1 },
    },
}

-- =========================================================
-- 通用工具
-- =========================================================

local function AnySeasonEffect(owner)
    for key, cfg in pairs(SEASONS) do
        if _G.Moon_HasEffect(owner, key) then return true end
    end
    return false
end

local function GetStacks(owner, skey)
    local st = owner._ji_state
    return (st and st[skey] and st[skey].stacks) or 0
end

local function LostHealthPct(owner)
    local health = owner.components.health
    if not health then return 0 end
    local max = health.maxhealth or 100
    local cur = health.currenthealth or max
    if max <= 0 or cur >= max then return 0 end
    return (max - cur) / max
end

-- 消耗 24% 总生命并获得印记；血量不足时截断到剩 1 点，永不致死
local function TryGainSeason(owner, skey)
    local st = owner._ji_state
    if not st or st[skey].stacks >= MAX_STACKS then return end
    local health = owner.components.health
    if not health or health:IsDead() then return end
    local cost = math.min(health.maxhealth * HEALTH_COST, health.currenthealth - 1)
    if cost <= 0 then return end
    health:DoDelta(-cost, false, "ji_cost")

    st[skey].stacks = st[skey].stacks + 1
    st[skey].expire = _G.GetTime() + LAYER_TIME

    -- 声生不息：已有其他季节印记时 +2 层（二期套装联动标记）
    local has_other = false
    for k, _ in pairs(SEASONS) do
        if k ~= skey and st[k].stacks > 0 then has_other = true end
    end
    if has_other then
        owner._ji_shengsheng = (owner._ji_shengsheng or 0) + 2
    end
    -- 四季流转：+1 层免死（最多 2）
    owner._ji_sizhou = math.min((owner._ji_sizhou or 0) + 1, 2)

    if owner.components.talker then
        local extra = has_other and " 声生不息+2 四季流转+" .. owner._ji_sizhou
            or (owner._ji_sizhou and owner._ji_sizhou > 0 and " 四季流转+" .. owner._ji_sizhou or "")
        owner.components.talker:Say("「四时一隅·" .. SEASONS[skey].name:sub(4) .. "」×" .. st[skey].stacks .. extra)
    end
end

-- =========================================================
-- 动态数值（层数 + 已损生命比例 → HH 词条）
-- =========================================================

local function SetHHValue(owner, key, newval, applied_field)
    local hh = owner.components.hh_player
    if not hh then return end
    local old = owner[applied_field] or 0
    if old == newval then return end
    if old > 0 then
        hh:ReduceEffectValueByKey(key, old)
    end
    if newval > 0 then
        hh:AddEffectValueByKey(key, newval)
    end
    owner[applied_field] = newval
end

local function UpdateDynamic(owner)
    if not owner:IsValid() then return end
    local st = owner._ji_state
    if not st then return end
    local lost = math.floor(LostHealthPct(owner) * 100)

    -- 秋：攻击力 40%/层 + 每失去1%生命 +1%
    local atk = 0
    if st.jiqiu.stacks > 0 then atk = st.jiqiu.stacks * 40 + lost end
    SetHHValue(owner, "addComDamagePercent", atk, "_ji_applied_atk")

    -- 冬：暴伤 100%/层 + 每失去1%生命 +1%
    local crit = 0
    if st.jidong.stacks > 0 then crit = st.jidong.stacks * 100 + lost end
    SetHHValue(owner, "criticalHitEffect", crit, "_ji_applied_crit")

    -- 夏：移速 30%/层
    local spd = st.jixia.stacks * 30
    SetHHValue(owner, "addSpeedPercent", spd, "_ji_applied_spd")
end

-- =========================================================
-- 玩家级钩子（首次佩戴任一季附魔时安装）
-- =========================================================

local function EnsureOwnerInit(owner)
    if owner._ji_state then return end
    owner._ji_state = {}
    for k, _ in pairs(SEASONS) do
        owner._ji_state[k] = { stacks = 0, expire = 0 }
    end

    local health = owner.components.health
    if not health then return end

    -- 本 mod 内部伤害/治疗来源标识（免伤/封外疗钩子放行用）
    local function is_ji_cause(cause)
        return type(cause) == "string" and cause:sub(1, 3) == "ji_"
    end

    -- 夏免伤：自建乘法层（不受 HH absorbDamage 80% 硬上限约束），ji_ 前缀伤害不受影响
    if not owner._ji_mit_hooked then
        owner._ji_mit_hooked = true
        local old_dodelta = health.DoDelta
        health.DoDelta = function(self, delta, overtime, cause, ...)
            if delta < 0 and not is_ji_cause(cause) then
                local stacks = GetStacks(owner, "jixia")
                if stacks > 0 and owner:IsValid() then
                    local mitig = math.min(LostHealthPct(owner) * 100, 99) / 100
                    delta = delta * (1 - mitig)
                end
            end
            return old_dodelta(self, delta, overtime, cause, ...)
        end
    end

    -- 春封外疗：印记期间无法获得其他回血（ji_ 前缀来源放行）
    if not owner._ji_healblock_hooked then
        owner._ji_healblock_hooked = true
        local old_dodelta2 = health.DoDelta
        health.DoDelta = function(self, delta, overtime, cause, ...)
            if delta > 0
                    and not is_ji_cause(cause)
                    and GetStacks(owner, "jichun") > 0
                    and owner:IsValid() then
                delta = 0
            end
            return old_dodelta2(self, delta, overtime, cause, ...)
        end
    end

    -- 四季流转免死：致死伤害改为剩 1 点，消耗一层
    if not owner._ji_cheatdeath_hooked then
        owner._ji_cheatdeath_hooked = true
        local old_dodelta3 = health.DoDelta
        health.DoDelta = function(self, delta, overtime, cause, ...)
            if delta < 0
                    and (owner._ji_sizhou or 0) > 0
                    and owner:IsValid()
                    and not self:IsDead()
                    and (self.currenthealth or 0) + delta <= 0 then
                owner._ji_sizhou = owner._ji_sizhou - 1
                delta = -(self.currenthealth - 1)
                if owner.components.talker then
                    owner.components.talker:Say("四季流转！免死一次！（剩余" .. owner._ji_sizhou .. "层）")
                end
            end
            return old_dodelta3(self, delta, overtime, cause, ...)
        end
    end

    -- 攻击：春连击计数 + 夏驱散
    owner._ji_onattack = function(attacker, data)
        if not owner:IsValid() then return end
        -- 春：连续攻击 20 次
        if GetStacks(owner, "jichun") < MAX_STACKS then
            owner._ji_chun_count = (owner._ji_chun_count or 0) + 1
            if owner._ji_chun_count >= 20 then
                owner._ji_chun_count = 0
                TryGainSeason(owner, "jichun")
            end
        end
        -- 夏：15%/30% 几率驱散目标全部 buff
        local xia = GetStacks(owner, "jixia")
        local target = data and data.target
        if xia > 0 and target and target:IsValid()
                and math.random() <= xia * 0.15
                and target.components.debuffable then
            local removed = 0
            for debuff_name, _ in pairs(target.components.debuffable.debuffs or {}) do
                target.components.debuffable:RemoveDebuff(debuff_name)
                removed = removed + 1
            end
            if removed > 0 and owner.components.talker then
                owner.components.talker:Say("四时一隅·夏！驱散目标 " .. removed .. " 个增益！")
            end
        end
    end
    owner:ListenForEvent("onattackother", owner._ji_onattack)

    -- 被攻击：夏失去血累计 + 春血线回滚
    owner._ji_onattacked = function(inst, data)
        if not owner:IsValid() then return end
        -- 夏：累计被击损失
        local dmg = data and data.damage or 0
        if dmg > 0 and GetStacks(owner, "jixia") < MAX_STACKS then
            local threshold = (owner.components.health.maxhealth or 100) * HEALTH_COST
            owner._ji_xia_lost = math.min((owner._ji_xia_lost or 0) + dmg, threshold)
            if owner._ji_xia_lost >= threshold then
                owner._ji_xia_lost = 0
                TryGainSeason(owner, "jixia")
            end
        end
        -- 春：受非致命伤回滚到上一血线（冷却 90s）
        local health = owner.components.health
        if GetStacks(owner, "jichun") > 0
                and health and not health:IsDead()
                and owner._ji_chun_snapshot
                and _G.GetTime() >= (owner._ji_rollback_cd or 0)
                and health.currenthealth < owner._ji_chun_snapshot then
            owner._ji_rollback_cd = _G.GetTime() + ROLLBACK_CD
            health:DoDelta(owner._ji_chun_snapshot - health.currenthealth, false, "ji_rollback")
            if owner.components.talker then
                owner.components.talker:Say("四时一隅·春！时光回溯到上一血线！（冷却90秒）")
            end
        end
    end
    owner:ListenForEvent("attacked", owner._ji_onattacked)

    -- 秋：吃食物单次回精神 > 50
    owner._ji_oneatfood = function(inst, food)
        if not owner:IsValid() or GetStacks(owner, "jiqiu") >= MAX_STACKS then return end
        local sanity = owner.components.sanity
        if not sanity then return end
        local before = sanity.current
        owner:DoTaskInTime(0.3, function()
            if not owner:IsValid() or GetStacks(owner, "jiqiu") >= MAX_STACKS then return end
            local s2 = owner.components.sanity
            if s2 and s2.current - before > 50 then
                TryGainSeason(owner, "jiqiu")
            end
        end)
    end
    owner:ListenForEvent("oneatfood", owner._ji_oneatfood)

    -- 冬：饱食度降至 50 以下（上升沿触发）
    owner._ji_onhunger = function(inst, data)
        if not owner:IsValid() then return end
        local hunger = owner.components.hunger
        if not hunger then return end
        if hunger.current < 50 then
            if not owner._ji_dong_low then
                owner._ji_dong_low = true
                if GetStacks(owner, "jidong") < MAX_STACKS then
                    TryGainSeason(owner, "jidong")
                end
            end
        else
            owner._ji_dong_low = nil
        end
    end
    owner:ListenForEvent("hungerdelta", owner._ji_onhunger)

    -- 血量变化：刷新动态数值
    owner._ji_onhealthdelta = function()
        UpdateDynamic(owner)
    end
    owner:ListenForEvent("healthdelta", owner._ji_onhealthdelta)

    -- 主心跳：过期检查 + 春秒回/血线快照 + 免疫冰冻由 freezable 钩子承担
    owner._ji_tick_task = owner:DoPeriodicTask(1, function()
        if not owner:IsValid() then return end
        local st = owner._ji_state
        local now = _G.GetTime()
        local changed = false
        for k, _ in pairs(SEASONS) do
            if st[k].stacks > 0 and now > (st[k].expire or 0) then
                st[k].stacks = 0
                changed = true
            end
        end

        -- 全部印记消失：四季流转/声生不息清空，血线快照清空
        local any_stack = false
        for k, _ in pairs(SEASONS) do
            if st[k].stacks > 0 then any_stack = true end
        end
        if not any_stack then
            if owner._ji_sizhou or owner._ji_shengsheng then
                owner._ji_sizhou = nil
                owner._ji_shengsheng = nil
            end
            owner._ji_chun_snapshot = nil
        end

        -- 春：血线快照（只记录不低于当前快照的血量）+ 每秒治疗
        if st.jichun.stacks > 0 then
            local hp = owner.components.health
            if hp and not hp:IsDead() then
                local cur = hp.currenthealth
                if not owner._ji_chun_snapshot or cur >= owner._ji_chun_snapshot then
                    owner._ji_chun_snapshot = cur
                end
                local heal_pct = st.jichun.stacks * 0.05
                -- 自身
                hp:DoDelta(hp.maxhealth * heal_pct, false, "ji_chun_heal")
                -- 周围友方
                local x, y, z = owner.Transform:GetWorldPosition()
                for _, v in ipairs(_G.TheSim:FindEntities(x, y, z, HEAL_RADIUS, { "player" })) do
                    if v:IsValid() and v ~= owner and not v:HasTag("playerghost")
                            and v.components.health and not v.components.health:IsDead() then
                        v.components.health:DoDelta(
                            v.components.health.maxhealth * heal_pct, false, "ji_chun_heal")
                    end
                end
            end
        end

        if changed then UpdateDynamic(owner) end
    end, 1)
end

local function CleanupOwner(owner)
    if owner._ji_tick_task then
        owner._ji_tick_task:Cancel()
        owner._ji_tick_task = nil
    end
    local hh = owner.components.hh_player
    if hh then
        if owner._ji_applied_atk then hh:ReduceEffectValueByKey("addComDamagePercent", owner._ji_applied_atk) end
        if owner._ji_applied_crit then hh:ReduceEffectValueByKey("criticalHitEffect", owner._ji_applied_crit) end
        if owner._ji_applied_spd then hh:ReduceEffectValueByKey("addSpeedPercent", owner._ji_applied_spd) end
    end
    owner._ji_applied_atk = nil
    owner._ji_applied_crit = nil
    owner._ji_applied_spd = nil
    if owner._ji_onattack then
        owner:RemoveEventCallback("onattackother", owner._ji_onattack)
        owner._ji_onattack = nil
    end
    if owner._ji_onattacked then
        owner:RemoveEventCallback("attacked", owner._ji_onattacked)
        owner._ji_onattacked = nil
    end
    if owner._ji_oneatfood then
        owner:RemoveEventCallback("oneatfood", owner._ji_oneatfood)
        owner._ji_oneatfood = nil
    end
    if owner._ji_onhunger then
        owner:RemoveEventCallback("hungerdelta", owner._ji_onhunger)
        owner._ji_onhunger = nil
    end
    if owner._ji_onhealthdelta then
        owner:RemoveEventCallback("healthdelta", owner._ji_onhealthdelta)
        owner._ji_onhealthdelta = nil
    end
    owner._ji_state = nil
    owner._ji_sizhou = nil
    owner._ji_shengsheng = nil
    owner._ji_chun_snapshot = nil
    owner._ji_chun_count = nil
    owner._ji_xia_lost = nil
    owner._ji_dong_low = nil
    owner._ji_rollback_cd = nil
    -- DoDelta 包装不解包（wdsn 同款策略），靠 _ji_state == nil 短路所有分支
end

-- =========================================================
-- 附魔注册（四个）
-- =========================================================

local function MakeSeasonConfig(skey, cfg, desc)
    return {
        name = cfg.name,
        client_text = cfg.text,
        desc = desc,
        check_desc = "「" .. cfg.name .. "」对应季节击杀 boss 有几率掉落",
        can_add = false,
        only_one = true,
        is_special = true, -- 专属获取：不入 HH 掉落池
        client_color = cfg.color,
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, skey, cfg.id, 1)
            EnsureOwnerInit(owner)
            UpdateDynamic(owner)
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, skey, cfg.id, 1)
            if not AnySeasonEffect(owner) then
                CleanupOwner(owner)
            else
                UpdateDynamic(owner)
            end
        end,
    }
end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_JI_CHUN", MakeSeasonConfig("jichun", SEASONS.jichun,
        "连续攻击20次：消耗24%总生命获得印记（最多2层，持续60秒）\n印记期间：自身及周围友方每秒回血5%/10%，且无法获得其他回血\n受非致命伤回滚到上一血线（冷却90秒）"))
    GLOBAL.AddSpecialEquipEffect("Legend_JI_XIA", MakeSeasonConfig("jixia", SEASONS.jixia,
        "被击累计失去24%总生命：获得印记（最多2层，持续60秒）\n移速+30%/60%，攻击15%/30%几率驱散目标全部增益\n每失去1%生命获得1%免伤（最多99%）"))
    GLOBAL.AddSpecialEquipEffect("Legend_JI_QIU", MakeSeasonConfig("jiqiu", SEASONS.jiqiu,
        "吃食物单次回精神>50：消耗24%总生命获得印记（最多2层，持续60秒）\n攻击力+40%/80%，每失去1%生命额外+1%攻击力"))
    GLOBAL.AddSpecialEquipEffect("Legend_JI_DONG", MakeSeasonConfig("jidong", SEASONS.jidong,
        "饱食度降至50以下：消耗24%总生命获得印记（最多2层，持续60秒）\n免疫冰冻50%/100%，暴击伤害+100%/200%\n每失去1%生命额外+1%暴击伤害"))

    -- 专属获取：不入 HH 掉落池
    _G.Moon_RegisterEnchantDrop("Legend_JI_CHUN", 0)
    _G.Moon_RegisterEnchantDrop("Legend_JI_XIA", 0)
    _G.Moon_RegisterEnchantDrop("Legend_JI_QIU", 0)
    _G.Moon_RegisterEnchantDrop("Legend_JI_DONG", 0)
end)

-- =========================================================
-- 季节限定掉落：对应季节击杀 boss(epic) 5‰ 掉对应石头
-- =========================================================

AddPrefabPostInitAny(function(inst)
    if not _G.TheWorld or not _G.TheWorld.ismastersim then return end
    if not inst:HasTag("epic") then return end
    inst:ListenForEvent("death", function(victim, data)
        if not CFG.ENABLE_MORE_ENCHANTS then return end
        if not _G.Moon_IsHHEnabled() then return end
        local season = _G.TheWorld.state and _G.TheWorld.state.season
        local skey = nil
        for k, cfg in pairs(SEASONS) do
            if cfg.season == season then skey = k end
        end
        if not skey then return end
        if math.random() > SEASON_CHANCE then return end
        local ok, stone = _G.pcall(_G.HHSpawnStoneById, SEASONS[skey].id)
        if ok and stone then
            local pt = victim:GetPosition()
            local killer = data and data.afflicter
            if killer and killer:IsValid() and killer.components.inventory then
                killer.components.inventory:GiveItem(stone, nil, pt)
            else
                stone.Transform:SetPosition(pt:Get())
            end
        end
    end)
end)

-- =========================================================
-- 冬：免疫冰冻（freezable 钩子，1层=50%几率免冰，2层=完全免疫）
-- =========================================================

AddComponentPostInit("freezable", function(self)
    local _old_AddColdness = self.AddColdness
    self.AddColdness = function(self, cold, ...)
        local inst = self.inst
        if inst and inst:HasTag("player")
                and inst._ji_state
                and _G.Moon_HasEffect and _G.Moon_HasEffect(inst, "jidong") then
            local stacks = GetStacks(inst, "jidong")
            if stacks >= 2 then return end
            if stacks >= 1 and math.random() <= 0.5 then return end
        end
        return _old_AddColdness(self, cold, ...)
    end
end)

-- =========================================================
-- 共通：佩戴任一季附魔无法暴击（强制暴率为 0）
-- =========================================================

AddPlayerPostInit(function(inst)
    if not _G.TheWorld.ismastersim then return end
    -- hh_player 组件可能由 HH mod 稍后添加，轮询安装（最多 20 次 × 0.5s）
    local attempts = 0
    local try_hook
    try_hook = function()
        local hh = inst.components.hh_player
        if hh and not hh._ji_critic_hooked then
            hh._ji_critic_hooked = true
            local old_GetVal = hh.GetEffectValueByKey
            hh.GetEffectValueByKey = function(self, key, ...)
                if key == "criticalHitRate" and inst._ji_state
                        and _G.Moon_HasEffect and AnySeasonEffect(inst) then
                    return 0
                end
                return old_GetVal(self, key, ...)
            end
            return
        end
        attempts = attempts + 1
        if attempts < 20 then
            inst:DoTaskInTime(0.5, try_hook)
        end
    end
    inst:DoTaskInTime(0, try_hook)
end)

-- =========================================================
-- 春：队友施法时额外回血 5%/10%（挂钩 spellcaster）
-- =========================================================

AddComponentPostInit("spellcaster", function(self)
    local _old_CastSpell = self.CastSpell
    self.CastSpell = function(self, target, pos, ...)
        local result = { _old_CastSpell(self, target, pos, ...) }
        local caster = self.inst
        if _G.TheWorld.ismastersim and caster and caster:IsValid() then
            local x, y, z = caster.Transform:GetWorldPosition()
            for _, v in ipairs(_G.TheSim:FindEntities(x, y, z, HEAL_RADIUS, { "player" })) do
                if v:IsValid() and not v:HasTag("playerghost")
                        and v.components.health and not v.components.health:IsDead()
                        and v._ji_state and GetStacks(v, "jichun") > 0 then
                    local pct = GetStacks(v, "jichun") * 0.05
                    v.components.health:DoDelta(v.components.health.maxhealth * pct, false, "ji_chun_castheal")
                end
            end
        end
        return unpack(result)
    end
end)
