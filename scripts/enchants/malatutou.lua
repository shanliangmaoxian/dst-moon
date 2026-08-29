-- 小月亮 附魔：麻辣兔头
-- +15%移速，战斗中/被追击 +22% 移速
-- 血量低于30%时立刻瞬移到附近随机位置，原地留个假身吸引仇恨（120s冷却）
-- 收获/采集时有3%率多一份
-- 有1%概率触发一次暴击（自身武器攻击值*822%）
-- 极低概率产一个惊喜种子在背包里

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

-- ======== 假身辅助函数 ========

local function spawn_decoy(owner)
    local x, y, z = owner.Transform:GetWorldPosition()

    -- 生成一个兔人作为假身（有战斗AI，会吸引仇恨）
    local decoy = _G.SpawnPrefab("bunnyman")
    if not decoy then return end

    decoy.Transform:SetPosition(x, y, z)

    -- 麻辣兔头配色：红橙色半透明
    if decoy.AnimState then
        decoy.AnimState:SetMultColour(1, 0.4, 0.2, 0.7)
        decoy.AnimState:SetAddColour(0.5, 0.15, 0, 0)
    end

    -- 移除可能干扰的种族标签
    local tags_to_remove = { "rabbit", "bunnyman", "monster" }
    for _, tag in ipairs(tags_to_remove) do
        if decoy:HasTag(tag) then decoy:RemoveTag(tag) end
    end

    -- 标记为假身
    decoy:AddTag("decoy")
    decoy:AddTag("friendly")
    decoy:AddTag("notarget")

    -- 假身名称
    if decoy.components.named then
        decoy.components.named:SetName("麻辣兔头 · 假身")
    end

    -- 给假身大量血量让它多撑一会儿
    if decoy.components.health then
        decoy.components.health:SetMaxHealth(500)
        decoy.components.health:SetCurrentHealth(500)
    end

    -- 假身不攻击
    if decoy.components.combat then
        decoy.components.combat:SetTarget(nil)
        local oldSetTarget = decoy.components.combat.SetTarget
        decoy.components.combat.SetTarget = function(self, target)
            -- 只吸引仇恨但不真的攻击
            return
        end
    end

    -- 吸引周围敌人攻击假身
    local enemies = _G.TheSim:FindEntities(x, y, z, 12, { "_combat" }, { "INLIMBO", "FX", "NOCLICK", "DECOR", "player", "playerghost", "friendly", "companion" })
    for _, enemy in ipairs(enemies) do
        if enemy:IsValid() and enemy.components.combat and not enemy:HasTag("player") then
            -- 让敌人攻击假身
            enemy.components.combat:SetTarget(decoy)
            -- 强制仇恨
            pcall(function()
                if enemy.components.combat.Sally then
                    enemy.components.combat:Sally()
                end
            end)
        end
    end

    -- 6秒后假身消失
    decoy:DoTaskInTime(6, function()
        if decoy:IsValid() then
            decoy:Remove()
        end
    end)
end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_MLTT", {
        name = "麻辣兔头",
        client_text = "麻辣\n兔头",
        desc = "+15%移速，战斗中/被追击+22%移速\n血量<30%瞬移留假身(120s冷却)\n收获/采集3%多一份\n攻击1%触发822%暴击\n惊喜种子",
        check_desc = "big胆！再吃麻辣兔头辣你pp！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "malatutou", "Legend_MLTT", 1)
            if not owner._mltt_hooked then
                owner._mltt_hooked = true
                owner._mltt_in_combat = false
                owner._mltt_next_decoy_time = 0  -- 假身冷却时间戳

                -- 永久+15%移速
                local hh = owner.components.hh_player
                if hh then
                    hh:AddEffectValueByKey("addSpeedPercent", 15)
                end

                -- ========== 战斗状态管理 ==========
                local function enter_combat(owner)
                    if not owner._mltt_in_combat then
                        owner._mltt_in_combat = true
                        local hhp = owner.components.hh_player
                        if hhp then
                            hhp:AddEffectValueByKey("addSpeedPercent", 22)
                        end
                    end
                    -- 重置战斗超时
                    if owner._mltt_combat_task then
                        owner._mltt_combat_task:Cancel()
                    end
                    owner._mltt_combat_task = owner:DoTaskInTime(5, function()
                        if owner:IsValid() and _G.Moon_HasEffect(owner, "malatutou") then
                            owner._mltt_in_combat = false
                            local hhp = owner.components.hh_player
                            if hhp then
                                hhp:ReduceEffectValueByKey("addSpeedPercent", 22)
                            end
                        end
                    end)
                end

                -- 血量低于30% ⇢ 瞬移 + 假身
                local function check_low_hp_teleport(owner)
                    local now = _G.GetTime and _G.GetTime() or 0
                    if now < owner._mltt_next_decoy_time then
                        return  -- 冷却中
                    end
                    local health = owner.components.health
                    if not health then return end
                    local hp_pct = health.currenthealth / health.maxhealth
                    if hp_pct > 0.3 then return end

                    -- 触发冷却
                    owner._mltt_next_decoy_time = now + 120

                    -- 原地生成假身
                    spawn_decoy(owner)

                    -- 瞬移到附近随机位置（3~8码）
                    local x, y, z = owner.Transform:GetWorldPosition()
                    local angle = math.random() * 2 * math.pi
                    local dist = 3 + math.random() * 5
                    local nx = x + math.cos(angle) * dist
                    local nz = z + math.sin(angle) * dist
                    owner.Transform:SetPosition(nx, y, nz)

                    if owner.components.talker then
                        owner.components.talker:Say("啊？辣死我了！瞬！")
                    end
                end

                -- 勾住 health:DoDelta 检测受伤
                local health = owner.components.health
                if health and not health._mltt_hooked_dodelta then
                    local oldDoDelta = health.DoDelta
                    health._mltt_old_dodelta = oldDoDelta
                    health.DoDelta = function(self, delta, overtime, cause, ...)
                        if delta < 0 then
                            if _G.Moon_HasEffect(owner, "malatutou") then
                                -- 进入战斗状态
                                enter_combat(owner)
                                -- 检查低血量瞬移
                                check_low_hp_teleport(owner)
                            end
                        end
                        return oldDoDelta(self, delta, overtime, cause, ...)
                    end
                end

                -- 监听主动攻击 → 进入战斗
                owner._mltt_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "malatutou") then return end
                    local target = data and data.target
                    if not target or not target:IsValid() then return end
                    if target == owner then return end

                    -- 进入战斗
                    enter_combat(owner)

                    -- 1%概率触发822%暴击
                    if math.random() <= 0.01 then
                        local hhp = owner.components.hh_player
                        if hhp then
                            hhp:AddEffectValueByKey("criticalHitRate", 100)
                            hhp:AddEffectValueByKey("criticalHitEffect", 722)  -- 额外722% + 基础100% = 822%
                            -- 下次攻击后还原
                            owner:DoTaskInTime(0, function()
                                if owner:IsValid() and hhp then
                                    hhp:ReduceEffectValueByKey("criticalHitRate", 100)
                                    hhp:ReduceEffectValueByKey("criticalHitEffect", 722)
                                end
                            end)
                            if owner.components.talker then
                                owner.components.talker:Say("麻辣暴击！822%！！")
                            end
                        end
                    end
                end
                owner:ListenForEvent("onattackother", owner._mltt_attack_handler)

                -- ========== 收获/采集 3%多一份 ==========
                owner._mltt_pick_handler = function(inst, data)
                    if not _G.Moon_HasEffect(owner, "malatutou") then return end
                    if data and data.loot and math.random() <= 0.03 then
                        if data.loot.prefab and owner.components.inventory then
                            local extra = _G.SpawnPrefab(data.loot.prefab)
                            if extra then
                                owner.components.inventory:GiveItem(extra, nil, owner:GetPosition())
                            end
                        end
                    end
                end
                owner:ListenForEvent("picksomething", owner._mltt_pick_handler)

                -- ========== 极低概率产惊喜种子 ==========
                -- 每480秒1%概率 ≈ 平均13小时一个种子
                owner._mltt_seed_task = owner:DoPeriodicTask(480, function()
                    if not _G.Moon_HasEffect(owner, "malatutou") then return end
                    if not owner:IsValid() then return end
                    if math.random() <= 0.01 and owner.components.inventory then
                        local seed = _G.SpawnPrefab("ancienttree_seed")
                        if seed then
                            owner.components.inventory:GiveItem(seed, nil, owner:GetPosition())
                            if owner.components.talker then
                                owner.components.talker:Say("咦？背包里多了个种子…")
                            end
                        end
                    end
                end)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "malatutou", "Legend_MLTT", 1)
            if not _G.Moon_HasEffect(owner, "malatutou") then
                -- 还原移速
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("addSpeedPercent", 15)
                    if owner._mltt_in_combat then
                        hh:ReduceEffectValueByKey("addSpeedPercent", 22)
                    end
                end

                -- 还原 DoDelta
                local health = owner.components.health
                if health and health._mltt_old_dodelta then
                    health.DoDelta = health._mltt_old_dodelta
                    health._mltt_old_dodelta = nil
                end

                -- 清理定时任务
                if owner._mltt_combat_task then
                    owner._mltt_combat_task:Cancel()
                    owner._mltt_combat_task = nil
                end
                if owner._mltt_seed_task then
                    owner._mltt_seed_task:Cancel()
                    owner._mltt_seed_task = nil
                end

                -- 清理事件监听
                if owner._mltt_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._mltt_attack_handler)
                    owner._mltt_attack_handler = nil
                end
                if owner._mltt_pick_handler then
                    owner:RemoveEventCallback("picksomething", owner._mltt_pick_handler)
                    owner._mltt_pick_handler = nil
                end

                owner._mltt_in_combat = nil
                owner._mltt_next_decoy_time = nil
                owner._mltt_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_MLTT", 0.01)
end)
