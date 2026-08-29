-- 小月亮 附魔：养猫客
-- 每60秒召唤一只浣猫（上限4只），永久存在
-- 每只浣猫：攻速+12%，移速+15%
-- 每120秒一次：浣猫牺牲挡刀（挡刀后2秒无敌）
-- 浣猫每30秒捡物报恩，5%概率带鱼（已注释：暂时停用报恩）
-- 夜眼：夜晚额外+15%移速

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

-- ======== 浣猫管理 ========

-- 清理已死亡的浣猫
local function cleanup_cats(owner)
    if not owner._ymk_cats then
        owner._ymk_cats = {}
        return
    end
    local alive = {}
    for _, cat in ipairs(owner._ymk_cats) do
        if cat and cat:IsValid() then
            table.insert(alive, cat)
        end
    end
    owner._ymk_cats = alive
end

-- 获取存活浣猫数量
local function alive_cat_count(owner)
    cleanup_cats(owner)
    return #(owner._ymk_cats or {})
end

-- 更新属性加成
local function refresh_buffs(owner)
    local hh = owner.components.hh_player
    if not hh then return end

    local count = alive_cat_count(owner)
    local prev = owner._ymk_prev_cat_count or 0

    if prev ~= count then
        if prev > 0 then
            hh:ReduceEffectValueByKey("atk_speed", prev * 12)
            hh:ReduceEffectValueByKey("addSpeedPercent", prev * 15)
        end
        if count > 0 then
            hh:AddEffectValueByKey("atk_speed", count * 12)
            hh:AddEffectValueByKey("addSpeedPercent", count * 15)
        end
        owner._ymk_prev_cat_count = count

        if owner.components.talker then
            if count == 4 then
                owner.components.talker:Say("四只猫猫齐聚！圆满！")
            elseif count > prev then
                owner.components.talker:Say("喵~新伙伴来了！")
            elseif count < prev and count > 0 then
                owner.components.talker:Say("猫猫少了一只…")
            elseif count == 0 then
                owner.components.talker:Say("猫猫都不在了…")
            end
        end
    end
end

-- 召唤一只浣猫
local function spawn_cat(owner)
    local x, y, z = owner.Transform:GetWorldPosition()

    local cat = _G.SpawnPrefab("catcoon")
    if not cat then return nil end

    cat.Transform:SetPosition(x, y, z)

    -- 外观：淡金色微光
    if cat.AnimState then
        cat.AnimState:SetMultColour(1, 0.9, 0.7, 1)
        cat.AnimState:SetAddColour(0.3, 0.2, 0, 0)
    end

    -- 摘除可能干扰的标签
    local tags_to_remove = { "cat", "animal" }
    for _, tag in ipairs(tags_to_remove) do
        if cat:HasTag(tag) then cat:RemoveTag(tag) end
    end

    -- 跟随玩家
    if cat.components.follower then
        cat.components.follower:SetLeader(owner)
    end

    -- 友军标签
    cat:AddTag("companion")
    cat:AddTag("friendly")
    cat:AddTag("notarget")

    -- 不主动攻击
    if cat.components.combat then
        cat.components.combat:SetTarget(nil)
        local oldSetTarget = cat.components.combat.SetTarget
        cat.components.combat.SetTarget = function(self, target)
            if target and target:IsValid() and not target:HasTag("player") and not target:HasTag("companion") then
                -- 只反击攻击猫的敌人，不主动攻击
                return oldSetTarget(self, target)
            end
            return
        end
    end

    -- 玩家无法攻击猫
    if cat.components.health then
        local oldDoDelta = cat.components.health.DoDelta
        cat.components.health.DoDelta = function(self, delta, overtime, cause, ...)
            if delta < 0 then
                local args = { ... }
                for _, arg in ipairs(args) do
                    if type(arg) == "table" and arg.IsValid and arg:IsValid() and arg:HasTag("player") then
                        return
                    end
                end
            end
            return oldDoDelta(self, delta, overtime, cause, ...)
        end
    end

    -- 猫的报恩：每30秒捡附近掉落物（已注释：暂时停用）
    --[[
    cat._ymk_gift_task = cat:DoPeriodicTask(30, function()
        if not cat:IsValid() or not owner:IsValid() then return end
        if not owner.components.inventory then return end
        if not _G.Moon_HasEffect(owner, "yangmaoke") then return end

        local cx, cy, cz = cat.Transform:GetWorldPosition()
        local items = _G.TheSim:FindEntities(cx, cy, cz, 5, {},
            { "INLIMBO", "FX", "NOCLICK", "DECOR", "player", "monster", "_combat", "companion", "friendly", "catcoon" })
        for _, item in ipairs(items) do
            if item:IsValid() and item.components.inventoryitem and not item.components.inventoryitem:IsHeld() then
                -- 捡起物品给主人
                owner.components.inventory:GiveItem(item, nil, owner:GetPosition())
                -- 5%概率额外带条鱼
                if math.random() <= 0.05 then
                    local fish = _G.SpawnPrefab("pondfish")
                    if fish then
                        owner.components.inventory:GiveItem(fish, nil, owner:GetPosition())
                    end
                end
                break
            end
        end
    end)
    ]]

    table.insert(owner._ymk_cats, cat)
    refresh_buffs(owner)

    return cat
end

-- ======== 注册附魔 ========

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    _G.AddSpecialEquipEffect("Legend_YANGMAOKE", {
        name = "养猫客",
        client_text = "养猫\n客",
        desc = "每60秒召浣猫(上限4)\n每只:攻速+12%,移速+15%\n浣猫牺牲挡刀(120s冷却)\n挡刀后2s无敌\n夜晚额外+15%移速",
        check_desc = "与猫同居，岁月静好…",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,

        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "yangmaoke", "Legend_YANGMAOKE", 1)
            if not owner._ymk_hooked then
                owner._ymk_hooked = true
                owner._ymk_cats = {}
                owner._ymk_prev_cat_count = 0
                owner._ymk_last_sacrifice_time = 0
                owner._ymk_invincible = false

                -- 夜眼 + 昼夜属性切换
                owner._ymk_night_buff_active = false
                owner._ymk_daynight_task = owner:DoPeriodicTask(1, function()
                    if not _G.Moon_HasEffect(owner, "yangmaoke") then return end
                    if not owner:IsValid() then return end

                    local is_night = _G.TheWorld.state.isnight
                    local hhp = owner.components.hh_player
                    if not hhp then return end

                    if is_night and not owner._ymk_night_buff_active then
                        hhp:AddEffectValueByKey("addSpeedPercent", 15)
                        owner._ymk_night_buff_active = true
                    elseif not is_night and owner._ymk_night_buff_active then
                        hhp:ReduceEffectValueByKey("addSpeedPercent", 15)
                        owner._ymk_night_buff_active = false
                    end
                end)

                -- 召唤定时器：每60秒一只
                owner._ymk_summon_task = owner:DoPeriodicTask(60, function()
                    if not _G.Moon_HasEffect(owner, "yangmaoke") then return end
                    if not owner:IsValid() then return end
                    if alive_cat_count(owner) >= 4 then return end

                    spawn_cat(owner)
                end)

                -- 立即召唤第一只
                spawn_cat(owner)

                -- 九命：钩住health:DoDelta，检测致命伤
                local health = owner.components.health
                if health and not health._ymk_hooked_dodelta then
                    local oldDoDelta = health.DoDelta
                    health._ymk_old_dodelta = oldDoDelta
                    health.DoDelta = function(self, delta, overtime, cause, ...)
                        if delta < 0 and not overtime then
                            local would_die = (self.currenthealth + delta) <= 0
                            if would_die and _G.Moon_HasEffect(owner, "yangmaoke") and not owner._ymk_invincible then
                                local now = _G.GetTime and _G.GetTime() or 0
                                if now >= owner._ymk_last_sacrifice_time + 120 then
                                    local count = alive_cat_count(owner)
                                    if count > 0 then
                                        -- 牺牲一只浣猫
                                        owner._ymk_last_sacrifice_time = now
                                        local cat = owner._ymk_cats[1]
                                        if cat and cat:IsValid() then
                                            if cat._ymk_gift_task then
                                                cat._ymk_gift_task:Cancel()
                                            end
                                            cat:Remove()
                                        end
                                        table.remove(owner._ymk_cats, 1)
                                        refresh_buffs(owner)

                                        if owner.components.talker then
                                            owner.components.talker:Say("喵呜…替我挡了一刀…")
                                        end

                                        -- 挡刀后 2 秒无敌
                                        owner._ymk_invincible = true
                                        health:SetInvincible(true)
                                        owner:DoTaskInTime(2, function()
                                            if owner:IsValid() and owner._ymk_invincible then
                                                owner.components.health:SetInvincible(false)
                                                owner._ymk_invincible = nil
                                            end
                                        end)

                                        return  -- 免疫该次伤害
                                    end
                                end
                            end
                        end
                        return oldDoDelta(self, delta, overtime, cause, ...)
                    end
                end
            end
        end,

        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "yangmaoke", "Legend_YANGMAOKE", 1)
            if not _G.Moon_HasEffect(owner, "yangmaoke") then
                -- 清理所有浣猫
                cleanup_cats(owner)
                for _, cat in ipairs(owner._ymk_cats or {}) do
                    if cat and cat:IsValid() then
                        if cat._ymk_gift_task then
                            cat._ymk_gift_task:Cancel()
                        end
                        cat:Remove()
                    end
                end
                owner._ymk_cats = {}

                -- 移除属性加成
                local hh = owner.components.hh_player
                if hh then
                    local prev = owner._ymk_prev_cat_count or 0
                    if prev > 0 then
                        hh:ReduceEffectValueByKey("atk_speed", prev * 12)
                        hh:ReduceEffectValueByKey("addSpeedPercent", prev * 15)
                    end
                    if owner._ymk_night_buff_active then
                        hh:ReduceEffectValueByKey("addSpeedPercent", 15)
                    end
                end

                -- 清理定时任务
                if owner._ymk_summon_task then
                    owner._ymk_summon_task:Cancel()
                    owner._ymk_summon_task = nil
                end
                if owner._ymk_daynight_task then
                    owner._ymk_daynight_task:Cancel()
                    owner._ymk_daynight_task = nil
                end

                -- 还原 DoDelta
                local health = owner.components.health
                if health and health._ymk_old_dodelta then
                    health.DoDelta = health._ymk_old_dodelta
                    health._ymk_old_dodelta = nil
                end

                -- 若还在无敌中,一并恢复
                if health and owner._ymk_invincible then
                    health:SetInvincible(false)
                    owner._ymk_invincible = nil
                end

                owner._ymk_hooked = nil
                owner._ymk_prev_cat_count = nil
                owner._ymk_last_sacrifice_time = nil
                owner._ymk_night_buff_active = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_YANGMAOKE", 0.01)
end)
