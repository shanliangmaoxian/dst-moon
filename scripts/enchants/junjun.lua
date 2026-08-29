-- 小月亮 附魔：君可知
-- 君临天下 — 每次受击限伤不超过最大生命15%，触发限伤后获得0.5秒无敌帧
-- 每次触发限伤叠1层「铁壁」：+5%减伤，持续15秒（最多6层=30%）
-- 无敌结束时对周围6码敌人造成攻击力200%范围伤害（内置冷却5秒）

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_JUNJUN", {
        name = "君可知",
        client_text = "君可\n知",
        desc = "受击限伤最大生命15%+无敌0.5秒\n叠铁壁减伤最多30%\n无敌结束200%范围伤害(冷却5秒)",
        check_desc = "坚如磐石，君临天下！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "junjun", "Legend_JUNJUN", 1)
            if not owner._junjun_hooked then
                owner._junjun_hooked = true

                -- 铁壁叠层状态
                owner._junjun_armor_stacks = 0
                owner._junjun_armor_task = nil
                owner._junjun_invincible = false
                owner._junjun_last_roar_time = 0

                -- 更新减伤
                local function updateArmor()
                    local hh = owner.components.hh_player
                    if not hh then return end
                    -- 先清除旧值
                    hh:ReduceEffectValueByKey("absorbDamage", 30)
                    -- 应用当前层数
                    local stacks = owner._junjun_armor_stacks or 0
                    if stacks > 0 then
                        hh:AddEffectValueByKey("absorbDamage", stacks * 5)
                    end
                end

                -- 添加铁壁层数
                local function addArmorStack()
                    if not _G.Moon_HasEffect(owner, "junjun") then return end
                    if not owner:IsValid() then return end
                    owner._junjun_armor_stacks = math.min((owner._junjun_armor_stacks or 0) + 1, 6)

                    -- 重置过期计时器
                    if owner._junjun_armor_task then
                        owner._junjun_armor_task:Cancel()
                    end
                    owner._junjun_armor_task = owner:DoTaskInTime(15, function()
                        owner._junjun_armor_stacks = 0
                        updateArmor()
                        if owner.components.talker then
                            owner.components.talker:Say("铁壁消散...")
                        end
                    end)

                    updateArmor()

                    -- 叠层提示
                    if owner.components.talker then
                        local stack_msg = owner._junjun_armor_stacks .. "/6"
                        local names = {"铁壁·初", "铁壁·固", "铁壁·坚", "铁壁·钢", "铁壁·磐", "铁壁·极"}
                        owner.components.talker:Say(names[owner._junjun_armor_stacks] or "铁壁·极")
                    end
                end

                -- 战吼：范围内反击
                local function roarBack()
                    local now = _G.GetTime()
                    if now - (owner._junjun_last_roar_time or 0) < 5 then return end
                    owner._junjun_last_roar_time = now

                    local x, y, z = owner.Transform:GetWorldPosition()
                    -- 找攻击力
                    local damage = 50
                    if owner.components.combat then
                        damage = owner.components.combat.defaultdamage or 50
                    end
                    local roar_damage = damage * 2.0

                    -- 范围伤害
                    local enemies = _G.TheSim:FindEntities(x, y, z, 6, { "_combat" })
                    for _, enemy in ipairs(enemies) do
                        if enemy ~= owner and enemy:IsValid()
                            and enemy.components.health and not enemy.components.health:IsDead() then
                            enemy.components.health:DoDelta(-roar_damage, false, "junjun_roar")
                        end
                    end

                    if owner.components.talker then
                        owner.components.talker:Say("战吼！")
                    end

                    -- 屏幕震动
                    _G.pcall(function()
                        owner.components.playercontroller:ShakeCamera("FULLSCREEN", 0.3, 0.05, 0.1, 2)
                    end)
                end

                -- 限伤 + 无敌帧 + 铁壁 + 战吼
                local health = owner.components.health
                if health and not health._junjun_hooked_dodelta then
                    local oldDoDelta = health.DoDelta
                    health._junjun_old_dodelta = oldDoDelta
                    health.DoDelta = function(self, delta, overtime, cause, ...)
                        -- 只拦截伤害(负值)
                        if delta < 0 and cause ~= "junjun_roar" then
                            if _G.Moon_HasEffect(owner, "junjun") and owner:IsValid() then
                                local damage = -delta

                                -- 无敌帧期间免疫所有伤害
                                if owner._junjun_invincible then
                                    return oldDoDelta(self, 0, overtime, cause, ...)
                                end

                                -- 限伤：不超过最大生命15%
                                local max_hp = owner.components.health.maxhealth or 150
                                local cap = max_hp * 0.15
                                if damage > cap then
                                    damage = cap

                                    -- 触发限伤 → 无敌帧0.5秒
                                    owner._junjun_invincible = true
                                    owner:DoTaskInTime(0.5, function()
                                        if owner:IsValid() then
                                            owner._junjun_invincible = false
                                            -- 无敌结束时战吼
                                            roarBack()
                                        end
                                    end)

                                    -- 叠铁壁层
                                    addArmorStack()
                                end

                                return oldDoDelta(self, -damage, overtime, cause, ...)
                            end
                        end
                        return oldDoDelta(self, delta, overtime, cause, ...)
                    end
                    health._junjun_hooked_dodelta = true
                end
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "junjun", "Legend_JUNJUN", 1)
            if not _G.Moon_HasEffect(owner, "junjun") then
                -- 清除铁壁减伤
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("absorbDamage", 30)
                end

                if owner._junjun_armor_task then
                    owner._junjun_armor_task:Cancel()
                    owner._junjun_armor_task = nil
                end

                -- 还原 DoDelta
                local health = owner.components.health
                if health and health._junjun_old_dodelta then
                    health.DoDelta = health._junjun_old_dodelta
                    health._junjun_old_dodelta = nil
                    health._junjun_hooked_dodelta = nil
                end

                owner._junjun_hooked = nil
                owner._junjun_armor_stacks = nil
                owner._junjun_invincible = nil
                owner._junjun_last_roar_time = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_JUNJUN", 0.01)
end)
